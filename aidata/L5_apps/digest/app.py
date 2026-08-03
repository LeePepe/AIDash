"""Digest orchestrator: fetch trends → render Markdown template → archive.

The template path (M1–M3) is deterministic and golden-testable: for fixed
warehouse data `build_digest(date)` returns byte-identical Markdown. M4 adds an
OPTIONAL LLM polish layer (`use_llm=True`) that fills bounded free-text slots on
top of the template. The template always owns every number; a verification
guard rejects any polished output that alters/invents a number, and any LLM
error, missing key, or failed verification falls back to the pure template
(ADR-16/18/23). The local archive is therefore a 必成 sink — it always produces.
"""

from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path

from config import DIGEST_DIR
from L5_apps.digest.cst import _CST, yesterday, _parse as _parse_cst_day
from L5_apps.digest.sources import (  # noqa: F401 — fetch_ado_pr_trends re-export
    DigestSources,
    fetch_raven_trends, fetch_multica_completed,
    # fetch_ado_pr_trends is imported into this module's namespace as a test
    # monkeypatch seam: test_digest_golden / _aidash / _llm do
    # `monkeypatch.setattr(app, "fetch_ado_pr_trends", ...)`. ruff can't see the
    # patch, so it flags F401 — keep it (deleting turns golden's assertion
    # failure into an AttributeError).
    fetch_ado_pr_trends, fetch_automation_trends, fetch_cost_improvement,
    fetch_value_efficiency, fetch_work_by_project, fetch_repo_radar,
    fetch_combined_pr_trends,
    # batch-2 (L5 数据接入批2): AI 效能 + 时间与产出 + 新闻雷达 + 模型分层.
    fetch_ai_efficiency, fetch_app_focus, fetch_commit_by_repo,
    fetch_cost_by_project, fetch_model_by_project,
    fetch_news_radar, fetch_model_tier,
)
from L5_apps.digest.render import render_digest
from L5_apps.digest.llm import LLMClient, LLMError, default_client
from L5_apps.digest.polish import polish_digest
from L5_apps.digest.verify import verify_numbers
from L5_apps.digest.must_see import must_see_layer
from L5_apps.digest.aidash import build_briefing, push_briefing, PushResult

log = logging.getLogger("aidata.digest.app")


def _today_cst() -> str:
    # NOTE: real wall-clock; only used as the CLI default, never in tests
    # (tests always pass an explicit --date to stay deterministic).
    return datetime.now(tz=_CST).strftime("%Y-%m-%d")


def _fetch_sources(report_date: str | None = None) -> DigestSources:
    """Fetch every trend source ONCE into an immutable bundle (ADR-23).

    Each source is independently health-wrapped, so any one failing degrades
    that section without crashing the digest. The same snapshot feeds both the
    Markdown renderer and the AIDash payload builder — no double fetch.

    `report_date` (run date) sets the efficiency metric's rolling 7-day window
    (research 2026-07-18: single-day cost is noise). Absent → all-time fallback.
    """
    window_days = 7
    since = None
    day_since = None   # yesterday-only window for '做了什么' (M2)
    day_until = None
    if report_date is not None:
        from datetime import timedelta
        base = _parse_cst_day(report_date)
        since = (base - timedelta(days=window_days)).strftime("%Y-%m-%d")
        day_since = (base - timedelta(days=1)).strftime("%Y-%m-%d")
        day_until = base.strftime("%Y-%m-%d")
    cost_improvement = fetch_cost_improvement()
    return DigestSources(
        raven=fetch_raven_trends(),
        multica=fetch_multica_completed(),
        ado=fetch_combined_pr_trends(),
        automation=fetch_automation_trends(),
        cost_improvement=cost_improvement,
        value_efficiency=fetch_value_efficiency(since, window_days),
        work_by_project=fetch_work_by_project(day_since, day_until),
        action_inbox=_build_action_inbox(cost_improvement),
        repo_radar=fetch_repo_radar(),
        # batch-2: 时间与产出 uses the yesterday-only window (same as 做了什么);
        # AI 效能 / 新闻 / 模型分层 are their own snapshots (all-time or latest).
        ai_efficiency=fetch_ai_efficiency(),
        app_focus=fetch_app_focus(day_since, day_until),
        commit_by_repo=fetch_commit_by_repo(day_since, day_until),
        news_radar=fetch_news_radar(),
        model_tier=fetch_model_tier(),
        # Attribution uses the REPORTED day (day_since), matching the day the
        # trend arrows describe — attributing yesterday's spike to projects is
        # only meaningful against yesterday's spend.
        cost_by_project=fetch_cost_by_project(day_since),
        model_by_project=fetch_model_by_project(day_since),
    )


