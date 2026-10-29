from pathlib import Path

import pytest

from L5_apps.digest.sources import (
    RetroOpsTrends,
    SourceHealth,
    fetch_raven_trends,
    fetch_retro_ops_trends,
    RavenTrends,
)

_WAREHOUSE = Path(__file__).resolve().parent.parent / "L3_merge" / "warehouse.db"


@pytest.mark.integration
@pytest.mark.skipif(
    not _WAREHOUSE.exists(),
    reason="warehouse.db not built (gitignored local artifact) — run `cli.py merge`",
)
def test_fetch_raven_trends_returns_series_and_ok_health():
    t = fetch_raven_trends()
    assert isinstance(t, RavenTrends)
    assert t.health.state == "ok"
    # cost series has 2026-07-09 with a plausible positive value. Range-based,
    # not an exact literal — cost drifts as new raven data is collected, so a
    # hardcoded number would break on every re-collect (this is an integration
    # test against the live warehouse). The hermetic exact-value check lives in
    # test_digest_golden.py against a frozen fixture.
    cost = dict(t.cost)
    assert cost["2026-07-09"] > 1000.0
    # every series is a list of (day, number) tuples
    for day, val in t.cost:
        assert isinstance(day, str) and isinstance(val, (int, float))


@pytest.mark.unit
def test_source_health_dataclass_shape():
    h = SourceHealth(name="raven", state="ok", detail="")
    assert h.name == "raven" and h.state == "ok"


@pytest.mark.unit
def test_fetch_raven_trends_degrades_on_query_failure(monkeypatch):
    # ADR-23: a query failure must degrade to empty series + error health,
    # never propagate the exception.
    import serve

    def boom(*args, **kwargs):
        raise RuntimeError("simulated query failure")

    monkeypatch.setattr(serve, "run_query", boom)
    t = fetch_raven_trends()
    assert t.health.state == "error"
    assert "simulated query failure" in t.health.detail
    assert t.cost == [] and t.tokens == [] and t.requests == []
    assert t.waste == [] and t.pipeline_completed == [] and t.sessions == []


@pytest.mark.unit
def test_fetch_retro_ops_trends_maps_l4_rows(monkeypatch):
    queries = {
        "retro/ci_health_and_noise": (
            [("repo-a", "all", "push", 10, 8, 1, 1, 0.889, 1)],
            ["repo_key", "workflow_category", "event_trigger", "run_count",
             "success_count", "failure_count", "cancelled_or_timeout_count",
             "pass_rate", "config_noise_job_count"],
        ),
        "retro/gtt_scorecard": (
            [("G-1", "done"), ("G-1", "done"), ("G-2", "blocked")],
            ["goal_id", "actual_status"],
        ),
        "retro/bot_tl_operations": (
            [("machine", "NEED_GO", "ok", 2, "ts", 4, 1, 0, "ok")],
            ["machine_alias", "action_kind", "status", "action_count",
             "latest_heartbeat_ts", "latest_checked_pr_count",
             "latest_stuck_pr_count", "latest_repair_queued_count",
             "latest_heartbeat_status"],
        ),
        "retro/tf_release_deliveries": ([], []),
        "retro/workspace_hygiene_reclaim": ([], []),
    }

    monkeypatch.setattr("serve.run_query", lambda name, params=None: queries[name])
    trends = fetch_retro_ops_trends()

    assert isinstance(trends, RetroOpsTrends)
    assert trends.health.state == "ok"
    assert trends.ci_segments == (
        ("通过", 8.0, "success"),
        ("配置异常", 1.0, "warning"),
        ("取消/超时", 1.0, None),
    )
    assert trends.gtt_segments == (("已完成", 1.0, "success"),
                                   ("阻塞", 1.0, "warning"))
    assert trends.bot_tl_bars == (("NEED_GO", 2.0, "2次", "warning"),)
    assert trends.ci_pass_ratio == 0.8
    assert trends.gtt_done_ratio == 0.5
    assert trends.prmon_checked == 4 and trends.prmon_stuck == 1
