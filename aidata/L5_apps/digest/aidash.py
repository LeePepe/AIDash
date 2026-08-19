"""AIDash push boundary for the digest (ADR-16/17/23).

Two halves live here:

  1. A PURE payload transform (`parse_sections`, `build_briefing`) that maps the
     digest's structured trend series + prose sections into AIDash
     Briefing → Container → Card payloads. Numeric trends become a `metric` card
     (sparkline series + a ring gauge for the automation ratio); prose sections
     become `digest`/`insight`/`todoList` cards with clean plain-text bodies.
     No I/O, fully unit-testable.
  2. A BEST-EFFORT, NON-FATAL push path (`resolve_aidash_bin`,
     `ensure_app_running`, `push_briefing`) that talks to the `aidash` CLI over
     XPC. Every failure mode — no app installed, CLI missing, app won't launch
     (asleep Mac), XPC error — degrades to a `PushResult(ok=False, ...)` and a
     logged warning, NEVER a raise (ADR-16/23). The local md archive is the 必成
     sink and is always written before any push is attempted.

All subprocess / `open` / `pgrep` / bin-resolution interaction is injected so the
unit suite is hermetic and never launches the real app.
"""

from __future__ import annotations

import json
import logging
import re
import subprocess  # nosec B404 - used only via injected runner/glob helpers
import tempfile
import time
from dataclasses import dataclass, replace
from pathlib import Path
from typing import TYPE_CHECKING, Callable, Sequence

from config import AIDASH_BIN_FIXED, AIDASH_BIN_GLOB
from L5_apps.digest.card_policy import (
    FIRST_SCREEN_CARDS, MAX_ACTIONS, MAX_CARDS,
    CardCandidate, DataProfile, choose_card, select_with_budget,
)
from L5_apps.digest.cst import yesterday
from L5_apps.digest.trends import compute_trend

if TYPE_CHECKING:  # type-only; keeps aidash import free of serve/I-O
    # DigestSources is the actual annotation used below (as a string forward
    # ref); import it here so the annotation resolves and ruff sees no F821.
    # sources.py is never imported at runtime from this module.
    from L5_apps.digest.sources import DigestSources

log = logging.getLogger("aidata.digest.aidash")

# AIDASH_BIN_FIXED / AIDASH_BIN_GLOB are imported from config (single source of
# truth — the aidash_events L1 adapter resolves the same binary, and config is
# the layer-neutral home for the shared constants). AIDASH_APP_* below are L5-
# only (the digest push launches the .app bundle) and stay local by design.
# The .app bundle next to the CLI. Launching THIS exact bundle (not `open -a
# AIDash` by name, which LaunchServices may resolve to a stale registration)
# makes the running app the freshly-built one, whose LaunchdAgentInstaller then
# (re)bootstraps the plain-launchctl LaunchAgent pointing at this build — the
# fix that lets launchd broker the mach service to a dev build (2026-07-19).
AIDASH_APP_GLOB = (
    "Library/Developer/Xcode/DerivedData/"
    "AIDash-*/Build/Products/Debug/AIDash.app"
)
# Fixed install paths (scripts/dev/install-fixed-build.sh in the AIDash repo).
# These live OUTSIDE DerivedData, so a rebuild / `xcodebuild clean` / DerivedData
# purge can't churn them out from under the daily push — the stable Program the
# launchd mach service brokers to. Prefer these when present; the DerivedData
# globs remain the fallback so a dev box without a fixed install still works.
# `/Applications/AIDash.app` is absolute; the CLI installs under the user's
# ~/.local/bin (no sudo), resolved via Path.home() rather than a hardcoded user.
AIDASH_APP_FIXED = "/Applications/AIDash.app"
APP_NAME = "AIDash"
GENERATED_BY = "aidata-digest"

# Loud-failure sink: when a push cannot land (XPC never became healthy), append
# an actionable line here so a silent best-effort warning is not the only trace.
# Mirrors the existing `~/Development/AIDash/.aidash-state/cron-errors.log`
# convention (ADR-16/23: the digest still archives locally; this only records
# that the AIDash mirror is stale so it can be noticed and retried).
PUSH_ERROR_LOG = (
    "Development/AIDash/.aidash-state/aidash-push-errors.log"
)

# CardType priority mapping for the todoList payload (P0/P1/P2 → high/med/low).
_PRIORITY = {"P0": "high", "P1": "medium", "P2": "low"}

# Sparkline window: last N CST days of a series (chronological oldest→newest).
_SERIES_WINDOW = 14
# arrow (from trends.compute_trend) → contract Trend enum word.
_TREND_WORD = {"↑": "up", "↓": "down", "→": "flat"}


# ---------------------------------------------------------------------------
# Payload dataclasses (immutable).
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Card:
    id: str
    type: str
    size: str
    payload: dict
    style: str = "neutral"


@dataclass(frozen=True)
class Container:
    id: str
    title: str
    order: int
    cards: tuple[Card, ...]
    layout: str = "auto"
    style: str = "neutral"
    subtitle: str = ""


@dataclass(frozen=True)
class Briefing:
    date: str
    generated_by: str
    containers: tuple[Container, ...]


@dataclass(frozen=True)
class PushResult:
    ok: bool
    reason: str = ""
    published: bool = False


@dataclass(frozen=True)
class DeliveryState:
    """Last-known delivery/XPC health, persisted across briefings.

    Read at digest-build time to expose delivery health SEPARATELY from
    content-source health (MY-1438/MY-1450). Written after every push attempt.
    Freshness: `timestamp` is UTC ISO-8601; consumers compare against the
    current briefing date to detect staleness.
    """
    ok: bool
    reason: str = ""
    timestamp: str = ""  # UTC ISO-8601, e.g. "2026-08-19T04:01:23Z"


# ---------------------------------------------------------------------------
# Pure transform.
# ---------------------------------------------------------------------------
def parse_sections(md: str) -> dict[str, list[str]]:
    """Split md into {heading: [content lines]}; preamble under key ''."""
    sections: dict[str, list[str]] = {"": []}
    current = ""
    for line in md.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            sections[current] = []
        else:
            sections.setdefault(current, []).append(line)
    return {k: [ln for ln in v if ln.strip()] for k, v in sections.items()}


def _section(sections: dict[str, list[str]], needle: str) -> list[str]:
    for heading, body in sections.items():
        if needle and needle in heading:
            return body
    return []


def _health_line(sections: dict[str, list[str]]) -> str:
    for ln in sections.get("", []):
        if "数据源" in ln:
            return ln.lstrip("> ").strip()
    return ""


def _mmdd(report_date: str) -> str:
    # report_date is YYYY-MM-DD; slice (never BSD `date +%m%d`, per recipe).
    return f"{report_date[5:7]}{report_date[8:10]}"


def _cuid(mmdd: str, n: int) -> str:
    return f"11111111-{mmdd}-{n:04d}-0000-{n:012d}"


def _kuid(mmdd: str, n: int) -> str:
    return f"22222222-{mmdd}-{n:04d}-0000-{n:012d}"


def _todo_items(todo_lines: list[str]) -> list[dict]:
    items: list[dict] = []
    for ln in todo_lines:
        text = ln.lstrip("- ").strip()
        prio = "medium"
        for tag, mapped in _PRIORITY.items():
            if text.startswith(tag):
                prio = mapped
                text = text[len(tag):].lstrip(": ").strip()
                break
        items.append({"title": text, "priority": prio})
    return items


# Action rank for the cap below: a P0 must survive where a P2 does not.
_PRIORITY_RANK = {"high": 0, "medium": 1, "low": 2}


def _capped_actions(items: list[dict]) -> list[dict]:
    """The day's actions, trimmed to the budget (§design 3: 行动最多 3 项).

    A list of ten things to do today is a list of zero things that will get
    done, so the cap is a feature rather than a truncation to apologise for.
    The trim is by PRIORITY (stably — equal priorities keep authored order), so
    what survives is the top of the list rather than whatever happened to be
    written first.
    """
    ranked = sorted(items, key=lambda it: _PRIORITY_RANK.get(it["priority"], 1))
    return ranked[:MAX_ACTIONS]


# ---- plain-text bodies (BUG 2: card `body` is a String, never markdown) ----
_MD_PREFIX = re.compile(r"^\s*(?:#{1,6}\s+|[-*+]\s+|>\s+)")


def _strip_md(line: str) -> str:
    """Drop a single leading markdown marker (#/-/*/+/>) from one line."""
    return _MD_PREFIX.sub("", line).strip()


def _plain_summary(must_see: str) -> str:
    """The overview body: short clean prose — no `##`/`- `/`> ` markdown.

    Takes only the leading TL;DR prose (the 点评 line + any preamble before the
    first `## ` section header) — the numeric trends, TODO and 可改良 become their
    own cards, so the overview body must not repeat them. Falls back to the whole
    stripped text when there is no header (e.g. a degraded "数据缺失" summary).
    """
    lines = must_see.splitlines()
    preamble = []
    for ln in lines:
        if ln.strip().startswith("## "):
            break
        preamble.append(ln)
    chosen = preamble if any(p.strip() for p in preamble) else lines
    parts = [_strip_md(ln) for ln in chosen if ln.strip()]
    return " · ".join(p for p in parts if p) or "（无摘要）"


