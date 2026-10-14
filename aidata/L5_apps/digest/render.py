"""Deterministic Markdown renderer for the digest (ADR-18 template, no LLM).

Given fetched trends, emits the four sections. All numbers/arrows come from the
data; nothing is invented. A degraded source prints its health state rather than
a fake trend (ADR-23).

M3 adds optional ADO PR (fact_ado_pr) and automation-ratio (state.db) inputs.
They are backward-compatible keyword args: a two-arg M1 call renders exactly the
original four raven sections.
"""

from __future__ import annotations

from L5_apps.digest.cst import yesterday
from L5_apps.digest.sources import (
    RavenTrends, MulticaTrends, AdoPrTrends, AutomationTrends,
)
from L5_apps.digest.trends import compute_trend, flat_streak
from L5_apps.digest.todo_rules import todo_candidates


def _fmt_trend(label: str, series: list[tuple[str, float]], report_date: str, unit: str = "") -> str:
    t = compute_trend(series, report_date)
    if t.days_available < 2:
        return f"- {label}: 数据仅 {t.days_available} 天"
    prev = "—" if t.prev is None else f"{t.prev:.0f}"
    pct = "" if t.pct_vs_prev is None else f"({t.pct_vs_prev:+.0f}%)"
    avg = "" if t.avg7 is None else f" · 7日均 {t.avg7:.0f}{unit}"
    return f"- {label}: {t.today:.0f}{unit} {t.arrow}{pct} vs 昨 {prev}{unit}{avg}"


def _fmt_ratio_trend(label: str, series: list[tuple[str, float]], report_date: str) -> str:
    """Percentage-formatted arrow for a 0..1 ratio series (automation)."""
    t = compute_trend(series, report_date)
    if t.days_available < 2:
        return f"- {label}: 数据仅 {t.days_available} 天"
    prev = "—" if t.prev is None else f"{t.prev * 100:.0f}%"
    return f"- {label}: {t.today * 100:.0f}% {t.arrow} vs 昨 {prev}"


def _ok(health) -> bool:
    return health is not None and health.state == "ok"


def _health_line(t: RavenTrends, multica: MulticaTrends | None,
                 ado: AdoPrTrends | None,
                 automation: AutomationTrends | None) -> str:
    """One explicit source-health line (ADR-23): distinguishes ok/skipped/error."""
    def mark(label: str, health) -> str:
        if health is None:
            return ""
        return f" {label}✅" if health.state == "ok" else f" {label}⚠️{health.state}"

    parts = ("raven✅" if t.health.state == "ok"
             else f"raven⚠️{t.health.state}")
    parts += mark("multica", multica.health if multica else None)
    parts += mark("ADO", ado.health if ado else None)
    parts += mark("state.db", automation.health if automation else None)
    return f"> 数据源: {parts}"


def _trending_section(t: RavenTrends, report_date: str, degraded: bool,
                      multica: MulticaTrends | None,
                      ado: AdoPrTrends | None,
                      automation: AutomationTrends | None) -> list[str]:
    lines = ["## ⚡ Trending"]
    if degraded:
        lines.append("- 数据缺失（raven 未采到）")
    else:
        lines.append(_fmt_trend("成本", t.cost, report_date, unit="$"))
        lines.append(_fmt_trend("Token", t.tokens, report_date))
        lines.append(_fmt_trend("请求数", t.requests, report_date))
        lines.append(_fmt_trend("浪费额", t.waste, report_date, unit="$"))
        lines.append(_fmt_trend("完成任务", t.pipeline_completed, report_date))
        lines.append(_fmt_trend("会话数", t.sessions, report_date))
        if _ok(ado.health if ado else None):
            lines.append(_fmt_trend("开PR", ado.opened, report_date))
        if _ok(automation.health if automation else None):
            lines.append(_fmt_ratio_trend("自动化占比", automation.ratio, report_date))
        streak = flat_streak(t.cost, report_date)
        if streak >= 3:
            lines.append(f"- 🚩 成本已连续 {streak} 天持平")
    # Completed-issue trend is its own source (multica) — render even when raven
    # is degraded, and degrade independently (ADR-23).
    lines.append(_fmt_completed_line(multica, report_date))
    lines.append("")
    return lines


def _fmt_completed_line(multica: MulticaTrends | None, report_date: str) -> str:
    """The "完成 issue" trending line — approximate (ADR-19), or 数据缺失."""
    if multica is None or multica.health.state != "ok":
        return "- 完成 issue(近似): 数据缺失"
    inner = _fmt_trend("完成 issue(近似)", multica.completed, report_date)
    return inner


def _todo_section(t: RavenTrends, report_date: str, degraded: bool) -> list[str]:
    lines = ["## 📅 今日 TODO"]
    todos = [] if degraded else todo_candidates(t, report_date)
    if todos:
        for td in todos:
            lines.append(f"- {td.priority}: {td.text}")
    else:
        lines.append("- （无阈值触发的行动项）")
    lines.append("")
    return lines