def _build_action_inbox(cost_improvement) -> list:
    """M3 action inbox: prioritized 需要处理什么. Best-effort; never fatal."""
    try:
        from L5_apps.digest.inbox import build_inbox
        waste = getattr(cost_improvement, "downgrade_usd", None)
        return build_inbox(downgrade_usd=waste)
    except Exception:  # degrade: an inbox failure must not break the digest
        return []


def _render_template(report_date: str, sources: DigestSources) -> str:
    """The deterministic M1–M3 template output (the number-owning ground truth)."""
    return render_digest(sources.raven, report_date, multica=sources.multica,
                         ado=sources.ado, automation=sources.automation,
                         repo_radar=sources.repo_radar)


def _maybe_polish(template_md: str, client: LLMClient | None) -> str:
    """Return a verify-guarded polished digest, or the template on any failure.

    Fallback triggers (all → return template, never raise, ADR-16/18/23):
      - no client available (missing key / raven unreachable at config time)
      - LLMError during the polish call or reply parsing
      - the polished output fails number verification (hallucinated/altered num)
    """
    if client is None:
        return template_md
    try:
        polished = polish_digest(template_md, client)
    except LLMError:
        return template_md
    result = verify_numbers(template_md, polished)
    if not result.ok:
        return template_md  # guard rejected the polish → template floor
    return polished


def build_digest(report_date: str, use_llm: bool = False,
                 client: LLMClient | None = None,
                 sources: DigestSources | None = None) -> str:
    """Build the Markdown digest reporting on the CST day before report_date.

    Default (`use_llm=False`) returns the pure deterministic template — the
    M1–M3 behavior, unchanged. `use_llm=True` additively attempts an LLM polish
    on top, always with the template as a guaranteed floor. `sources` may be
    supplied to reuse an already-fetched snapshot (write_digest fetches once and
    shares it with the AIDash push); otherwise it is fetched here.
    """
    src = sources if sources is not None else _fetch_sources()
    template_md = _render_template(report_date, src)
    if not use_llm:
        return template_md
    return _maybe_polish(template_md, client or default_client())


def _push_to_aidash(md: str, report_date: str,
                    sources: DigestSources) -> PushResult:
    """Transform the digest into a Briefing and push it (best-effort).

    Split out so tests can monkeypatch the whole push at the app boundary. This
    itself calls the non-fatal push_briefing; the wrapper in write_digest still
    guards against any unexpected raise (e.g. a transform bug).

    `report_date` is the RUN date; build_briefing derives the reported day
    (yesterday) internally so the briefing date/title/UUIDs match the local
    archive filename and the digest title — never the run date (BUG 3). The
    structured `sources` give the metric cards real numbers + sparkline series
    instead of parsing them back out of the rendered markdown.
    """
    from L5_apps.digest.aidash import resolve_aidash_bin
    briefing = build_briefing(report_date, sources, md, must_see_layer(md))
    return push_briefing(briefing, bin_path=resolve_aidash_bin())


def write_digest(report_date: str, use_llm: bool = False,
                 push_aidash: bool = False) -> Path:
    """Build and archive to DIGEST_DIR/daily/<yesterday>.md (idempotent).

    The local archive is the 必成 sink: it is written BEFORE any AIDash push, so
    a push crash can never lose the digest. When `push_aidash` is set, the push
    is attempted best-effort — every failure mode (no CLI, app not running, XPC
    error, or any unexpected raise) is caught, logged as a warning, and swallowed
    so write_digest still returns the archive path (ADR-16/23).
    """
    sources = _fetch_sources(report_date)  # fetch once; shared by render + push

    # Integrity gate (D): if any headline source degraded (stale watermark,
    # skipped collection, query error), append a loud line to cron-errors.log +
    # notify — so a silently-incomplete digest (0 issue / 0 PR / stale radar) is
    # noticed the same day. Never blocks generation (ADR-16 必成 sink).
    try:
        from L5_apps.digest.freshness import alarm_if_degraded
        from L5_apps.digest.aidash import _default_notifier
        alarm_if_degraded(sources, report_date, notifier=_default_notifier)
    except Exception as exc:  # noqa: BLE001 - monitoring must never break digest
        log.warning("freshness gate errored (non-fatal): %s", exc)

    md = build_digest(report_date, use_llm=use_llm, sources=sources)
    out_dir = DIGEST_DIR / "daily"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{yesterday(report_date)}.md"
    out_path.write_text(md, encoding="utf-8")  # 必成 sink, before the push

    if push_aidash:
        try:
            result = _push_to_aidash(md, report_date, sources)
            if result.ok:
                log.info("AIDash push ok (published=%s)", result.published)
            else:
                log.warning("AIDash push non-fatal failure: %s", result.reason)
        except Exception as exc:  # noqa: BLE001 - archive already safe; never crash
            log.warning("AIDash push errored (non-fatal): %s", exc)

    return out_path


def default_report_date() -> str:
    return _today_cst()