def _lines_body(lines: list[str]) -> str:
    return "\n".join(_strip_md(ln) for ln in lines)


# ---- metric items (BUG 1: numeric trends → `metric` card, not `trending`) ---
def _sparkline(series: Sequence[tuple[str, float]], reported_day: str,
               window: int = _SERIES_WINDOW) -> list[float]:
    """Last `window` days of `series` up to reported_day, oldest→newest floats.

    Source series are newest-first (day, value) tuples; we sort ascending by CST
    day (ISO strings sort chronologically), drop anything after the reported day,
    keep the most-recent `window`, and emit plain float values left-to-right.
    """
    rows = sorted((d, v) for d, v in series if d <= reported_day)
    return [float(v) for _, v in rows[-window:]]


def _metric_item(label: str, series: Sequence[tuple[str, float]], unit: str,
                 higher_is_better: bool | None, report_date: str) -> dict | None:
    """One `metric` Item with a sparkline, or None when the day has no value."""
    reported_day = yesterday(report_date)
    if reported_day not in dict(series):
        return None                          # guard: every Item needs a value
    trend = compute_trend(list(series), report_date)
    item: dict = {
        "label": label,
        "value": round(trend.today, 2),
        "trend": _TREND_WORD.get(trend.arrow, "flat"),
        "series": _sparkline(series, reported_day),
    }
    if unit:
        item["unit"] = unit
    if higher_is_better is not None:
        item["higherIsBetter"] = higher_is_better
    return item


def _ratio_item(series: Sequence[tuple[str, float]],
                report_date: str) -> dict | None:
    """Automation占比 as a ring-gauge Item: ratio in 0..1 (contract-clamped)."""
    reported_day = yesterday(report_date)
    m = dict(series)
    if reported_day not in m:
        return None
    ratio = max(0.0, min(1.0, float(m[reported_day])))   # contract: 0...1
    trend = compute_trend(list(series), report_date)
    return {
        "label": "自动化占比",
        "value": round(ratio * 100, 1),
        "unit": "%",
        "ratio": ratio,
        "trend": _TREND_WORD.get(trend.arrow, "flat"),
        "higherIsBetter": True,
    }


def _raven_specs(sources: "DigestSources") -> list[tuple]:
    """(label, series, unit, higherIsBetter) for the always-present raven metrics."""
    r = sources.raven
    return [
        ("成本", r.cost, "$", False),
        ("Token", r.tokens, "", None),
        ("请求数", r.requests, "", None),
        ("浪费额", r.waste, "$", False),
        ("完成任务", r.pipeline_completed, "", True),
        ("会话数", r.sessions, "", True),
    ]


def _metric_items(sources: "DigestSources", report_date: str) -> list[dict]:
    """Build every valid metric Item (sparkline metrics + automation ring)."""
    items: list[dict] = []
    for label, series, unit, higher in _raven_specs(sources):
        item = _metric_item(label, series, unit, higher, report_date)
        if item:
            items.append(item)
    if sources.multica.health.state == "ok":
        item = _metric_item("完成 issue", sources.multica.completed, "", True,
                            report_date)
        if item:
            items.append(item)
    if sources.ado.health.state == "ok":
        item = _metric_item("开 PR", sources.ado.opened, "", True, report_date)
        if item:
            items.append(item)
    if sources.automation.health.state == "ok":
        item = _ratio_item(sources.automation.ratio, report_date)
        if item:
            items.append(item)
    return items


# ---- Item-level de-duplication (§design 3, acceptance criterion 5) ----------
#
# The redundancy in this briefing is real, but it is not container-shaped, not
# card-shaped, and SMALLER than it looks — it is one row.
#
# `趋势指标` publishes one row per metric. When the per-project spend breakdown
# is on the page, its 成本 row reports the same total that breakdown decomposes,
# so the bare row carries nothing the split does not.
#
# EXACTLY ONE ROW, AND HERE IS THE EVIDENCE. `attribution/cost-by-project.sql`
# selects `ktokens` and `requests` alongside `cost_usd`, but
# `fetch_cost_by_project` reads only `project` / `cost_usd` / `cost_pct`, and
# `_bar_items` publishes label/value/valueText. So no token, request or session
# figure ever reaches a card. Treating `Token` as redundant deleted a signal
# nothing on the page replaced — a de-duplication that was a deletion.
#
# Two earlier attempts suppressed the whole CONTAINER and took four unrelated
# rows with it. Doing it here — inside the producer that owns the rows — is the
# granularity the redundancy actually has.
#
# Labels a published breakdown genuinely restates. Deliberately minimal: every
# addition must be justified by a field the provider card actually renders.
_SPEND_TOTAL_LABELS = ("成本",)

# Card id slots holding the per-project cost BREAKDOWN — the only card whose
# presence makes the bare cost row redundant.
#
# SLOT 32 ONLY (`attribution/cost-by-project`). Slot 33
# (`attribution/model-by-project`) is deliberately NOT here: it is a project ×
# model grain filtered to `cost_usd > 0` and folded to a top-5 whose trailing
# "Other" sums costs across pairs, so it does not reproduce the day's total
# cost and cannot stand in for it. Binding to it would drop the 成本 row on days
# when nothing on the page reports that total.
#
# NOT keyed on the `成本归因` container: that container is built from any of
# four inputs and can consist of the 人机杠杆 metric alone, which decomposes
# nothing.
_SPEND_BREAKDOWN_SLOTS = frozenset({32})


def _slot_of(card_id: str) -> int | None:
    """The `_kuid` slot number encoded in a card id, or None if unparseable.

    Ids are `22222222-<mmdd>-<slot:04d>-0000-<slot:012d>`; the third group is
    read rather than the last so the parse stays cheap and obvious. Never
    raises — an id from elsewhere simply matches nothing.
    """
    parts = card_id.split("-")
    if len(parts) < 3 or not parts[2].isdigit():
        return None
    return int(parts[2])


def _dedupe_metric_items(items: list[dict],
                         spend_breakdown_published: bool) -> list[dict]:
    """Drop metric rows a stronger PUBLISHED card already covers.

    Conditional on the stronger card actually reaching the reader, and that
    condition must be evaluated against the FINAL published set, not against
    "the producer built one". The budget can still trim the breakdown after it
    is built, and a row dropped in anticipation of a card that never ships
    leaves the page with neither — the signal deleted rather than
    de-duplicated. So this runs after `_apply_budget`, on what survived.

    Never returns an empty list when it was given a non-empty one. A metric
    payload requires `items.count >= 1`, so emptying the card would make the app
    reject it and the card would vanish silently — turning a de-duplication into
    a deletion. If every row is redundant there is nothing left to thin, so the
    card is left intact.
    """
    if not spend_breakdown_published:
        return items
    kept = [it for it in items if it.get("label") not in _SPEND_TOTAL_LABELS]
    return kept or items


def _dedupe_published(containers: tuple[Container, ...]) -> tuple[Container, ...]:
    """Thin duplicated rows out of the trend card, after the budget has run.

    Two conditions, and both are about what the reader ACTUALLY sees:

    1. **Ordering.** De-duplication asks "is this row already covered by
       something on the page?", and only the post-budget set can answer that.
       Running it earlier answers "did a producer build one?" instead, and gets
       it wrong whenever the budget later trims the provider.
    2. **Identity.** The provider is the per-project cost BREAKDOWN card, not
       the container that happens to hold it. `成本归因` is built from any of
       four inputs — it can consist of the 人机杠杆 metric alone, with no spend
       split in it — so keying on the container title dropped the cost row
       whenever any attribution data existed. Only the cost-by-project card
       (slot 32) qualifies; see `_SPEND_BREAKDOWN_SLOTS` for why the project ×
       model card does not.

    Pure: containers are rebuilt rather than mutated, and a briefing without
    both sides of the pair passes through untouched.
    """
    published_ids = {card.id for c in containers for card in c.cards}
    breakdown_published = any(
        _slot_of(card_id) in _SPEND_BREAKDOWN_SLOTS for card_id in published_ids
    )
    if not breakdown_published:
        return containers
    out: list[Container] = []
    for container in containers:
        if container.title != "趋势指标":
            out.append(container)
            continue
        cards = []
        for card in container.cards:
            items = card.payload.get("items")
            if not items:
                cards.append(card)
                continue
            kept = _dedupe_metric_items(items, True)
            cards.append(replace(card, payload={**card.payload, "items": kept}))
        out.append(replace(container, cards=tuple(cards)))
    return tuple(out)


def _overview_sections(sections: dict[str, list[str]]) -> list[dict]:
    """Real-data sections for the digest hero card.

    The overview digest previously carried only a one-line 点评 body and no
    sections. The AIDash app's EffectiveCardSize resolver treats a section-less,
    short-body digest as "thin" and downgrades hero→small, whose layout renders
    ONLY the title — so the body vanished and the card looked empty. Giving the
    digest 2+ real sections keeps it at hero (app: sections>=2 ⇒ hero) so title +
    body + sections all render.

    Both sections are built from data already in the parsed digest md — no
    padding: 昨日概况 mirrors the 昨日汇总 lines, 趋势要点 surfaces the most
    decision-relevant Trending lines (cost / waste / automation / sessions).
    Returns [] when neither has content (degraded digest stays section-less).
    """
    out: list[dict] = []

    summary = _section(sections, "昨日汇总")
    if summary:
        out.append({
            "heading": "昨日概况",
            "paragraphs": [_strip_md(ln) for ln in summary if _strip_md(ln)],
        })

    trending = _section(sections, "Trending")
    if trending:
        # Keep the lines that carry a decision signal, in priority order.
        wanted = ("成本", "浪费", "自动化", "会话", "请求", "Token")
        picked: list[str] = []
        for key in wanted:
            for ln in trending:
                clean = _strip_md(ln)
                if clean.startswith(key) and clean not in picked:
                    picked.append(clean)
                    break
        if picked:
            out.append({"heading": "趋势要点", "paragraphs": picked})

    return out


