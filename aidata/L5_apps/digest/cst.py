"""CST (Asia/Shanghai) day-boundary helpers for the digest.

aidata stores timestamps as UTC epoch-ms. The digest reports on CST calendar
days (ADR-2). All day bucketing uses a fixed +8h offset — never the host's
local timezone — so results are host-TZ-independent (ADR-22).
"""

from __future__ import annotations

from datetime import datetime, timedelta

from timeutil import CST as _CST, epoch_ms_to_cst_day

# The SQL day-bucket expression, defined once so every trend query agrees.
CST_DAY_EXPR = "date(ts/1000,'unixepoch','+8 hours')"


def cst_date_of_ms(ts_ms: int) -> str:
    """UTC epoch-milliseconds -> 'YYYY-MM-DD' in CST (thin wrapper; seam)."""
    return epoch_ms_to_cst_day(ts_ms)


def _parse(day: str) -> datetime:
    return datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=_CST)


def yesterday(report_date: str) -> str:
    """The CST calendar day before report_date."""
    return (_parse(report_date) - timedelta(days=1)).strftime("%Y-%m-%d")


def recent_days(report_date: str, n: int) -> list[str]:
    """The n CST days strictly before report_date, newest-first."""
    base = _parse(report_date)
    return [(base - timedelta(days=i)).strftime("%Y-%m-%d") for i in range(1, n + 1)]
