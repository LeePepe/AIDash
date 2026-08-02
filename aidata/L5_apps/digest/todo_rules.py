"""Rule-based TODO candidate generation (ADR-8, M1 = rules only, no LLM).

Hard thresholds turn yesterday's numbers into actionable items. In later
milestones an LLM refines/ranks these; in M1 the rules ARE the output.
"""

from __future__ import annotations

from dataclasses import dataclass

from L5_apps.digest.cst import yesterday

WASTE_USD_P1 = 500.0
COST_SPIKE_PCT = 50.0
CANCEL_RATIO_P0 = 0.30


@dataclass(frozen=True)
class Todo:
    priority: str   # P0 | P1 | P2
    text: str


def _val(series: list[tuple[str, float]], day: str) -> float:
    return dict(series).get(day, 0.0)


def todo_candidates(t, report_date: str) -> list[Todo]:
    """Deterministic TODO items from yesterday's signals, most-severe first."""
    y = yesterday(report_date)
    out: list[Todo] = []

    # P0: pipeline cancellation ratio
    done = _val(t.pipeline_completed, y)
    cx = _val(t.pipeline_cancelled, y)
    runs = done + cx
    if runs > 0 and cx / runs > CANCEL_RATIO_P0:
        out.append(Todo("P0", f"查 pipeline:{int(cx)}/{int(runs)} run 被取消(取消率"
                               f"{cx / runs * 100:.0f}%)"))

    # P1: waste spend
    waste = _val(t.waste, y)
    if waste > WASTE_USD_P1:
        out.append(Todo("P1", f"审查浪费:${waste:.0f} 花在极小输出/大上下文请求"))

    # P1: cost spike vs 7-day avg
    from L5_apps.digest.trends import compute_trend
    ct = compute_trend(t.cost, report_date)
    if ct.avg7 and ct.avg7 > 0 and ct.today > ct.avg7 * (1 + COST_SPIKE_PCT / 100):
        out.append(Todo("P1", f"成本异常:昨日 ${ct.today:.0f} vs 7日均值 ${ct.avg7:.0f}"))

    # Order: P0 first, then P1, then P2; cap P0 at 2 (ADR-14).
    order = {"P0": 0, "P1": 1, "P2": 2}
    out.sort(key=lambda td: order[td.priority])
    p0 = [td for td in out if td.priority == "P0"][:2]
    rest = [td for td in out if td.priority != "P0"]
    return p0 + rest