def _overview_container(mmdd: str, reported_day: str, must_see: str,
                        sections: dict[str, list[str]],
                        delivery: "DeliveryState | None" = None,
                        report_date: str = "") -> Container:
    """总览: the always-present digest card + optional data-health insight."""
    digest_payload = {
        "title": f"AI 使用日报 {reported_day}",
        "body": _plain_summary(must_see),
    }
    overview_sections = _overview_sections(sections)
    if overview_sections:
        digest_payload["sections"] = overview_sections
    cards = [Card(_kuid(mmdd, 1), "digest", "hero", digest_payload,
                  style="accent")]
    health = _health_line(sections)
    if health:
        cards.append(Card(_kuid(mmdd, 2), "insight", "wide",
                          {"title": "数据源健康", "body": _strip_md(health)},
                          style="warning"))
    # Delivery/XPC health — separate from content-source health (MY-1450).
    if delivery is not None and not delivery.ok:
        d_line = delivery_health_line(report_date, delivery)
        if d_line:
            cards.append(Card(_kuid(mmdd, 99), "insight", "wide",
                              {"title": "投递健康", "body": _strip_md(d_line)},
                              style="warning"))
    return Container(_cuid(mmdd, 1), "总览", 10, tuple(cards),
                     layout="auto", style="accent")


def _cost_improvement_body(ci) -> str:
    """Plain-text body for the real-data '可改良·成本' insight.

    Spend concentration (top models + %) + how much opus went to tiny outputs.
    Returns "" when there's no usable signal so the caller can skip the card.

    NOTE (research 2026-07-18): does NOT assert "switch to a cheaper model to
    save $X". Cheaper-per-token models can cost MORE per task (overthinking tax,
    OckBench: 7B burned 3.13x tokens → 57% dearer than 14B). So we report the
    neutral fact ("N 次 opus 请求只产出 <20 token") and let the user judge,
    rather than claiming a guaranteed saving. See
    docs/specs/2026-07-18-token-efficiency-research.md.
    """
    if ci is None or ci.health.state != "ok" or not ci.top_models:
        return ""
    lines: list[str] = []
    top = ci.top_models
    lead = top[0]
    lines.append(
        f"成本集中在 {lead.model}（占 {lead.pct_of_spend:.0f}%）"
        + (f"，前 {len(top)} 个模型合计 "
           f"{sum(m.pct_of_spend for m in top):.0f}%" if len(top) > 1 else "")
    )
    if ci.downgrade_usd > 0:
        lines.append(
            f"其中 {ci.downgrade_requests} 次 opus 请求只产出 <20 token（琐碎补全），"
            f"涉及 ${ci.downgrade_usd:.0f}——值得核查这些是否该走更小的模型"
        )
    return "\n".join(lines)


def _value_efficiency_body(ve) -> str:
    """Plain-text body for the '值不值·效率' insight (research 2026-07-18).

    Two research-backed signals over a rolling window: cost-per-completed-task
    (incl. failed-task spend) and output-token share (low ⇒ input/context-
    dominated). Deliberately framed as observations, not a verdict — there is no
    clean ROI multiple; single-day cost is noise, hence the N-day window.
    Returns "" when unusable.
    """
    if ve is None or ve.health.state != "ok":
        return ""
    if ve.cost_per_completed_task is None and ve.output_share_pct is None:
        return ""
    lines: list[str] = []
    w = ve.window_days
    if ve.cost_per_completed_task is not None:
        lines.append(
            f"近 {w} 天每完成任务约 ${ve.cost_per_completed_task:.0f}"
            f"（${ve.total_cost:.0f} / {ve.completed_tasks} 个，已含失败花费）"
        )
    if ve.output_share_pct is not None:
        lines.append(
            f"输出 token 仅占 {ve.output_share_pct:.1f}%——花费几乎全在读取"
            f"上下文（input 主导，符合 agentic 特征）"
        )
    return "\n".join(lines)


def _prose_containers(mmdd: str,
                      sections: dict[str, list[str]],
                      cost_improvement=None,
                      value_efficiency=None,
                      inbox_items=None,
                      model_tier_card=None) -> list[Container]:
    """昨日汇总 / 今日规划 / 可改良 — only for sections that have content."""
    out: list[Container] = []
    summary = _section(sections, "昨日汇总")
    if summary:
        out.append(Container(_cuid(mmdd, 3), "昨日汇总", 30,
            (Card(_kuid(mmdd, 4), "insight", "wide",
                  {"title": "昨日汇总", "body": _lines_body(summary)}),),
            layout="list"))
    # 今日规划 → real action inbox (§M3, goal ② 需要处理什么) when available,
    # else fall back to the markdown 今日 TODO section. The inbox merges stalls
    # / decisions / planned work / findings into one prioritized list.
    inbox = [{"title": it.title, "priority": it.priority} for it in (inbox_items or [])]
    todos = _capped_actions(inbox or _todo_items(_section(sections, "今日 TODO")))
    if todos:
        out.append(Container(_cuid(mmdd, 4), "今日规划", 40,
            (Card(_kuid(mmdd, 5), "todoList", "hero", {"items": todos},
                  style="accent"),), layout="list", style="accent"))
    improve = _section(sections, "可改良")
    cost_body = _cost_improvement_body(cost_improvement)
    value_body = _value_efficiency_body(value_efficiency)
    if improve or cost_body or value_body or model_tier_card is not None:
        cards: list[Card] = []
        # Value/efficiency card first (research-backed cost-per-task + output
        # share), then the cost-concentration card, then the markdown 可改良,
        # then the model-tier stackedBar (§design: 模型分层 融进现有 可改良).
        # All degrade gracefully to whatever data is available.
        if value_body:
            cards.append(Card(_kuid(mmdd, 8), "insight", "wide",
                              {"title": "值不值·效率", "body": value_body},
                              style="accent"))
        if cost_body:
            cards.append(Card(_kuid(mmdd, 7), "insight", "wide",
                              {"title": "可改良·成本", "body": cost_body},
                              style="warning"))
        if improve:
            cards.append(Card(_kuid(mmdd, 6), "insight", "wide",
                              {"title": "可改良", "body": _lines_body(improve)}))
        if model_tier_card is not None:
            cards.append(model_tier_card)
        out.append(Container(_cuid(mmdd, 5), "可改良", 50, tuple(cards),
                             layout="list"))
    return out


def _work_container(mmdd: str, work) -> "Container | None":
    """今日工作: per-project effort as a metric card (goal ① 做了什么, M2).

    Each project is one metric Item: value = assistant turns (proxy for effort),
    labeled in plain language ("次交互") rather than the internal "turns" jargon
    so a non-technical reader understands it (#3). context = sessions + output-
    token volume. Ordered by turns desc, capped so the card stays readable.
    Activity is NEUTRAL, not "higher is better": more interaction can mean rework
    or loops, so the metric must not be colored as good/bad. Returns None when
    there's no project data (degraded → container simply absent).
    """
    if work is None or work.health.state != "ok" or not work.projects:
        return None
    items: list[dict] = []
    for p in work.projects[:6]:
        items.append({
            "label": p.project,
            "value": p.turns,
            "unit": "次交互",
            "higherIsBetter": False,
            "context": (f"{p.sessions} 会话 · {p.out_ktok:.0f}k out"
                        if p.out_ktok >= 1 else f"{p.sessions} 会话"),
        })
    return Container(_cuid(mmdd, 6), "今日工作", 15,
                     (Card(_kuid(mmdd, 9), "metric", "wide", {"items": items}),),
                     layout="auto", style="accent")


# ---- GitHub tool-radar (§radar): curated watchlist → trending cards ----------
# One trending card per tier (值得现在看 / 拓展视野). Each item carries the new
# optional `delta`/`category` fields: the current app ignores unknown JSON keys
# (Codable), so pushing them is safe before the Swift side renders them (PR 2).
_TIER_TITLES = (
    ("now", "值得现在看", "accent"),
    ("horizon", "拓展视野", "neutral"),
)


def _radar_item(card) -> dict:
    """One trending Item from a RepoCard: repo, url, stars, delta, category, reason."""
    item: dict = {
        "title": card.repo,
        "url": card.url,
        "score": float(card.stars),
    }
    if card.star_delta is not None:
        item["delta"] = float(card.star_delta)   # app renders ▲/▼ pill
    if card.category:
        item["category"] = card.category
    if card.reason:
        item["reason"] = card.reason             # the "why it's worth a look" line
    return item