def _yesterday_section(t: RavenTrends, report_date: str, degraded: bool,
                       multica: MulticaTrends | None,
                       ado: AdoPrTrends | None,
                       automation: AutomationTrends | None) -> list[str]:
    lines = ["## 🗂 昨日汇总"]
    y = yesterday(report_date)
    if degraded:
        lines.append("- 数据缺失")
    else:
        c = dict(t.cost).get(y, 0.0)
        r = dict(t.requests).get(y, 0.0)
        lines.append(f"- 昨日花费 ${c:.2f}，请求 {int(r)} 次")
    lines.append(_fmt_yesterday_completed(multica, report_date))
    # ADO PR line (ADR-15) — only when the source is healthy, never fabricated.
    if _ok(ado.health if ado else None):
        opened = int(dict(ado.opened).get(y, 0.0))
        merged = int(dict(ado.merged).get(y, 0.0))
        lines.append(f"- 开了 {opened} 个 PR（合并 {merged} 个）")
    elif ado is not None:
        lines.append(f"- ADO PR: 数据缺失（{ado.health.state}）")
    # Automation ratio line (ADR-15).
    if _ok(automation.health if automation else None):
        ratio = dict(automation.ratio).get(y, 0.0)
        auto_n = int(dict(automation.automated).get(y, 0.0))
        man_n = int(dict(automation.manual).get(y, 0.0))
        lines.append(f"- 自动化占比 {ratio * 100:.0f}%（自动 {auto_n} / 手动 {man_n}）")
    elif automation is not None:
        lines.append(f"- 自动化占比: 数据缺失（{automation.health.state}）")
    lines.append("")
    return lines


def _fmt_yesterday_completed(multica: MulticaTrends | None,
                             report_date: str) -> str:
    """"昨日完成: N 个 issue (分 workspace)" — approximate, or 数据缺失."""
    if multica is None or multica.health.state != "ok":
        return "- 昨日完成: 数据缺失（multica 未采到）"
    y = yesterday(report_date)
    total = int(dict(multica.completed).get(y, 0.0))
    parts = []
    for name, series in sorted(multica.completed_by_ws.items()):
        n = int(dict(series).get(y, 0.0))
        if n:
            parts.append(f"{name}: {n}")
    breakdown = f"（{', '.join(parts)}）" if parts else ""
    return f"- 昨日完成: {total} 个 issue（近似）{breakdown}"


def _improvements_section(t: RavenTrends, report_date: str, degraded: bool) -> list[str]:
    lines = ["## 🔍 可改良"]
    if degraded:
        lines.append("- 修复 raven 采集后再分析")
    else:
        y = yesterday(report_date)
        w = dict(t.waste).get(y, 0.0)
        if w > 0:
            lines.append(f"- 昨日 ${w:.0f} 花在极小输出/大上下文，可考虑降级模型或裁剪上下文")
        else:
            lines.append("- 昨日无显著浪费信号")
    lines.append("")
    return lines


def _tier_label(tier: str) -> str:
    return {"now": "值得现在看", "horizon": "拓展视野"}.get(tier, "拓展视野")


def _radar_section(radar) -> list[str]:
    """GitHub 工具雷达 — curated watchlist stars/delta/enrichment (§radar).

    Rendered into the local Markdown archive (the 必成 sink) so the radar is
    captured even when the AIDash push fails. Only emitted when the source is
    healthy and has repos; a degraded/absent radar prints nothing (the other
    sections must stay byte-stable, ADR-18).
    """
    if radar is None or radar.health.state != "ok" or not radar.cards:
        return []
    lines = ["## 🛰 GitHub 工具雷达"]
    for c in radar.cards:
        delta = "" if c.star_delta is None else f" ({c.star_delta:+d})"
        tail_parts = []
        if c.category:
            tail_parts.append(c.category)
        if c.related_project:
            tail_parts.append(f"↔{c.related_project}")
        tail_parts.append(_tier_label(c.tier))
        tail = " · ".join(tail_parts)
        reason = f" — {c.reason}" if c.reason else ""
        lines.append(f"- {c.repo} ⭐{c.stars}{delta} · {tail}{reason}")
    lines.append("")
    return lines


def render_digest(t: RavenTrends, report_date: str,
                  multica: MulticaTrends | None = None,
                  ado: AdoPrTrends | None = None,
                  automation: AutomationTrends | None = None,
                  repo_radar=None,
                  delivery=None) -> str:
    y = yesterday(report_date)
    lines: list[str] = [f"# AI 使用日报 {y}", ""]

    lines += [_health_line(t, multica, ado, automation), ""]

    # Delivery/XPC health — distinct from content-source health (MY-1450).
    if delivery is not None:
        from L5_apps.digest.aidash import delivery_health_line
        d_line = delivery_health_line(report_date, delivery)
        if d_line:
            lines += [d_line, ""]

    degraded = t.health.state != "ok"

    lines += _trending_section(t, report_date, degraded, multica, ado, automation)
    lines += _todo_section(t, report_date, degraded)
    lines += _yesterday_section(t, report_date, degraded, multica, ado, automation)
    lines += _improvements_section(t, report_date, degraded)
    lines += _radar_section(repo_radar)

    return "\n".join(lines)
