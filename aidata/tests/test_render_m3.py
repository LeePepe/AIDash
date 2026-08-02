"""Tests for M3 render additions: ADO PR + automation in Trending/昨日汇总."""

import pytest

from L5_apps.digest.sources import (
    RavenTrends, AdoPrTrends, AutomationTrends, SourceHealth,
)
from L5_apps.digest.render import render_digest

COST = [("2026-07-09", 2699.44), ("2026-07-08", 2180.19), ("2026-07-07", 4523.19)]


def _raven():
    return RavenTrends(
        cost=COST, tokens=[(d, v * 1000) for d, v in COST],
        requests=[("2026-07-09", 8273.0), ("2026-07-08", 4595.0)],
        waste=[("2026-07-09", 100.0)],
        pipeline_completed=[("2026-07-09", 32.0)],
        pipeline_cancelled=[("2026-07-09", 5.0)],
        sessions=[("2026-07-09", 40.0), ("2026-07-08", 38.0)],
        health=SourceHealth("raven", "ok"),
    )


def _ado(state="ok"):
    return AdoPrTrends(
        opened=[("2026-07-09", 3.0), ("2026-07-08", 1.0)],
        merged=[("2026-07-09", 2.0), ("2026-07-08", 0.0)],
        health=SourceHealth("ado_pr", state),
    )


def _auto(state="ok"):
    return AutomationTrends(
        ratio=[("2026-07-09", 0.8), ("2026-07-08", 0.5)],
        automated=[("2026-07-09", 8.0), ("2026-07-08", 3.0)],
        manual=[("2026-07-09", 2.0), ("2026-07-08", 3.0)],
        health=SourceHealth("state_db", state),
    )


@pytest.mark.unit
def test_render_backward_compatible_without_m3_args():
    # M1 two-arg call still yields the four sections unchanged.
    md = render_digest(_raven(), "2026-07-10")
    assert "## ⚡ Trending" in md
    assert "## 🗂 昨日汇总" in md
    assert "开了" not in md  # no ADO line when ado not provided
    assert "自动化" not in md


@pytest.mark.unit
def test_render_ado_opened_arrow_in_trending():
    md = render_digest(_raven(), "2026-07-10", ado=_ado())
    assert "开PR" in md
    assert "↑" in md  # opened 3 > 1 prev


@pytest.mark.unit
def test_render_ado_yesterday_summary_line():
    md = render_digest(_raven(), "2026-07-10", ado=_ado())
    # yesterday of 2026-07-10 is 2026-07-09: opened 3, merged 2
    assert "开了 3 个 PR" in md
    assert "合并 2" in md


@pytest.mark.unit
def test_render_automation_ratio_in_yesterday_summary():
    md = render_digest(_raven(), "2026-07-10", automation=_auto())
    assert "自动化占比" in md
    assert "80%" in md          # 0.8 -> 80%
    assert "自动 8" in md and "手动 2" in md


@pytest.mark.unit
def test_render_ado_degraded_shows_health_no_fake_arrow():
    md = render_digest(_raven(), "2026-07-10", ado=_ado(state="skipped:未采集"))
    assert "ADO" in md and "未采集" in md
    # no fabricated opened count in 昨日汇总 for a skipped source
    assert "开了 3 个 PR" not in md


@pytest.mark.unit
def test_render_automation_degraded_shows_health():
    md = render_digest(_raven(), "2026-07-10", automation=_auto(state="error"))
    assert "state.db" in md
    assert "自动化占比 80%" not in md


@pytest.mark.unit
def test_render_health_line_lists_all_provided_sources():
    md = render_digest(_raven(), "2026-07-10", ado=_ado(), automation=_auto())
    line = md.splitlines()[2]  # the "> 数据源:" line
    assert "raven" in line and "ADO" in line and "state.db" in line