def _radar_topic(label: str, cards: list) -> str:
    """Topic line for a tier card: label, + the dominant related project only
    when it clearly dominates (>= half of the repos that matched any project).
    Otherwise stay plain so a diverse card isn't mislabeled with one project."""
    projects = [c.related_project for c in cards if c.related_project]
    if projects:
        top = max(set(projects), key=projects.count)
        if projects.count(top) * 2 >= len(cards):
            return f"{label} · 多关联 {top}"
    return label


def _radar_containers(mmdd: str, radar) -> list[Container]:
    """Build the 'GitHub 工具雷达' container (one trending card per tier).

    Returns [] when the radar is degraded/empty, so a missing source simply
    yields no container (never an empty card). Repos are already stars-desc from
    the L4 query; we just split by tier and keep that order.
    """
    if radar is None or radar.health.state != "ok" or not radar.cards:
        return []
    cards: list[Card] = []
    n = 10
    for tier, label, style in _TIER_TITLES:
        tier_repos = [c for c in radar.cards if c.tier == tier]
        if not tier_repos:
            continue
        payload = {
            "topic": _radar_topic(label, tier_repos),
            "items": [_radar_item(c) for c in tier_repos],
        }
        cards.append(Card(_kuid(mmdd, n), "trending", "hero", payload,
                          style=style))
        n += 1
    if not cards:
        return []
    return [Container(_cuid(mmdd, 7), "GitHub 工具雷达", 60, tuple(cards),
                      layout="auto")]


# ---------------------------------------------------------------------------
# batch-2 producers (L5 数据接入批2): map the new source bundles → barList /
# stackedBar / metric / trending / insight cards, grouped into the design's
# information architecture (§design 1). Every builder is DEGRADE-SAFE: it emits
# a card only when its source health is "ok" AND the data is non-empty, so a
# degraded source simply yields no card / no container (ADR-23) — never a hollow
# card and never a crash.
# ---------------------------------------------------------------------------
def _bar_items(bundle) -> list[dict]:
    """RankBundle → barList `items` (label/value/valueText/[semantic]).

    Emits `semantic` only when set (absent-safe: the app's Codable drops None),
    so a neutral row carries no key. Order is preserved (source is value-desc).
    """
    items: list[dict] = []
    for it in bundle.items:
        item: dict = {"label": it.label, "value": float(it.value),
                      "valueText": it.value_text}
        if it.semantic:
            item["semantic"] = it.semantic
        items.append(item)
    return items


def _bar_card(kuid: str, bundle, style: str = "neutral") -> "Card | None":
    """A barList Card from a RankBundle, or None when degraded/empty (ADR-23)."""
    if bundle is None or bundle.health.state != "ok" or not bundle.items:
        return None
    return Card(kuid, "barList", "wide", {"items": _bar_items(bundle)},
                style=style)


def _segments(bundle) -> list[dict]:
    """SegmentBundle/ModelTier → stackedBar `segments` (label/value/[semantic])."""
    segs: list[dict] = []
    for s in bundle.segments:
        seg: dict = {"label": s.label, "value": float(s.value)}
        if s.semantic:
            seg["semantic"] = s.semantic
        segs.append(seg)
    return segs


def _stacked_card(kuid: str, bundle, title: str,
                  style: str = "neutral") -> "Card | None":
    """A stackedBar Card, or None when degraded/empty (ADR-23)."""
    if bundle is None or bundle.health.state != "ok" or not bundle.segments:
        return None
    payload = {"segments": _segments(bundle)}
    if title:
        payload["title"] = title
    return Card(kuid, "stackedBar", "wide", payload, style=style)


def _series_metric_item(label: str, series, unit: str,
                        higher_is_better: bool | None,
                        context: str = "") -> dict | None:
    """A metric Item straight off a newest-first (bucket, value) series.

    Unlike `_metric_item` (which keys the value on yesterday-of-run and is for
    the daily raven trends), this takes the series' OWN latest bucket as the
    headline number, so it works for both daily (cache) and WEEKLY (rework)
    buckets whose key never equals a calendar `yesterday`. The sparkline is the
    last _SERIES_WINDOW values oldest→newest; the trend compares the two most
    recent buckets. Returns None on an empty series (degrade-safe)."""
    if not series:
        return None
    ordered = sorted(series)                 # oldest→newest by bucket key
    latest_val = float(ordered[-1][1])
    if len(ordered) >= 2:
        prev = float(ordered[-2][1])
        if prev == 0 or abs(latest_val - prev) / abs(prev) <= 0.05:
            trend = "flat"
        else:
            trend = "up" if latest_val > prev else "down"
    else:
        trend = "flat"
    item: dict = {
        "label": label,
        "value": round(latest_val, 2),
        "trend": trend,
        "series": [float(v) for _, v in ordered[-_SERIES_WINDOW:]],
    }
    if unit:
        item["unit"] = unit
    if higher_is_better is not None:
        item["higherIsBetter"] = higher_is_better
    if context:
        item["context"] = context
    return item


def _ai_efficiency_container(mmdd: str, ai, tool_cross=None) -> "Container | None":
    """🧠 AI 效能 (order 25, §design 差异化核心): cache/返工 metrics + 失败根因
    barList + 会话质量 stackedBar + 工具成本 barList + planner-gap insight. Only
    the cards whose source is healthy render; the container is omitted if none
    survive (ADR-23).
    """
    if ai is None:
        return None
    cards: list[Card] = []

    # 缓存命中率 + 返工率 → one metric card (two big-number items w/ sparkline).
    metric_items: list[dict] = []
    if ai.cache_health.state == "ok":
        ctx = ""
        if ai.cache_savings:
            _, latest_savings = sorted(ai.cache_savings)[-1]
            ctx = f"省 {latest_savings:.0f}% token 成本"
        cache_item = _series_metric_item("缓存命中率", ai.cache, "%", True, ctx)
        if cache_item:
            metric_items.append(cache_item)
    if ai.rework_health.state == "ok":
        rework_item = _series_metric_item("返工率", ai.rework, "%", False,
                                          "DORA 返工率 · 本周")
        if rework_item:
            metric_items.append(rework_item)
    if metric_items:
        cards.append(Card(_kuid(mmdd, 20), "metric", "wide",
                          {"items": metric_items}, style="accent"))

    # 失败根因 → barList (infra rows semantic="warning").
    failure_card = _bar_card(_kuid(mmdd, 21), ai.failure, style="warning")
    if failure_card:
        cards.append(failure_card)

    # 会话质量 → stackedBar (end_turn=good / max_tokens=warning).
    quality_card = _stacked_card(_kuid(mmdd, 22), ai.quality, "会话质量")
    if quality_card:
        cards.append(quality_card)

    # 工具成本 barList — belongs here rather than in 成本归因 because it is a
    # workflow question ("which tool drags the most weight, and have I handed
    # it off"), not a spend question. Ranked by tokens-per-call; the label
    # carries the automated share.
    tool_card = _bar_card(_kuid(mmdd, 36), tool_cross, style="neutral")
    if tool_card:
        cards.append(tool_card)

    # planner-gap 聚合 → insight (only when there IS a gap; a 0 count is not a
    # finding worth a card).
    if ai.planner_gap_health.state == "ok" and ai.planner_gap_count > 0:
        cards.append(Card(_kuid(mmdd, 23), "insight", "wide", {
            "title": "规划缺口",
            "body": (f"⚠️ {ai.planner_gap_count} 个 issue 有 Engineer 干活但没走 "
                     "Planner（该 spec 却跳过）——可 CLI 深钻 health/planner-gap"),
        }, style="warning"))

    if not cards:
        return None
    return Container(_cuid(mmdd, 8), "AI 效能", 25, tuple(cards),
                     layout="auto", style="accent",
                     subtitle="AI 效能因果度量 · 业界少见")


def _leverage_card(mmdd: str, lev) -> "Card | None":
    """One typed prompt, priced — the only human/machine ratio on the board.

    Rendered as a metric so the headline number reads at a glance; the
    secondary items give it context (a $40 prompt that fired 46 requests is a
    deep agentic loop, the same $40 over 3 requests is an expensive model).
    """
    if lev is None or getattr(lev, "health", None) is None:
        return None
    if lev.health.state != "ok" or not lev.prompts:
        return None
    # MetricPayload.Item.value is a Double in the Swift schema — a formatted
    # string ("$38.5") is rejected with schema.payload_decode_failed, and the
    # push logs only "card put exit 1", so the card silently vanishes from the
    # app while the local build still shows it. Keep the number numeric and put
    # the symbol in `unit`.
    items = [
        {"label": "每条输入成本", "value": round(lev.usd_per_prompt, 1),
         "unit": "USD", "trend": "flat"},
        {"label": "每条触发请求", "value": round(lev.requests_per_prompt, 1),
         "unit": "次", "trend": "flat"},
        {"label": "我发了", "value": float(lev.prompts), "unit": "条",
         "trend": "flat"},
    ]
    return Card(_kuid(mmdd, 34), "metric", "wide",
                {"title": "人机杠杆", "items": items})


