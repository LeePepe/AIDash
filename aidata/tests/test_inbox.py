"""Tests for the action-inbox aggregator (§M3, 需要处理什么).

Hermetic: serve.run_query is monkeypatched, proposals/log readers injected.
Covers bucket aggregation, per-bucket quotas, priority sort, and degradation.
"""

import pytest
from L5_apps.digest import inbox as inbox_mod
from L5_apps.digest.inbox import build_inbox
from L5_apps.digest.proposals import Proposal


@pytest.fixture
def fake_queries(monkeypatch):
    """Monkeypatch serve.run_query for the two inbox SQL queries."""
    def _run(name, params=None):
        if name == "inbox/stalled-prs":
            return ([("6750052", "cookie sync fix", 1112.0, "b1", "WorkspaceA"),
                     ("6805136", "screenshot crash", 745.0, "b2", "WorkspaceA")],
                    ["pr_id", "title", "age_hours", "source_branch", "repo"])
        if name == "inbox/pending-issues":
            return ([("ABC-297", "Swift 6 migration", "blocked", "high"),
                     ("MY-1", "plain todo", "todo", "medium")],
                    ["identifier", "title", "status", "priority"])
        return ([], [])
    monkeypatch.setattr(inbox_mod.serve, "run_query", _run)


def _no_logs(_path):
    return ""


def _no_proposals():
    return []


@pytest.mark.unit
def test_aggregates_stalls_and_issues(fake_queries):
    items = build_inbox(0.0, proposals_reader=_no_proposals, log_reader=_no_logs)
    buckets = {it.bucket for it in items}
    assert "卡顿" in buckets
    titles = " ".join(it.title for it in items)
    assert "PR 卡 46 天" in titles          # 1112h → 46 days
    assert "ABC-297" in titles              # blocked issue


@pytest.mark.unit
def test_blocked_is_high_todo_is_medium_or_planned(fake_queries):
    items = build_inbox(0.0, proposals_reader=_no_proposals, log_reader=_no_logs)
    wsa = next(it for it in items if "ABC-297" in it.title)
    assert wsa.priority == "high" and wsa.bucket == "卡顿"
    todo = [it for it in items if "plain todo" in it.title]
    if todo:
        assert todo[0].bucket == "计划"


@pytest.mark.unit
def test_proposals_surface_as_decisions(fake_queries):
    def _props():
        return [Proposal("p1", "t", "pm-agent", "立项 X", "", "high", "pending")]
    items = build_inbox(0.0, proposals_reader=_props, log_reader=_no_logs)
    dec = [it for it in items if it.bucket == "待决策"]
    assert dec and "pm-agent" in dec[0].title and dec[0].priority == "high"


@pytest.mark.unit
def test_downgrade_finding_over_threshold(fake_queries):
    items = build_inbox(3403.0, proposals_reader=_no_proposals, log_reader=_no_logs)
    find = [it for it in items if it.bucket == "发现"]
    assert find and "$3403" in find[0].title


@pytest.mark.unit
def test_downgrade_finding_below_threshold_absent(fake_queries):
    items = build_inbox(100.0, proposals_reader=_no_proposals, log_reader=_no_logs)
    assert not [it for it in items if it.bucket == "发现"]


@pytest.mark.unit
def test_error_logs_become_high_stalls(fake_queries):
    def _log(path):
        return "2026-07-18 push failed" if "push" in str(path) else ""
    items = build_inbox(0.0, proposals_reader=_no_proposals, log_reader=_log)
    errs = [it for it in items if "报错" in it.title]
    assert errs and errs[0].priority == "high"


@pytest.mark.unit
def test_quota_prevents_stall_wall(monkeypatch):
    # 20 stalled PRs must not crowd out a pending decision.
    def _run(name, params=None):
        if name == "inbox/stalled-prs":
            return ([(str(i), f"pr{i}", 200.0 + i, "b", "R") for i in range(20)],
                    ["pr_id", "title", "age_hours", "source_branch", "repo"])
        return ([], [])
    monkeypatch.setattr(inbox_mod.serve, "run_query", _run)

    def _props():
        return [Proposal("p1", "t", "a", "decide me", "", "high", "pending")]
    items = build_inbox(0.0, proposals_reader=_props, log_reader=_no_logs)
    stalls = [it for it in items if it.bucket == "卡顿"]
    decisions = [it for it in items if it.bucket == "待决策"]
    assert len(stalls) <= 5              # quota caps stalls
    assert decisions                     # decision still present


@pytest.mark.unit
def test_degrades_when_query_raises(monkeypatch):
    def _boom(name, params=None):
        raise RuntimeError("db gone")
    monkeypatch.setattr(inbox_mod.serve, "run_query", _boom)
    # Must not raise; buckets that failed are just empty.
    items = build_inbox(0.0, proposals_reader=_no_proposals, log_reader=_no_logs)
    assert isinstance(items, list)


@pytest.mark.unit
def test_sorted_high_before_medium(fake_queries):
    items = build_inbox(3403.0, proposals_reader=_no_proposals, log_reader=_no_logs)
    prios = [inbox_mod._PRIO_RANK[it.priority] for it in items]
    assert prios == sorted(prios)        # non-decreasing priority rank


def test_retro_signals_surface_and_build_inbox(monkeypatch):
    queries = {
        "retro/gtt_scorecard": (
            [
                ("goal-1", "blocked", 2),
                ("goal-1", "blocked", 2),
                ("goal-2", "active", 1),
            ],
            ["goal_id", "actual_status", "task_blocked_count"],
        ),
        "retro/ci_health_and_noise": (
            [("repo-a", 3), ("repo-b", 1)],
            ["repo_key", "config_noise_job_count"],
        ),
        "retro/workspace_hygiene_reclaim": (
            [("repo-a", 2), ("repo-b", 1)],
            ["repo_key", "reclaimable_count"],
        ),
    }

    def run_query(name, params=None):
        return queries.get(name, ([], []))

    monkeypatch.setattr(inbox_mod.serve, "run_query", run_query)

    signals = inbox_mod._retro_signals()
    titles = " ".join(item.title for item in signals)
    assert "GTT 阻塞：goal-1（2 项阻塞）" in titles
    assert "CI 配置噪音 4 次（如 repo-a）" in titles
    assert "3 个已合并洁净 Worktree" in titles
    assert len([item for item in signals if item.ref == "goal-1"]) == 1

    items = build_inbox(
        proposals_reader=_no_proposals, log_reader=_no_logs)
    assert any("GTT 阻塞" in item.title for item in items)


def test_retro_signals_degrade_cleanly(monkeypatch):
    def run_query(name, params=None):
        if name == "retro/gtt_scorecard":
            raise RuntimeError("missing table")
        if name == "retro/ci_health_and_noise":
            return ([], [])
        raise ValueError("unavailable")

    monkeypatch.setattr(inbox_mod.serve, "run_query", run_query)

    assert inbox_mod._retro_signals() == []
    assert inbox_mod.build_inbox(
        proposals_reader=_no_proposals, log_reader=_no_logs) == []
