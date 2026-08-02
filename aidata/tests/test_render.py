import pytest

from L5_apps.digest.sources import RavenTrends, SourceHealth
from L5_apps.digest.render import render_digest

COST = [("2026-07-09", 2699.44), ("2026-07-08", 2180.19), ("2026-07-07", 4523.19),
        ("2026-07-06", 2493.94), ("2026-07-05", 698.83), ("2026-07-04", 1837.16),
        ("2026-07-03", 491.59), ("2026-07-02", 833.82)]


def _rt(health_state="ok"):
    return RavenTrends(
        cost=COST, tokens=[(d, v * 1000) for d, v in COST],
        requests=[("2026-07-09", 8273.0), ("2026-07-08", 4595.0)],
        waste=[("2026-07-09", 800.0)],
        pipeline_completed=[("2026-07-09", 32.0)],
        pipeline_cancelled=[("2026-07-09", 15.0)],
        sessions=[("2026-07-09", 40.0), ("2026-07-08", 38.0)],
        health=SourceHealth("raven", health_state),
    )


@pytest.mark.unit
def test_render_has_four_sections():
    md = render_digest(_rt(), "2026-07-10")
    assert "## ⚡ Trending" in md
    assert "## 📅 今日 TODO" in md
    assert "## 🗂 昨日汇总" in md
    assert "## 🔍 可改良" in md


@pytest.mark.unit
def test_render_cost_arrow_up():
    md = render_digest(_rt(), "2026-07-10")
    assert "↑" in md  # cost 2699 > 2180 prev


@pytest.mark.unit
def test_render_is_deterministic():
    assert render_digest(_rt(), "2026-07-10") == render_digest(_rt(), "2026-07-10")


@pytest.mark.unit
def test_render_degraded_source_shows_missing():
    md = render_digest(_rt(health_state="error"), "2026-07-10")
    assert "数据缺失" in md or "error" in md


@pytest.mark.unit
def test_render_insufficient_data_shows_days_only():
    rt = RavenTrends(
        cost=[("2026-07-09", 100.0)],  # only 1 day -> days_available < 2
        tokens=[("2026-07-09", 5000.0)],
        requests=[("2026-07-09", 50.0)],
        waste=[("2026-07-09", 10.0)],
        pipeline_completed=[("2026-07-09", 3.0)],
        pipeline_cancelled=[("2026-07-09", 1.0)],
        sessions=[("2026-07-09", 4.0)],
        health=SourceHealth("raven", "ok"),
    )
    md = render_digest(rt, "2026-07-10")
    assert "数据仅 1 天" in md