def _attribution_container(mmdd: str, cost_by_project, model_by_project,
                           leverage=None, rework_by_workspace=None) -> "Container | None":
    """💸 成本归因 (order 22): WHY the trend arrows moved.

    Sits immediately after 趋势指标 (order 20) on purpose — it exists to
    explain the arrows directly above it. Every other card in the briefing
    reports a single dimension, so a "+968%" tells you something changed but
    not where to look; this splits the same spend across projects, then across
    project x model, then prices it against the one input that is mine.

    Cards are barLists + one metric (existing CardTypes, no new renderer).
    Omitted entirely when attribution is unavailable, rather than showing an
    empty frame (ADR-23).
    """
    cards: list[Card] = []
    project_card = _bar_card(_kuid(mmdd, 32), cost_by_project, style="neutral")
    if project_card:
        cards.append(project_card)
    model_card = _bar_card(_kuid(mmdd, 33), model_by_project, style="neutral")
    if model_card:
        cards.append(model_card)
    leverage_card = _leverage_card(mmdd, leverage)
    if leverage_card:
        cards.append(leverage_card)
    rework_card = _bar_card(_kuid(mmdd, 35), rework_by_workspace, style="neutral")
    if rework_card:
        cards.append(rework_card)
    if not cards:
        return None
    return Container(_cuid(mmdd, 11), "成本归因", 22, tuple(cards),
                     layout="auto", subtitle="钱花在哪个项目 · 哪个模型 · 每条输入值多少")


def _time_output_container(mmdd: str, app_focus, commit_by_repo) -> "Container | None":
    """⏱ 时间与产出 (order 28, §design): app 焦点 + 跨仓 commit barLists."""
    cards: list[Card] = []
    focus_card = _bar_card(_kuid(mmdd, 30), app_focus, style="neutral")
    if focus_card:
        cards.append(focus_card)
    commit_card = _bar_card(_kuid(mmdd, 31), commit_by_repo, style="neutral")
    if commit_card:
        cards.append(commit_card)
    if not cards:
        return None
    return Container(_cuid(mmdd, 9), "时间与产出", 28, tuple(cards),
                     layout="auto")


# Friendly topic → display label + chart-pill hint for the news radar.
_NEWS_TOPIC_LABEL = {
    "ai-tech": "AI · 科技",
    "finance": "财经",
    "us-china": "中美",
    "china": "中国",
    "world": "国际",
    "hn": "Hacker News",
}


def _news_container(mmdd: str, news) -> "Container | None":
    """📰 新闻雷达 (order 80, §design): newest headlines grouped by topic, each
    topic a `trending` card (reuses the GitHub-radar列表形态). Topics render in a
    stable design order; unknown topics fall to the end alphabetically."""
    if news is None or news.health.state != "ok" or not news.items:
        return None
    by_topic: dict[str, list] = {}
    for it in news.items:
        by_topic.setdefault(it.topic, []).append(it)
    order = list(_NEWS_TOPIC_LABEL.keys())

    def _topic_key(t: str) -> tuple:
        return (order.index(t) if t in order else len(order), t)

    cards: list[Card] = []
    n = 40
    for topic in sorted(by_topic, key=_topic_key):
        items = [{"title": it.title, "url": it.url,
                  "score": 0.0, "category": _NEWS_TOPIC_LABEL.get(topic, topic)}
                 for it in by_topic[topic]]
        cards.append(Card(_kuid(mmdd, n), "trending", "wide", {
            "topic": _NEWS_TOPIC_LABEL.get(topic, topic),
            "items": items,
        }))
        n += 1
    return Container(_cuid(mmdd, 10), "新闻雷达", 80, tuple(cards),
                     layout="auto")


def _model_tier_card(mmdd: str, model_tier) -> "Card | None":
    """模型分层 stackedBar (pure category, no semantic) for the 可改良 section
    (§design: 融进现有 '可改良' 而非独立卡)."""
    if (model_tier is None or model_tier.health.state != "ok"
            or not model_tier.segments):
        return None
    return _stacked_card(_kuid(mmdd, 19), model_tier, "模型分层占比")


# ---- 你最常收藏的卡型 (spec 005 T007/US5) -----------------------------------
def _card_interest_body(card_interest, top_n: int = 3) -> str:
    """Plain-text Top-N body: which card TYPES the user whole-card-stars most.

    Returns "" when there's no usable signal (no data / degraded source), so
    the caller can omit the card entirely (ADR-23) rather than render an empty
    insight. `card_interest.types` is already descending (behavior/card-interest
    orders by star_count desc, card_type asc as tiebreak)."""
    if card_interest is None or card_interest.health.state != "ok":
        return ""
    types = card_interest.types
    if not types:
        return ""
    lines = [f"{i}. {t.card_type} · {t.star_count} 次"
             for i, t in enumerate(types[:top_n], start=1)]
    return "\n".join(lines)


def _card_interest_container(mmdd: str, card_interest) -> "Container | None":
    """卡型兴趣: one insight card, "你最常收藏的卡型 Top-N" (spec 005 US5).

    Reuses the existing `insight` CardType (§I: no new CardType). Placed right
    after 可改良 (order 50) and before the GitHub 工具雷达 (order 60). Returns
    None when the source is degraded/empty — the container is simply absent
    (ADR-23), the digest still produced."""
    body = _card_interest_body(card_interest)
    if not body:
        return None
    card = Card(_kuid(mmdd, 24), "insight", "wide",
                {"title": "你最常收藏的卡型 Top-N", "body": body})
    # NOTE: slot 13, not 11. 成本归因 already owns 11 — the two collided, so the
    # `container put` for whichever came second silently OVERWROTE the first in
    # the app (container id is the upsert key). Harmless-looking while cards were
    # appended unconditionally; load-bearing now that the information budget
    # selects containers by identity. Slot 12 is 交叉信号.
    return Container(_cuid(mmdd, 13), "卡型兴趣", 55, (card,), layout="list")


# ---------------------------------------------------------------------------
# 交叉信号 · relationship (§design 4.2, constitution §Relationship visualization)
#
# The first card here built from a genuinely TWO-dimensional bundle. Everything
# above is a series or a ranking, and neither can honestly become a
# relationship — so this is produced from the structured matrix bundle only,
# never by parsing structure back out of prose.
# ---------------------------------------------------------------------------
# What the plotted number actually measures. Stated on the card because
# "rework tokens" is a proxy (tokens on issues that were cancelled and later
# completed), not an objective measure of wasted effort.
_REWORK_METRIC_DEFINITION = (
    "返工 token = 被取消后又完成的 issue 上消耗的 token；"
    "每个 issue 只计入其主导根因一次，不跨根因重复计数"
)


def _relationship_summary(cells: list, sample_size: int) -> str:
    """A summary that states what was OBSERVED, never why.

    The constitution forbids wording an observational association as causation,
    and this matrix is exactly the kind that invites it ("runtime-offline
    causes rework"). What is actually known is where the mass sits, so that is
    what the sentence says.
    """
    top = max(cells, key=lambda c: c.value)
    total = sum(c.value for c in cells)
    share = (100.0 * top.value / total) if total > 0 else 0.0
    return (f"观察到返工 token 最集中于 {top.row} · {top.column}"
            f"（占 {share:.0f}%，样本 {sample_size} 个返工 issue）；"
            "这是相关性观察，不构成因果结论")


def _relationship_container(mmdd: str, rework) -> "Container | None":
    """🔗 交叉信号: the workspace × root-cause rework heatmap.

    Returns None — not an empty frame — whenever the data cannot honestly carry
    a relationship (ADR-23):
      - the source degraded or was never collected;
      - the matrix is thinner than 2×2, i.e. one axis has a single value and the
        "relationship" would be a ranking wearing a matrix's clothes;
      - the sample size is 0, which the schema rejects anyway (sampleSize >= 1),
        so publishing it would make the card silently vanish app-side.

    The size/visualization decision is delegated to `card_policy.choose_card`,
    so "why is this wide?" is answered by a unit-tested rule rather than a
    literal typed here.
    """
    if rework is None or getattr(rework, "health", None) is None:
        return None
    if rework.health.state != "ok" or not rework.cells or rework.sample_size < 1:
        return None
    rows = sorted({c.row for c in rework.cells})
    columns = sorted({c.column for c in rework.cells})
    profile = DataProfile(
        semantic="relationship",
        item_count=len(rework.cells),
        dimensions=2,
        row_count=len(rows),
        column_count=len(columns),
        relationship_kind="heatmap",
    )
    decision = choose_card(profile)
    if decision.size != "wide":
        # A medium heatmap is a 1×N strip: the second axis carries no
        # information, so the chart would assert a structure the data lacks.
        return None
    payload = {
        "title": "返工集中在哪里",
        "visualization": decision.visualization,
        "xAxis": {"label": "失败根因"},
        "yAxis": {"label": "Workspace"},
        "cells": [{"row": c.row, "column": c.column, "value": float(c.value)}
                  for c in rework.cells],
        "sampleSize": int(rework.sample_size),
        "timeWindow": rework.time_window or "全部",
        "metricDefinition": _REWORK_METRIC_DEFINITION,
        "summary": _relationship_summary(rework.cells, rework.sample_size),
    }
    card = Card(_kuid(mmdd, 37), "relationship", decision.size, payload)
    return Container(_cuid(mmdd, 12), "交叉信号", 24, (card,), layout="auto",
                     subtitle="返工 × 根因 × workspace · 观察性关联")


