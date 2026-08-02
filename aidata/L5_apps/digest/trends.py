"""Trend math: day-over-day arrows, 7-day average, flat-streak detection.

Pure functions on (day, value) series. A dimension with too few days still
returns a Trend, but callers check `days_available` to decide whether to print
an arrow or "数据仅 N 天" (ADR-3).
"""

from __future__ import annotations

from dataclasses import dataclass

from L5_apps.digest.cst import yesterday


@dataclass(frozen=True)
class Trend:
    today: float
    prev: float | None
    avg7: float | None
    arrow: str
    pct_vs_prev: float | None
    days_available: int


def _as_map(series: list[tuple[str, float]]) -> dict[str, float]:
    return {day: val for day, val in series}


def compute_trend(series: list[tuple[str, float]], report_date: str,
                  flat_eps: float = 0.05) -> Trend:
    """Compute today (=yesterday-of-report) vs prev day and 7-day trailing avg."""
    m = _as_map(series)
    y = yesterday(report_date)
    today = m.get(y, 0.0)

    from L5_apps.digest.cst import recent_days
    prior_days = recent_days(y, 1)          # the single day before "today"
    prev = m.get(prior_days[0]) if prior_days else None

    avg_days = recent_days(y, 7)            # 7 days before "today"
    avg_vals = [m[d] for d in avg_days if d in m]
    avg7 = round(sum(avg_vals) / len(avg_vals), 2) if avg_vals else None

    if prev is None or prev == 0:
        arrow, pct = "→", None
    else:
        pct = (today - prev) / prev * 100
        if abs(today - prev) / prev <= flat_eps:
            arrow = "→"
        else:
            arrow = "↑" if today > prev else "↓"

    return Trend(today=today, prev=prev, avg7=avg7, arrow=arrow,
                 pct_vs_prev=pct, days_available=len(series))


def flat_streak(series: list[tuple[str, float]], report_date: str,
                flat_eps: float = 0.05) -> int:
    """Count consecutive most-recent days (ending yesterday) with flat change."""
    m = _as_map(series)
    from L5_apps.digest.cst import recent_days
    # Days from yesterday backwards that exist in the series.
    chain = [yesterday(report_date)] + recent_days(yesterday(report_date), 30)
    present = [d for d in chain if d in m]
    streak = 0
    for i in range(len(present) - 1):
        cur, nxt = m[present[i]], m[present[i + 1]]
        if nxt != 0 and abs(cur - nxt) / nxt <= flat_eps:
            streak += 1
        else:
            break
    return streak
