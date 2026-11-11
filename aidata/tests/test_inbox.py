"""Tests for the action-inbox aggregator (§M3, 需要处理什么).

Hermetic: serve.run_query is monkeypatched, proposals/log readers injected.
Covers bucket aggregation, per-bucket quotas, priority sort, and degradation.
"""

import os
import time

import pytest
from L5_apps.digest import inbox as inbox_mod
from L5_apps.digest.inbox import build_inbox
from L5_apps.digest.proposals import Proposal


@pytest.fixture
def fake_queries(monkeypatch):
    """Monkeypatch serve.run_query for the two inbox SQL queries."""
    def _run(name, params=None):
        if name == "inbox/stalled-prs":
            return ([("6750052", "cookie sync fix", 480.0, "b1", "WorkspaceA"),
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
    assert "PR 卡 20 天" in titles          # 480h → 20 days
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


@pytest.mark.unit
def test_inbox_skips_done_goals_and_preserves_proposal_ref(monkeypatch):
    def run_query(name, params=None):
        if name == "retro/gtt_scorecard":
            return ([("done-goal", "done", 4), ("open-goal", "blocked", 1)],
                    ["goal_id", "actual_status", "task_blocked_count"])
        return ([], [])

    monkeypatch.setattr(inbox_mod.serve, "run_query", run_query)
    signals = inbox_mod._retro_signals()
    assert all("done-goal" not in item.title for item in signals)

    items = inbox_mod._proposals(
        lambda: [Proposal("proposal://p1", "t", "agent", "title", "", "high", "pending")]
    )
    assert items[0].ref == "proposal://p1"


@pytest.mark.unit
def test_stalled_pr_older_than_thirty_days_is_not_actionable(monkeypatch):
    def run_query(name, params=None):
        if name == "inbox/stalled-prs":
            return ([
                ("old", "old PR", 31 * 24, "b", "R"),
                ("fresh", "fresh PR", 20 * 24, "b", "R"),
            ], ["pr_id", "title", "age_hours", "source_branch", "repo"])
        return ([], [])

    monkeypatch.setattr(inbox_mod.serve, "run_query", run_query)
    items = build_inbox(0.0, proposals_reader=_no_proposals, log_reader=_no_logs)
    titles = " ".join(item.title for item in items)
    assert "old PR" not in titles
    assert "fresh PR" in titles


@pytest.mark.unit
def test_old_cron_log_line_is_not_actionable(tmp_path):
    log = tmp_path / "cron-errors.log"
    log.write_text("2026-10-01T04:00:00Z — old failure\n", encoding="utf-8")
    old = time.time() - 8 * 24 * 60 * 60
    os.utime(log, (old, old))
    assert inbox_mod._default_log_reader(log) == ""


@pytest.mark.unit
def test_recent_embedded_cron_timestamp_is_actionable(tmp_path):
    log = tmp_path / "cron-errors.log"
    log.write_text("2026-11-05T04:00:00Z — recent failure\n", encoding="utf-8")
    old = time.time() - 8 * 24 * 60 * 60
    os.utime(log, (old, old))
    assert "recent failure" in inbox_mod._default_log_reader(log)


@pytest.mark.unit
def test_pending_issues_emits_canonical_linear_ref_for_tia_items(monkeypatch):
    def run_query(name, params=None):
        if name == "inbox/pending-issues":
            return (
                [
                    ("TIA-90", "Voice todo from VoxPocket", "todo", "high"),
                    ("MY-12", "Legacy multica todo", "todo", "medium"),
                ],
                ["identifier", "title", "status", "priority"],
            )
        return ([], [])

    monkeypatch.setattr(inbox_mod.serve, "run_query", run_query)
    items = inbox_mod._pending_issues()
    assert len(items) == 2
    assert items[0].ref == "linear://TIA-90"
    assert items[1].ref == "MY-12"


@pytest.mark.unit
def test_mail_and_work_watch_signals_surface_in_build_inbox(tmp_path, monkeypatch):
    import sqlite3

    monkeypatch.setattr(inbox_mod.serve, "run_query", lambda *_a, **_k: ([], []))
    teams_db = tmp_path / "work_teams_bridge.db"
    with sqlite3.connect(teams_db) as conn:
        conn.execute(
            "CREATE TABLE work_teams_item ("
            "item_id TEXT, cursor TEXT, dedup_key TEXT, channel_kind TEXT, "
            "sender_alias TEXT, title_preview TEXT, summary_preview TEXT, "
            "has_mention INTEGER, needs_reply INTEGER, priority TEXT, replied INTEGER)"
        )
        conn.execute(
            "INSERT INTO work_teams_item VALUES "
            "('wt-1', '20261111T040000Z#wt-1', 'teams:wt-1', 'teams_mention', "
            "'alice', 'Please review Q4 architecture', 'Need sign-off', 1, 1, 'high', 0), "
            "('wt-2', '20261111T030000Z#wt-2', 'teams:wt-2', 'teams_mention', "
            "'bob', 'Already replied thread', 'Done', 1, 1, 'high', 1)"
        )

    mail_db = tmp_path / "mail_inbox.db"
    with sqlite3.connect(mail_db) as conn:
        conn.execute(
            "CREATE TABLE mail_inbox_item ("
            "item_id TEXT, cursor TEXT, dedup_key TEXT, sender_domain TEXT, "
            "subject_preview TEXT, snippet_preview TEXT, has_mention INTEGER, "
            "is_todo INTEGER, priority TEXT, replied INTEGER)"
        )
        conn.execute(
            "INSERT INTO mail_inbox_item VALUES "
            "('m-1', '20261111T050000Z#m-1', 'mail:m-1', 'corp.example.com', "
            "'Action required: approve release', 'Urgent todo', 0, 1, 'high', 0)"
        )

    items = build_inbox(
        0.0,
        proposals_reader=_no_proposals,
        log_reader=_no_logs,
        mail_db_path=mail_db,
        teams_db_path=teams_db,
    )
    refs = [it.ref for it in items]
    titles = " | ".join(it.title for it in items)
    assert "teams:wt-1" in refs
    assert "teams:wt-2" not in refs
    assert "mail:m-1" in refs
    assert "[Teams @我] alice" in titles
    assert "[邮件待办] corp.example.com" in titles


@pytest.mark.unit
def test_inbox_surfaces_skill_roi_proposals_and_retro_signals(monkeypatch):
    def run_query(name, params=None):
        if name == "retro/skill_roi_diagnostics":
            return (
                [("my-designer", 0.32, 0.75, 0.50)],
                ["skill", "roi_score", "unpracticed_rate", "r1_pass_rate"],
            )
        return ([], [])

    monkeypatch.setattr(inbox_mod.serve, "run_query", run_query)
    signals = inbox_mod._retro_signals()
    assert any(it.ref == "skill-roi://my-designer" and "ROI 偏低" in it.title for it in signals)

    props = inbox_mod._proposals(
        lambda: [
            Proposal(
                "skill-roi-my-designer",
                "2026-11-11T00:00:00Z",
                "retro-loop",
                "[Skill ROI] 优化 my-designer",
                "detail",
                "high",
                "pending",
                ref="skill-roi://my-designer",
            )
        ]
    )
    assert props[0].ref == "skill-roi://my-designer"
