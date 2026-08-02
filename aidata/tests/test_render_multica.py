import pytest

from L5_apps.digest.sources import RavenTrends, SourceHealth, MulticaTrends
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


def _mt(health_state="ok"):
    return MulticaTrends(
        completed=[("2026-07-09", 8.0), ("2026-07-08", 5.0)],
        completed_by_ws={
            "WorkspaceA": [("2026-07-09", 3.0)],
            "my": [("2026-07-09", 5.0), ("2026-07-08", 5.0)],
        },
        health=SourceHealth("multica", health_state),
    )


@pytest.mark.unit
def test_render_shows_completed_issue_trend():
    md = render_digest(_rt(), "2026-07-10", multica=_mt())
    assert "完成 issue" in md
    assert "近似" in md  # ADR-19: label approximate


@pytest.mark.unit
def test_render_yesterday_completed_per_workspace():
    md = render_digest(_rt(), "2026-07-10", multica=_mt())
    assert "昨日完成" in md
    assert "WorkspaceA" in md and "my" in md


@pytest.mark.unit
def test_render_multica_health_in_source_line():
    md = render_digest(_rt(), "2026-07-10", multica=_mt("error"))
    assert "multica" in md


@pytest.mark.unit
def test_render_degraded_multica_shows_missing_not_fake_trend():
    md = render_digest(_rt(), "2026-07-10", multica=_mt("error"))
    # completed dimension must not print a fabricated arrow when source failed
    assert "数据缺失" in md


@pytest.mark.unit
def test_render_without_multica_stays_backward_compatible():
    # M1 callers pass no multica arg — must not crash.
    md = render_digest(_rt(), "2026-07-10")
    assert "## ⚡ Trending" in md


@pytest.mark.unit
def test_render_with_multica_is_deterministic():
    a = render_digest(_rt(), "2026-07-10", multica=_mt())
    b = render_digest(_rt(), "2026-07-10", multica=_mt())
    assert a == b