# ---------------------------------------------------------------------------
# Information budget (§design 3): a two-minute first screen, a five-minute page.
#
# Containers are built as before — each producer still owns its own
# degrade-safety — but they are then offered to the budget as CANDIDATES rather
# than appended unconditionally. The budget is what turns "we have data for this"
# into "this earns the reader's attention today".
#
# ## Why redundancy is handled per ITEM, not here
#
# An earlier version let one container declare it superseded another's signal
# (成本归因's per-project split vs 趋势指标's spend total). The granularity was
# wrong: admission is per CONTAINER, but the redundancy is a single ROW. 趋势指标
# carries tokens, requests, sessions, completed-issues and the automation ratio
# beside the cost row — none of which the cost split restates — so suppressing
# the container to remove one duplicated row deleted five unrelated signals.
#
# Two-pass admission (suppress against provisionally-admitted providers) did not
# rescue it either: `_admit` skips an over-budget candidate and lets a lighter
# one take its place, so admission is NOT monotone — removing a card can change
# WHICH cards fit and evict the very provider that justified the suppression,
# losing both sides and the signal entirely.
#
# So de-duplication lives in `_dedupe_metric_items`, inside the producer that
# owns the rows, and runs before the card is built. The budget below ranks and
# caps; it never deletes one container on another's behalf.
# ---------------------------------------------------------------------------
# Per-container budget metadata, keyed by container title. Everything absent
# from this table takes the default (a plain, non-detail card of average cost).
#
#   is_detail        — stable description; omitted when it carries no signal.
#   cross_signal     — how much cross-source value it adds (0 = single dimension).
#   reading_cost     — roughly how long a reader spends on it.
#
# 趋势指标 scores 1 rather than 0 because its rows are de-duplicated before the
# card is built: whatever survives is a signal no other card restates (requests,
# sessions, completed work, automation ratio). Ranking it at 0 — as a bare
# single-dimension total — described the card before de-duplication, and dropped
# the day's only source of those numbers on a busy day.
_BUDGET_META: dict[str, dict] = {
    "总览": {"reading_cost": 2, "requires_action": False},
    "今日规划": {"requires_action": True, "reading_cost": 1},
    "交叉信号": {"cross_signal": 3, "reading_cost": 2},
    "AI 效能": {"cross_signal": 2, "reading_cost": 3},
    "成本归因": {"cross_signal": 2, "reading_cost": 3},
    "趋势指标": {"cross_signal": 1, "reading_cost": 2},
    "今日工作": {"reading_cost": 2},
    "昨日汇总": {"reading_cost": 2},
    "可改良": {"cross_signal": 1, "reading_cost": 3},
    "时间与产出": {"is_detail": True, "reading_cost": 2},
    "卡型兴趣": {"is_detail": True, "reading_cost": 1},
    "GitHub 工具雷达": {"is_detail": True, "reading_cost": 3},
    "新闻雷达": {"is_detail": True, "reading_cost": 3},
}


def _container_candidates(containers: list[Container]) -> list[CardCandidate]:
    """One CardCandidate per container, weighted by the cards it publishes.

    Containers are the ADMISSION unit — a container is what a reader scans, and
    half of "成本归因" explains nothing, so a section is published whole or not
    at all. But the BUDGET is spent in cards (`weight`), because the reader's
    five minutes go on cards rather than section headers. Charging one per
    container was the bug: three five-card sections cost 3 against a cap of 10
    while putting 15 cards on the page.

    `freshness` is derived from position: the digest orders containers by their
    own `order`, and an earlier container is the more immediate signal.
    """
    candidates: list[CardCandidate] = []
    for index, container in enumerate(containers):
        meta = _BUDGET_META.get(container.title, {})
        candidates.append(CardCandidate(
            card=container,
            order=container.order,
            requires_action=bool(meta.get("requires_action", False)),
            is_anomaly=bool(meta.get("is_anomaly", False)),
            cross_signal_strength=int(meta.get("cross_signal", 0)),
            # Later containers are progressively less immediate; the overview
            # and the day's numbers lead.
            freshness=max(0, len(containers) - index),
            source_coverage=len(container.cards),
            reading_cost=int(meta.get("reading_cost", 2)),
            is_detail=bool(meta.get("is_detail", False)),
            weight=len(container.cards),
        ))
    return candidates


def _apply_budget(containers: list[Container]) -> tuple[Container, ...]:
    """Trim the day's containers so the PUBLISHED CARDS fit the budget, and
    make the first-screen decision one the APP will actually honour.

    The overview is EXEMPT and always leads: it is the briefing's only
    guaranteed card (ADR-23 — a fully degraded day still publishes a valid
    briefing), so putting it up for selection would risk a day with no cards at
    all. Its cards are still CHARGED against the budget, since the reader pays
    for them either way; only its admission is unconditional.

    ## Why this rewrites `order` rather than just returning a tuple

    The app does NOT render containers in the order we send them — both
    `BriefingView.swift` and `XPCHandlers.swift` sort by `container.order`. So a
    first-screen decision expressed only as tuple position is invisible to the
    reader: whatever `order` says wins, and the budget's ranking is silently
    discarded on the way through XPC. (Sorting survivors straight back to
    authored order here had exactly that effect — `FIRST_SCREEN_CARDS` decided
    nothing a reader could see.)

    So the lead containers are renumbered into a reserved band BELOW every
    authored order, preserving their priority sequence, while the tail keeps its
    authored numbering. `order` remains ascending — it is still the single
    ordering key — but its leading stretch now encodes "this is the two-minute
    read" instead of "this is where the producer happened to append it".
    """
    if not containers:
        return ()
    head, rest = containers[0], containers[1:]
    # The overview's own cards come out of the same budget — exempt from being
    # dropped is not the same as free.
    head_cards = len(head.cards)
    budget = max(0, MAX_CARDS - head_cards)
    first_screen = max(0, FIRST_SCREEN_CARDS - head_cards)
    kept = select_with_budget(_container_candidates(rest),
                              max_cards=budget, first_screen=first_screen)
    if not [c for c in kept.selected if c.card.cards]:
        return (head,)

    # Take the first-screen boundary FROM the budget rather than re-deriving it.
    # Counting cards off the front of the result would be wrong: the tail is
    # sorted back into authored order, so a light low-priority container sitting
    # early in authored order gets swept into the lead and — because the lead is
    # what gets renumbered — genuinely promoted onto the reader's first screen
    # ahead of a higher-priority one.
    lead = [c.card for c in kept.lead if c.card.cards]
    tail = [c.card for c in kept.tail if c.card.cards]

    # Renumber EVERY survivor into one ascending run below the overview.
    #
    # Renumbering only the lead is not enough. The app sorts by `order` alone,
    # so a tail container that happens to carry a low authored number (say the
    # producer gave it 15 while a lead container authored 30 got renumbered)
    # would still render above the first screen — the budget's decision loses to
    # an accident of how the producers numbered their sections.
    #
    # So: lead first, in priority order; then tail, in authored order. The
    # overview keeps the hard top. Within each group the relative order is the
    # one that group is supposed to express, and across groups the first screen
    # always wins.
    published = [
        replace(container, order=head.order + 1 + index)
        for index, container in enumerate(lead + tail)
    ]
    return tuple([head] + published)


