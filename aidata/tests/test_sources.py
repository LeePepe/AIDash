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
            [("repo-a", "all", "push", 10, 8, 1, 1, 0.889, 1),
             ("repo-a", "build", "pull_request", 2, 1, 1, 0, 0.5, 0),
             ("repo-b", "all", "push", 4, 4, 0, 0, 1.0, 0)],
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
        "retro/tf_release_deliveries": (
            [("repo-a", "iOS", 2, 1), ("repo-b", "macOS", 5, 0)],
            ["repo_key", "target_platform", "delivery_count",
             "failed_delivery_count"],
        ),
        "retro/workspace_hygiene_reclaim": (
            [("repo-a", "worktree", 3)],
            ["repo_key", "entity_type", "reclaimable_count"],
        ),
    }

    monkeypatch.setattr("serve.run_query", lambda name, params=None: queries[name])
    monkeypatch.setattr(
        "L5_apps.digest.sources._claude_job_counts",
        lambda: (("completed", 2.0), ("failed", 1.0)),
    )
    trends = fetch_retro_ops_trends()

    assert isinstance(trends, RetroOpsTrends)
    assert trends.health.state == "ok"
    assert trends.ci_segments == (
        ("通过", 13.0, "success"),
        ("门禁拦截", 1.0, None),
        ("配置异常", 1.0, "warning"),
        ("取消/超时", 1.0, None),
    )
    assert trends.gtt_segments == (("已完成", 1.0, "success"),
                                   ("阻塞", 1.0, "warning"))
    assert trends.bot_tl_bars == (("NEED_GO", 2.0, "2次", "warning"),)
    assert trends.ci_pass_ratio == 13 / 16
    assert trends.gtt_done_ratio == 0.5
    assert trends.prmon_checked == 4 and trends.prmon_stuck == 1
    assert trends.ci_points == (
        ("repo-a", 12.0, 9 / 11), ("repo-b", 4.0, 1.0))
    assert [item[1] for item in trends.release_tf_bars] == [5.0, 2.0]
    assert trends.workspace_hygiene_bars[0][1] == 3.0
    assert trends.claude_jobs == (("completed", 2.0), ("failed", 1.0))


@pytest.mark.unit
def test_retro_ops_keeps_release_and_hygiene_without_ci(monkeypatch):
    queries = {
        "retro/ci_health_and_noise": ([], []),
        "retro/gtt_scorecard": ([], []),
        "retro/bot_tl_operations": ([], []),
        "retro/tf_release_deliveries": (
            [("repo-a", "iOS", 2, 0)],
            ["repo_key", "target_platform", "delivery_count",
             "failed_delivery_count"],
        ),
        "retro/workspace_hygiene_reclaim": ([], []),
    }
    monkeypatch.setattr("serve.run_query", lambda name, params=None: queries[name])
    monkeypatch.setattr("L5_apps.digest.sources._claude_job_counts", lambda: ())

    trends = fetch_retro_ops_trends()

    assert trends.health.state == "ok"
    assert trends.release_tf_bars[0][1] == 2.0
