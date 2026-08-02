import pytest

from L5_apps.digest.trends import compute_trend, flat_streak, Trend


# Real golden series from warehouse (cost by CST day), newest-first.
COST = [
    ("2026-07-09", 2699.44), ("2026-07-08", 2180.19), ("2026-07-07", 4523.19),
    ("2026-07-06", 2493.94), ("2026-07-05", 698.83), ("2026-07-04", 1837.16),
    ("2026-07-03", 491.59), ("2026-07-02", 833.82),
]


@pytest.mark.unit
def test_compute_trend_up_vs_prev():
    # report_date 07-10 -> "yesterday" is 07-09 (2699.44) vs 07-08 (2180.19) = up
    t = compute_trend(COST, "2026-07-10")
    assert t.today == 2699.44
    assert t.prev == 2180.19
    assert t.arrow == "↑"
    assert round(t.pct_vs_prev, 1) == 23.8  # (2699.44-2180.19)/2180.19*100


@pytest.mark.unit
def test_compute_trend_7day_avg():
    # avg of 07-02..07-08 (7 days before 07-09)
    t = compute_trend(COST, "2026-07-10")
    expected_avg = round(sum(v for _, v in COST[1:8]) / 7, 2)
    assert round(t.avg7, 2) == expected_avg
    assert t.days_available == 8


@pytest.mark.unit
def test_compute_trend_flat_is_arrow_right():
    series = [("2026-07-09", 100.0), ("2026-07-08", 102.0)]
    t = compute_trend(series, "2026-07-10")  # 2% change < 5% eps
    assert t.arrow == "→"


@pytest.mark.unit
def test_compute_trend_missing_today_returns_zero_today():
    # no row for yesterday -> today=0.0, arrow →, days_available reflects series
    series = [("2026-07-01", 50.0)]
    t = compute_trend(series, "2026-07-10")
    assert t.today == 0.0
    assert t.prev is None


@pytest.mark.unit
def test_flat_streak_counts_consecutive_flat_days():
    # 07-09..07-07 all within 5% of each other, 07-06 jumps
    series = [("2026-07-09", 100.0), ("2026-07-08", 101.0),
              ("2026-07-07", 100.5), ("2026-07-06", 60.0)]
    assert flat_streak(series, "2026-07-10") == 2  # 09-vs-08 flat, 08-vs-07 flat, 07-vs-06 not