def build_briefing(report_date: str, sources: "DigestSources", full_md: str,
                   must_see: str,
                   delivery: "DeliveryState | None" = None) -> Briefing:
    """Map the digest into a Briefing (pure). `report_date` is the RUN date.

    Numeric trends render as a `metric` card (sparklines + a ring gauge for the
    automation ratio) built from the structured `sources` series — not by parsing
    numbers back out of markdown. `full_md` still supplies the prose sections
    (昨日汇总/TODO/可改良) and the source-health line.

    Containers are built first and then passed through the INFORMATION BUDGET
    (§design 3): what a reader can finish in two minutes leads, the whole page
    stays inside five, and a low-value card is omitted rather than pushed to the
    bottom. The overview is exempt so a fully degraded day still publishes.

    The briefing date/title/UUIDs key on the REPORTED day (yesterday of the run
    date) so they match the local archive filename and the digest title (BUG 3).
    A degraded digest (no series data) still yields a valid briefing: the overview
    `digest` card is always present, so the briefing is never empty/invalid.
    """
    reported_day = yesterday(report_date)
    sections = parse_sections(full_md)
    mmdd = _mmdd(reported_day)
    containers = [_overview_container(mmdd, reported_day, must_see, sections,
                                      delivery=delivery,
                                      report_date=report_date)]

    # 今日工作 (goal ① 做了什么, M2): per-project effort, right after overview.
    work_container = _work_container(
        mmdd, getattr(sources, "work_by_project", None))
    if work_container:
        containers.append(work_container)

    # 💸 成本归因 (order 22): explains the arrows in 趋势指标 directly above.
    attribution_container = _attribution_container(
        mmdd, getattr(sources, "cost_by_project", None),
        getattr(sources, "model_by_project", None),
        getattr(sources, "leverage", None),
        getattr(sources, "rework_by_workspace", None))

    metrics = _metric_items(sources, report_date)
    if metrics:
        containers.append(Container(
            _cuid(mmdd, 2), "趋势指标", 20,
            (Card(_kuid(mmdd, 3), "metric", "wide", {"items": metrics}),),
            layout="auto"))

    if attribution_container:
        containers.append(attribution_container)

    # 🔗 交叉信号 (order 24): the rework heatmap. Sits between 成本归因 (22) and
    # AI 效能 (25) — it explains where the effectiveness numbers below come from.
    relationship_container = _relationship_container(
        mmdd, getattr(sources, "rework_relationship", None))
    if relationship_container:
        containers.append(relationship_container)

    # 🧠 AI 效能 (order 25) + ⏱ 时间与产出 (order 28): batch-2 差异化 sections,
    # placed right after the trend metrics and before the prose 昨日汇总 (order 30).
    ai_container = _ai_efficiency_container(
        mmdd, getattr(sources, "ai_efficiency", None),
        getattr(sources, "tool_cross", None))
    if ai_container:
        containers.append(ai_container)
    time_container = _time_output_container(
        mmdd, getattr(sources, "app_focus", None),
        getattr(sources, "commit_by_repo", None))
    if time_container:
        containers.append(time_container)

    # 可改良 gains the 模型分层 stackedBar (§design: 融进现有, not a standalone card).
    model_tier_card = _model_tier_card(mmdd, getattr(sources, "model_tier", None))
    containers.extend(_prose_containers(mmdd, sections,
                                        cost_improvement=getattr(sources, "cost_improvement", None),
                                        value_efficiency=getattr(sources, "value_efficiency", None),
                                        inbox_items=getattr(sources, "action_inbox", None),
                                        model_tier_card=model_tier_card))

    # GitHub 工具雷达 (§radar): curated watchlist stars/delta, split by tier.
    containers.extend(_radar_containers(mmdd, getattr(sources, "repo_radar", None)))

    # 卡型兴趣 (spec 005 US5): "你最常收藏的卡型 Top-N", right after 可改良 (order 55).
    card_interest_container = _card_interest_container(
        mmdd, getattr(sources, "card_interest", None))
    if card_interest_container:
        containers.append(card_interest_container)

    # 📰 新闻雷达 (order 80): newest headlines by topic, at the参考/探索 tail.
    news_container = _news_container(mmdd, getattr(sources, "news_radar", None))
    if news_container:
        containers.append(news_container)
    # De-duplicate AFTER the budget, never before: a row is only redundant if
    # the card that covers it actually reaches the reader, and until the budget
    # has run that is not known (§design 3, criterion 5).
    return Briefing(reported_day, GENERATED_BY,
                    _dedupe_published(_apply_budget(containers)))


# ---------------------------------------------------------------------------
# Best-effort, non-fatal push path (ADR-17/23).
#
# Everything below is injectable so the unit suite never touches the real app:
#   - globber/mtime resolve the CLI binary,
#   - opener launches AIDash, pgrep reports whether it's running,
#   - runner shells out to the CLI (returns an int exit code).
# push_briefing NEVER raises: any failure → PushResult(ok=False, reason=...).
# ---------------------------------------------------------------------------
Globber = Callable[[str], list[str]]
MTime = Callable[[str], float]
Opener = Callable[[], object]
Pgrep = Callable[[str], bool]
Runner = Callable[..., int]
# Exists: does a fixed install path exist? Injected so the fixed-path preference
# in resolve_aidash_bin/app is unit-testable without touching the real FS.
Exists = Callable[[str], bool]
# Probe: given the aidash bin path, return True iff XPC is actually reachable
# (a read-only round-trip succeeded), False otherwise. Distinct from Pgrep,
# which only reports that the app *process* exists — the two diverge when the
# process is up but its XPC listener never checked into the mach service
# (observed: `xpc.app_unavailable` while `pgrep` still hits).
Probe = Callable[[str], bool]


def _default_globber(pattern: str) -> list[str]:
    return [str(p) for p in Path.home().glob(pattern)]


def _default_mtime(path: str) -> float:
    return Path(path).stat().st_mtime


def _default_exists(path: str) -> bool:
    return Path(path).exists()


def resolve_aidash_bin(globber: Globber = _default_globber,
                       mtime: MTime = _default_mtime,
                       exists: Exists = _default_exists) -> str | None:
    """Return the aidash CLI path, or None if absent.

    Prefers the FIXED install (`~/.local/bin/aidash`, outside DerivedData) so
    the daily push isn't churned by rebuilds; falls back to the newest
    DerivedData build (recipe glob — never `which aidash`, which the user
    rejects; newest by mtime wins) so a dev box without a fixed install works.
    """
    try:
        if exists(AIDASH_BIN_FIXED):
            return AIDASH_BIN_FIXED
        candidates = globber(AIDASH_BIN_GLOB)
        if not candidates:
            return None
        return max(candidates, key=mtime)
    except OSError:
        return None


def resolve_aidash_app(globber: Globber = _default_globber,
                       mtime: MTime = _default_mtime,
                       exists: Exists = _default_exists) -> str | None:
    """Return the AIDash.app bundle path to launch, or None.

    Prefers the FIXED install (`/Applications/AIDash.app`, outside DerivedData)
    so the daily push targets the stable build the launchd mach service brokers
    to; falls back to the newest DerivedData bundle so a dev box without a fixed
    install still launches the freshly-built app (whose installer bootstraps the
    LaunchAgent for that build) rather than whatever `open -a AIDash` resolves.
    """
    try:
        if exists(AIDASH_APP_FIXED):
            return AIDASH_APP_FIXED
        candidates = globber(AIDASH_APP_GLOB)
        if not candidates:
            return None
        return max(candidates, key=mtime)
    except OSError:
        return None


def _default_opener() -> object:
    # Prefer the exact DerivedData bundle; fall back to `open -a AIDash` by name
    # when it can't be resolved (e.g. an installed /Applications build).
    app = resolve_aidash_app()
    if app:
        return subprocess.run(["open", app], check=False)  # nosec B603 B607
    return subprocess.run(["open", "-a", APP_NAME], check=False)  # nosec B603 B607


def _default_pgrep(name: str) -> bool:
    proc = subprocess.run(["pgrep", "-lf", name],  # nosec B603 B607
                          capture_output=True, text=True, check=False)
    return proc.returncode == 0 and bool(proc.stdout.strip())


def ensure_app_running(opener: Opener = _default_opener,
                       pgrep: Pgrep = _default_pgrep,
                       poll_s: float = 0.5, attempts: int = 6) -> bool:
    """Launch AIDash and poll until it's running (ADR-17). Best-effort.

    A bounded readiness poll rather than a fixed sleep. Returns True as soon as
    pgrep reports the app, False if it never comes up within `attempts`.

    NOTE: process-liveness only. A True here does NOT mean XPC is reachable —
    the listener may not have checked into the mach service yet (or at all).
    Callers that need to actually talk to the app must additionally gate on
    `ensure_xpc_ready`, which does a real round-trip.
    """
    if pgrep(APP_NAME):
        return True
    opener()
    for _ in range(attempts):
        if pgrep(APP_NAME):
            return True
        if poll_s > 0:
            time.sleep(poll_s)
    return pgrep(APP_NAME)


def _default_runner(argv: Sequence[str], **kw) -> int:
    proc = subprocess.run(list(argv), capture_output=True,  # nosec B603
                          text=True, check=False)
    return proc.returncode


def _default_probe(bin_path: str, timeout_s: float = 12.0) -> bool:
    """Real XPC health check: a read-only `schema list` round-trip.

    `schema list` is the cheapest command that exercises the full CLI→XPC→app
    path without mutating state. Per cli-surface.md exit codes: 0 = success
    (XPC healthy), 2 = XPC transport failure (`xpc.*`, e.g. app_unavailable),
    3 = app-side error. Only exit 0 proves the listener is actually serving,
    so anything non-zero is treated as "not ready".

    CRITICAL: when the app process is up but its XPC listener is dead, the CLI
    does not fail fast — it HANGS waiting for a mach reply (observed: a bare
    `schema list` blocked >120s). So the probe MUST bound itself with a timeout;
    a timeout is treated as "not ready" (the exact hung-listener case). Without
    this the 04:00 cron would block indefinitely instead of degrading loudly.

    Self-contained and never raises: a missing/insufficient binary (OSError) or
    a hang (TimeoutExpired) are both "not ready", not exceptions the caller
    must guard.
    """
    try:
        proc = subprocess.run([bin_path, "schema", "list", "--quiet"],  # nosec B603
                              capture_output=True, text=True, check=False,
                              timeout=timeout_s)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0


def ensure_xpc_ready(bin_path: str, *, probe: Probe = _default_probe,
                     poll_s: float = 0.5, attempts: int = 6) -> bool:
    """Poll the real XPC path until a read-only round-trip succeeds.

    Bounded retry: the app process can be up while its XPC listener is still
    coming online (CloudKit init, mach-service check-in), so a single probe
    right after launch races. Returns True on the first healthy probe, False
    if XPC never becomes reachable within `attempts`.
    """
    for i in range(max(1, attempts)):
        if probe(bin_path):
            return True
        if poll_s > 0 and i < attempts - 1:
            time.sleep(poll_s)
    return False


