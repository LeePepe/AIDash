import pytest

from L5_apps.digest.cst import (
    cst_date_of_ms, yesterday, recent_days, CST_DAY_EXPR,
)


@pytest.mark.unit
def test_cst_date_of_ms_shifts_plus_8():
    # 2026-07-09 23:30 UTC = 2026-07-10 07:30 CST -> CST date is 07-10
    ts = 1783639800000  # 2026-07-09T23:30:00Z
    assert cst_date_of_ms(ts) == "2026-07-10"
    # 2026-07-09 15:00 UTC = 2026-07-09 23:00 CST -> still 07-09
    ts2 = 1783609200000  # 2026-07-09T15:00:00Z
    assert cst_date_of_ms(ts2) == "2026-07-09"


@pytest.mark.unit
def test_cst_date_boundary_16utc_is_next_cst_day():
    # 16:00 UTC = 00:00 CST next day (the exact day flip)
    ts = 1783612800000  # 2026-07-09T16:00:00Z == 2026-07-10T00:00 CST
    assert cst_date_of_ms(ts) == "2026-07-10"


@pytest.mark.unit
def test_yesterday():
    assert yesterday("2026-07-10") == "2026-07-09"
    assert yesterday("2026-03-01") == "2026-02-28"  # month boundary


@pytest.mark.unit
def test_recent_days_newest_first_excludes_report_date():
    assert recent_days("2026-07-10", 3) == ["2026-07-09", "2026-07-08", "2026-07-07"]


@pytest.mark.unit
def test_cst_day_expr_is_plus_8_hours():
    assert CST_DAY_EXPR == "date(ts/1000,'unixepoch','+8 hours')"