def _default_notifier(title: str, message: str) -> None:
    """Post a macOS desktop notification via osascript. Best-effort, never raises.

    This is the fix for the silent-failure blind spot: the 04:00 cron push often
    fails (XPC listener dead after an `open`-launched app — the SMAppService
    registration weakness), and until now that only landed in a log file nobody
    watches, so the dashboard could sit stale for days unnoticed. A desktop
    notification surfaces the failure the same day. A missing/failed osascript
    (non-macOS, sandbox) is swallowed — notification is a nicety, not a gate.
    """
    # Escape double-quotes for the AppleScript string literals.
    safe_msg = message.replace('"', '\\"')
    safe_title = title.replace('"', '\\"')
    script = f'display notification "{safe_msg}" with title "{safe_title}"'
    try:
        subprocess.run(["osascript", "-e", script],  # nosec B603 B607
                       capture_output=True, timeout=10, check=False)
    except (OSError, subprocess.SubprocessError):  # pragma: no cover - best-effort
        pass


def _record_push_failure(reason: str,
                         now: Callable[[], str] = None,
                         log_path: Path | None = None,
                         notifier: Callable[[str, str], None] = None) -> None:
    """Append to the push-error log AND post a desktop notification (loud fail).

    Two-channel loudness (both best-effort, non-fatal): the log line is the
    durable record; the notification pulls attention the same day so a stale
    AIDash mirror is noticed within hours, not days. Neither channel failing
    raises from the push boundary.
    """
    try:
        stamp = (now or _utc_now)()
        path = log_path or (Path.home() / PUSH_ERROR_LOG)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(f"{stamp} — AIDash push did not land: {reason}\n")
    except OSError as exc:  # pragma: no cover - log-of-last-resort
        log.warning("could not write push-error log: %s", exc)
    # Desktop notification — separate try so a log failure doesn't skip it and
    # vice versa. Injected notifier defaults to the real osascript one.
    try:
        (notifier or _default_notifier)(
            "AIDash 日报未推送",
            f"{reason}（本地归档已保存，重新 Run AIDashApp 后可重推）")
    except Exception:  # noqa: BLE001 - notification is a nicety, never fatal
        pass


def _utc_now() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# Delivery state persistence (MY-1438/MY-1450).
#
# The push path writes `DeliveryState` after every attempt; the next
# digest-build reads it to expose delivery health separately from
# content-source health. Uses the existing state.json watermark store
# under key "delivery".
# ---------------------------------------------------------------------------
_DELIVERY_KEY = "delivery"


def save_delivery_state(result: PushResult,
                        now: Callable[[], str] | None = None) -> DeliveryState:
    """Persist delivery state from a PushResult. Returns the saved state."""
    from state import set_watermark
    stamp = (now or _utc_now)()
    state = DeliveryState(ok=result.ok, reason=result.reason, timestamp=stamp)
    set_watermark(_DELIVERY_KEY, {
        "ok": state.ok, "reason": state.reason, "timestamp": state.timestamp,
    })
    return state


def load_delivery_state() -> DeliveryState | None:
    """Read the last-persisted delivery state, or None if never pushed."""
    from state import get_watermark
    raw = get_watermark(_DELIVERY_KEY)
    if raw is None or not isinstance(raw, dict):
        return None
    return DeliveryState(
        ok=raw.get("ok", False),
        reason=raw.get("reason", ""),
        timestamp=raw.get("timestamp", ""),
    )


def delivery_health_line(report_date: str,
                         delivery: "DeliveryState | None" = None) -> str:
    """Human-readable delivery/XPC health line with freshness semantics.

    Returns "" when no delivery state exists (first run, never pushed).
    Marks the state as stale when its timestamp is >36h before the report date.
    """
    if delivery is None:
        return ""
    if delivery.ok:
        label = "XPC✅"
    else:
        short_reason = delivery.reason.split("(")[0].strip() if delivery.reason else "unknown"
        label = f"XPC⚠️{short_reason}"
    # Freshness: compare delivery timestamp to report_date.
    stale_tag = ""
    if delivery.timestamp and report_date:
        try:
            from datetime import datetime, timezone, timedelta
            ts = datetime.fromisoformat(delivery.timestamp.replace("Z", "+00:00"))
            from L5_apps.digest.cst import _parse as _parse_cst_day, _CST
            report_dt = _parse_cst_day(report_date).replace(tzinfo=_CST)
            age = report_dt - ts
            if age > timedelta(hours=36):
                stale_tag = f"(stale: {age.days}d ago)"
        except (ValueError, TypeError):
            pass
    parts = label + (f" {stale_tag}" if stale_tag else "")
    return f"> 投递: {parts}"


def _card_argv(bin_path: str, container_id: str, card: Card,
               payload_file: str) -> list[str]:
    return [bin_path, "card", "put",
            "--container-id", container_id, "--id", card.id,
            "--type", card.type, "--size", card.size, "--style", card.style,
            "--payload", f"@{payload_file}"]


def _publish_briefing(briefing: Briefing, bin_path: str,
                      runner: Runner) -> PushResult:
    """Issue the put/publish CLI calls. Returns a PushResult; may raise (caught
    by push_briefing) if a runner blows up."""
    rc = runner([bin_path, "briefing", "put", "--date", briefing.date,
                 "--generated-by", briefing.generated_by])
    if rc != 0:
        return PushResult(False, f"briefing put exit {rc}")
    for container in briefing.containers:
        rc = runner([bin_path, "container", "put",
                     "--briefing-date", briefing.date, "--id", container.id,
                     "--title", container.title, "--order", str(container.order),
                     "--layout", container.layout, "--style", container.style])
        if rc != 0:
            return PushResult(False, f"container put exit {rc}")
        for card in container.cards:
            with tempfile.NamedTemporaryFile("w", suffix=".json",
                                             delete=False, encoding="utf-8") as fh:
                json.dump(card.payload, fh, ensure_ascii=False)
                payload_file = fh.name
            rc = runner(_card_argv(bin_path, container.id, card, payload_file))
            if rc != 0:
                return PushResult(False, f"card put exit {rc}")
    rc = runner([bin_path, "briefing", "publish", "--date", briefing.date])
    if rc != 0:
        return PushResult(False, f"briefing publish exit {rc}")
    return PushResult(True, "", published=True)


def push_briefing(briefing: Briefing, *, bin_path: str | None,
                  runner: Runner = _default_runner,
                  opener: Opener = _default_opener,
                  pgrep: Pgrep = _default_pgrep,
                  probe: Probe = _default_probe,
                  failure_sink: Callable[[str], None] = _record_push_failure,
                  poll_s: float = 0.5, attempts: int = 6,
                  xpc_attempts: int = 24) -> PushResult:
    """Push a briefing to AIDash, best-effort and NON-FATAL (ADR-16/17/23).

    Returns a PushResult describing what happened. NEVER raises — every failure
    (no CLI, app won't launch, XPC not reachable, non-zero CLI exit / XPC error,
    or any raised exception in the injected helpers) is caught and degraded.

    Readiness is a TWO-stage gate:
      1. `ensure_app_running` — the app *process* exists (launch if needed).
      2. `ensure_xpc_ready`   — a real read-only round-trip succeeds, proving the
         XPC listener actually serves. Stage 1 passing while stage 2 fails is the
         exact 04:00 failure mode (process up at wake, listener not yet checked
         into the mach service) that previously lost the digest silently.

    Stage 2 gets its OWN, MORE PATIENT budget (`xpc_attempts`, default 24 ≈ 12s
    at poll_s=0.5) — separate from the process-liveness budget (`attempts`).
    The XPC listener's cold-start (CloudKit init + mach-service check-in) can
    take several seconds after an Xcode Run / cron wake; the old shared 6-attempt
    (3s) window raced that warmup and gave up too early (observed 2026-07-18).

    When the push cannot land, the failure is made LOUD: `failure_sink` records
    an actionable line to the push-error log AND posts a desktop notification, so
    a stale AIDash mirror is noticed the same day. The local md archive remains
    the 必成 sink (written before push), so a stale mirror is recoverable — not
    data loss.
    """
    if bin_path is None:
        log.warning("AIDash push skipped: aidash CLI not found (bin missing)")
        failure_sink("aidash CLI not found in DerivedData (build the CLI?)")
        return PushResult(False, "aidash cli/bin not found")
    try:
        if not ensure_app_running(opener=opener, pgrep=pgrep,
                                  poll_s=poll_s, attempts=attempts):
            log.warning("AIDash push skipped: app not running (asleep Mac?)")
            failure_sink("AIDash app process never came up (asleep Mac?)")
            return PushResult(False, "AIDash app not running")
        if not ensure_xpc_ready(bin_path, probe=probe,
                                poll_s=poll_s, attempts=xpc_attempts):
            # Process is up but XPC never became reachable — the digest is
            # archived locally but the menubar mirror is stale. Make it loud.
            log.warning("AIDash push skipped: XPC not reachable "
                        "(app up, listener not serving)")
            failure_sink("XPC not reachable — app process up but its listener "
                         "never checked in (try relaunching AIDash)")
            return PushResult(False, "AIDash XPC not reachable")
        result = _publish_briefing(briefing, bin_path, runner)
        if not result.ok:
            log.warning("AIDash push failed: %s", result.reason)
            failure_sink(result.reason)
        return result
    except Exception as exc:  # noqa: BLE001 - best-effort: degrade, never crash
        log.warning("AIDash push errored (non-fatal): %s", exc)
        failure_sink(f"unexpected push error: {type(exc).__name__}: {exc}")
        return PushResult(False, f"push error: {type(exc).__name__}")
