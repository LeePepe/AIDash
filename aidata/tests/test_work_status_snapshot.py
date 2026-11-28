from __future__ import annotations

import json
import re
import sqlite3

from L5_apps.digest import work_status_snapshot as wss

_BANNED_LABEL_PATTERNS = (
    re.compile(r"\bS(?:[1-9]|1[0-2])\b"),
    re.compile(r"\bM[1-5]\b"),
    re.compile(r"\bE[1-9]\b"),
    re.compile(r"\bL[0-3]\b"),
    re.compile(r"\bR[1-4](?:_|\b)"),
    re.compile(r"\bH[1-5]\b"),
    re.compile(r"\bHZN[1-5]\b"),
    re.compile(r"\bpython3\b", re.IGNORECASE),
    re.compile(r"\bSKILL\.md\b"),
    re.compile(r"\bsession_id\b", re.IGNORECASE),
    re.compile(r"\.py\b"),
)


def _assert_plain_language_labels(text: str) -> None:
    for pat in _BANNED_LABEL_PATTERNS:
        assert not pat.search(text), f"banned code {pat.pattern!r} leaked into plain-language label {text!r}"


def test_work_status_snapshot_emits_goals_action_split_unassigned_bucket_and_plain_signals(tmp_path):
    warehouse = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse) as conn:
        conn.executescript(
            """
            CREATE TABLE fact_agent_retro_finding (
                finding_uid TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                session_id TEXT NOT NULL,
                goal_id TEXT,
                role_key TEXT NOT NULL,
                skill TEXT NOT NULL,
                layer_key TEXT NOT NULL,
                finding_code TEXT NOT NULL,
                severity TEXT NOT NULL,
                skill_version TEXT,
                is_post_fix INTEGER NOT NULL,
                occurrence_count INTEGER NOT NULL,
                ts TEXT NOT NULL,
                cst_day TEXT GENERATED ALWAYS AS (date(ts, '+8 hours')) STORED
            );
            """
        )
        conn.execute(
            "INSERT INTO fact_agent_retro_finding "
            "(finding_uid, source, session_id, goal_id, role_key, skill, layer_key, finding_code, "
            "severity, skill_version, is_post_fix, occurrence_count, ts) "
            "VALUES ('f1', 'copilot_cli', 's1', 'goal-newest', 'm1', 'team-lead', 'handoff', "
            "'H3_r10_receipt_gap_or_dirty_schema', 'high', 'v20@abc1234', 1, 2, '2026-11-26T04:00:00Z')"
        )
        conn.commit()

    cols = [
        "session_uid", "source", "session_id_short", "goal_id", "is_unassigned_bucket",
        "goal_title", "repo_name", "branch_name", "goal_status", "review_round_badge",
        "role_key", "model_id", "summary_label", "started_at", "ended_at",
        "duration_sec", "turn_count", "total_tokens", "skills_json",
        "search_read_calls", "code_edit_calls", "verify_script_calls", "spin_rework_calls",
        "files_changed_count", "commits_count", "pr_number", "slow_or_failed_scripts_json",
        "ref_hit_count", "script_call_count", "ref_skills_csv", "script_skills_csv",
        "session_search_to_edit_ratio", "goal_session_count", "goal_duration_sec",
        "goal_total_tokens", "goal_search_read_calls", "goal_code_edit_calls",
        "goal_verify_script_calls", "goal_spin_rework_calls", "goal_files_changed_count",
        "goal_commits_count", "goal_pr_number", "goal_ref_hit_count", "goal_script_call_count",
        "goal_search_to_edit_ratio", "goal_latest_ts", "cst_day", "window_start",
        "window_end", "window_cst", "source_as_of", "sample_size",
    ]
    rows = [
        (
            "sw:1111", "copilot_cli", "1111aaaa", "goal-newest", 0,
            "Build Session Work Summary", "OwnerOrg/SampleRepo", "feat/goal-newest", "done", "R1",
            "writer", "gpt-5.6-luna", "Implement L1-L5 work status pipeline",
            "2026-11-26T08:00:00Z", "2026-11-26T08:25:00Z",
            1500.0, 15, 64000, '["aidash-metrics", "team-lead"]',
            10, 2, 2, 1,
            5, 3, 355, '[{"script": "ci-monitor.py", "skill": "team-lead", "exit_code": 1, "duration_ms": 5200}]',
            1, 1, "aidash-metrics", "",
            5.0, 1, 1500.0,
            64000, 10, 2,
            2, 1, 5,
            3, 355, 1, 1,
            5.0, "2026-11-26T08:25:00Z", "2026-11-26", "2026-11-13",
            "2026-11-26", "14d", "2026-11-26", 2,
        ),
        (
            "sw:2222", "copilot_cli", "2222bbbb", "unassigned-daily", 1,
            "日常独立会话（未绑定独立 Goal）", "OwnerOrg/SampleRepo", "main", "daily", None,
            "explorer", "gemini-3.8-flash", "Inspect schema layout",
            "2026-11-25T05:00:00Z", "2026-11-25T05:04:00Z",
            240.0, 3, 7500, "[]",
            3, 0, 0, 0,
            0, 0, None, "[]",
            0, 0, None, None,
            None, 1, 240.0,
            7500, 3, 0,
            0, 0, 0,
            0, None, 0, 0,
            None, "2026-11-25T05:04:00Z", "2026-11-25", "2026-11-13",
            "2026-11-26", "14d", "2026-11-26", 2,
        ),
    ]

    out_path = tmp_path / "work-status.json"
    icloud_dir = tmp_path / "icloud"
    payload = wss.write_snapshot(
        out_path,
        until_day="2026-11-26",
        warehouse_db=warehouse,
        query_runner=lambda _name, _params=None: (rows, cols),
        icloud_sync_dir=icloud_dir,
    )

    assert out_path.is_file()
    assert (icloud_dir / "jobs" / "aidata-digest" / "work-status.json").is_file()
    assert payload["contract"] == "aidash-work-status/v1"
    assert payload["schema_version"] == 1
    assert payload["coverage_status"] == "healthy"
    assert payload["sample_size"] == 2
    assert payload["window_cst"] == "14d"
    assert payload["source_as_of"] == "2026-11-26"

    pulse = payload["pulse"]
    assert pulse["goals_count"] == 1
    assert pulse["buckets_count"] == 2
    assert pulse["sessions_count"] == 2
    assert pulse["duration_sec"] == 1740.0
    assert pulse["total_tokens"] == 71500
    assert pulse["files_changed_count"] == 5
    assert pulse["commits_count"] == 3
    assert pulse["prs_touched_count"] == 1

    goals = payload["goals"]
    assert [g["goal_id"] for g in goals] == ["goal-newest", "unassigned-daily"]

    g_top = goals[0]
    assert g_top["title"] == "Build Session Work Summary"
    assert g_top["is_unassigned_bucket"] is False
    assert g_top["review_round_badge"] == "R1"
    assert g_top["outputs"] == {
        "files_changed_count": 5,
        "commits_count": 3,
        "pr_number": 355,
        "session_count": 1,
    }
    split = g_top["action_split"]
    assert split["search_read_calls"] == 10
    assert split["code_edit_calls"] == 2
    assert split["verify_script_calls"] == 2
    assert split["spin_rework_calls"] == 1
    assert round(
        split["search_read_pct"] + split["code_edit_pct"] + split["verify_script_pct"] + split["spin_rework_pct"],
        1,
    ) == 100.0

    sk_map = {s["skill"]: s for s in g_top["skills_used"]}
    assert sk_map["aidash-metrics"]["used_reference"] is True
    assert sk_map["aidash-metrics"]["empty_load"] is False
    assert sk_map["team-lead"]["empty_load"] is True

    sig_kinds = {sig["kind"] for sig in g_top["ai_signals"]}
    assert {"empty_skill_load", "high_search_to_edit", "script_or_rework_friction", "retro_handoff"} <= sig_kinds
    for sig in g_top["ai_signals"]:
        _assert_plain_language_labels(sig["label_zh"])
        _assert_plain_language_labels(sig["label_en"])

    for sess in g_top["sessions"]:
        assert len(sess["session_id_short"]) == 8
        _assert_plain_language_labels(sess["role_label_zh"])
        _assert_plain_language_labels(sess["role_label_en"])
        assert "prompt" not in sess
        assert "transcript" not in sess

    g_unassigned = goals[1]
    assert g_unassigned["goal_id"] == "unassigned-daily"
    assert g_unassigned["title"] == "日常独立会话（未绑定独立 Goal）"
    assert g_unassigned["is_unassigned_bucket"] is True
    assert g_unassigned["outputs"]["session_count"] == 1


def test_work_status_snapshot_reports_missing_and_unknown_honestly(tmp_path):
    # 1. Missing table / query failure -> coverage_status == "missing"
    def failing_runner(_name: str, _params: dict | None = None):
        raise sqlite3.OperationalError("no such table: fact_session_work_summary")

    out_missing = tmp_path / "missing-work-status.json"
    missing_payload = wss.write_snapshot(out_missing, query_runner=failing_runner)
    assert missing_payload["coverage_status"] == "missing"
    assert missing_payload["sample_size"] == 0
    assert missing_payload["goals"] == []

    # 2. Empty table (table present, 0 rows in window) -> coverage_status == "unknown"
    empty_payload = wss.build_work_status_snapshot([], table_present=True)
    assert empty_payload["coverage_status"] == "unknown"
    assert empty_payload["sample_size"] == 0
    assert empty_payload["goals"] == []
    assert empty_payload["time_series"] == []
    assert empty_payload["skill_version_cohorts"] == []
    assert empty_payload["repo_delivered_groups"] == []
    assert empty_payload["trend_summary"]["first_pass_rate_pct"] is None
    assert empty_payload["trend_summary"]["median_goal_duration_sec"] is None
    assert json.loads(out_missing.read_text(encoding="utf-8"))["contract"] == "aidash-work-status/v1"


def test_work_status_snapshot_v2_cohorts_time_series_repo_groups_focus_and_role_relay():
    stream_rows = [
        # Pre-upgrade legacy goal on day 2026-11-20 (R2 rework, team-lead v18)
        {
            "session_uid": "sw:pre1",
            "source": "copilot_cli",
            "session_id_short": "aaaa1111",
            "goal_id": "goal-legacy-v18",
            "is_unassigned_bucket": 0,
            "goal_title": "Legacy Team Lead Handoff",
            "repo_name": "OwnerOrg/SampleRepo",
            "branch_name": "feat/goal-legacy-v18",
            "goal_status": "done",
            "review_round_badge": "R2",
            "role_key": "m1",
            "model_id": "gpt-6.1-sol",
            "summary_label": "Coordinate legacy task slices",
            "started_at": "2026-11-20T02:00:00Z",
            "ended_at": "2026-11-20T02:15:00Z",
            "duration_sec": 900.0,
            "turn_count": 8,
            "total_tokens": 25000,
            "skills_json": '["team-lead"]',
            "search_read_calls": 4,
            "code_edit_calls": 2,
            "verify_script_calls": 2,
            "spin_rework_calls": 2,
            "files_changed_count": 3,
            "commits_count": 2,
            "pr_number": 301,
            "slow_or_failed_scripts_json": "[]",
            "ref_hit_count": 1,
            "script_call_count": 1,
            "ref_skills_csv": "team-lead",
            "script_skills_csv": "team-lead",
            "cst_day": "2026-11-20",
            "goal_latest_day": "2026-11-20",
            "window_start": "2026-11-14",
            "window_end": "2026-11-27",
            "window_cst": "14d",
            "source_as_of": "2026-11-27",
            "sample_size": 6,
        },
        # Post-upgrade clean steady goal 1 on day 2026-11-25 (R1 pass, team-lead v19 + my-designer v12)
        {
            "session_uid": "sw:post1-m1",
            "source": "copilot_cli",
            "session_id_short": "bbbb2221",
            "goal_id": "goal-steady-1",
            "is_unassigned_bucket": 0,
            "goal_title": "Steady Goal One",
            "repo_name": "OwnerOrg/SampleRepo",
            "branch_name": "feat/goal-steady-1",
            "goal_status": "merged",
            "review_round_badge": "R1",
            "role_key": "m1",
            "model_id": "gpt-6.1-sol",
            "summary_label": "Freeze spec and dispatch writer",
            "started_at": "2026-11-25T01:00:00Z",
            "ended_at": "2026-11-25T01:05:00Z",
            "duration_sec": 300.0,
            "turn_count": 4,
            "total_tokens": 12000,
            "skills_json": '["team-lead", "my-designer"]',
            "search_read_calls": 3,
            "code_edit_calls": 1,
            "verify_script_calls": 1,
            "spin_rework_calls": 0,
            "files_changed_count": 1,
            "commits_count": 1,
            "pr_number": 310,
            "slow_or_failed_scripts_json": "[]",
            "ref_hit_count": 2,
            "script_call_count": 2,
            "ref_skills_csv": "team-lead,my-designer",
            "script_skills_csv": "team-lead,my-designer",
            "cst_day": "2026-11-25",
            "goal_latest_day": "2026-11-25",
            "window_start": "2026-11-14",
            "window_end": "2026-11-27",
            "window_cst": "14d",
            "source_as_of": "2026-11-27",
            "sample_size": 6,
        },
        {
            "session_uid": "sw:post1-wr",
            "source": "copilot_cli",
            "session_id_short": "bbbb2222",
            "goal_id": "goal-steady-1",
            "is_unassigned_bucket": 0,
            "goal_title": "Steady Goal One",
            "repo_name": "OwnerOrg/SampleRepo",
            "branch_name": "feat/goal-steady-1",
            "goal_status": "merged",
            "review_round_badge": "R1",
            "role_key": "writer",
            "model_id": "gpt-5.6-luna",
            "summary_label": "Implement workbench UI slice",
            "started_at": "2026-11-25T01:10:00Z",
            "ended_at": "2026-11-25T01:25:00Z",
            "duration_sec": 900.0,
            "turn_count": 10,
            "total_tokens": 30000,
            "skills_json": '["my-designer"]',
            "search_read_calls": 4,
            "code_edit_calls": 4,
            "verify_script_calls": 2,
            "spin_rework_calls": 0,
            "files_changed_count": 4,
            "commits_count": 2,
            "pr_number": 310,
            "slow_or_failed_scripts_json": "[]",
            "ref_hit_count": 1,
            "script_call_count": 1,
            "ref_skills_csv": "my-designer",
            "script_skills_csv": "my-designer",
            "cst_day": "2026-11-25",
            "goal_latest_day": "2026-11-25",
            "window_start": "2026-11-14",
            "window_end": "2026-11-27",
            "window_cst": "14d",
            "source_as_of": "2026-11-27",
            "sample_size": 6,
        },
        # Post-upgrade collision goal on day 2026-11-26 (post_fix=1 recurrence on team-lead v19)
        {
            "session_uid": "sw:post2-col",
            "source": "copilot_cli",
            "session_id_short": "cccc3333",
            "goal_id": "goal-postfix-collision",
            "is_unassigned_bucket": 0,
            "goal_title": "Post-Upgrade Recurrence Goal",
            "repo_name": "OwnerOrg/SkillsRepo",
            "branch_name": "feat/goal-postfix-collision",
            "goal_status": "done",
            "review_round_badge": "R2",
            "role_key": "writer",
            "model_id": "gpt-5.6-luna",
            "summary_label": "Retry gate check",
            "started_at": "2026-11-26T04:00:00Z",
            "ended_at": "2026-11-26T04:20:00Z",
            "duration_sec": 1200.0,
            "turn_count": 9,
            "total_tokens": 28000,
            "skills_json": '["team-lead"]',
            "search_read_calls": 5,
            "code_edit_calls": 3,
            "verify_script_calls": 1,
            "spin_rework_calls": 1,
            "files_changed_count": 2,
            "commits_count": 1,
            "pr_number": 312,
            "slow_or_failed_scripts_json": "[]",
            "ref_hit_count": 1,
            "script_call_count": 1,
            "ref_skills_csv": "team-lead",
            "script_skills_csv": "team-lead",
            "cst_day": "2026-11-26",
            "goal_latest_day": "2026-11-26",
            "window_start": "2026-11-14",
            "window_end": "2026-11-27",
            "window_cst": "14d",
            "source_as_of": "2026-11-27",
            "sample_size": 6,
        },
        # Active in-flight goal on day 2026-11-27 (no review_round_badge yet -> honest None for day first_pass_rate)
        {
            "session_uid": "sw:active1",
            "source": "copilot_cli",
            "session_id_short": "dddd4444",
            "goal_id": "goal-active-now",
            "is_unassigned_bucket": 0,
            "goal_title": "In-Flight Telemetry Goal",
            "repo_name": "OwnerOrg/SampleRepo",
            "branch_name": "feat/goal-active-now",
            "goal_status": "in_progress",
            "review_round_badge": None,
            "role_key": "reviewer",
            "model_id": "gpt-6.1-sol",
            "summary_label": "Running review checks",
            "started_at": "2026-11-27T02:00:00Z",
            "ended_at": "2026-11-27T02:08:00Z",
            "duration_sec": 480.0,
            "turn_count": 4,
            "total_tokens": 11000,
            "skills_json": '["team-lead"]',
            "search_read_calls": 3,
            "code_edit_calls": 0,
            "verify_script_calls": 1,
            "spin_rework_calls": 0,
            "files_changed_count": 0,
            "commits_count": 0,
            "pr_number": None,
            "slow_or_failed_scripts_json": "[]",
            "ref_hit_count": 1,
            "script_call_count": 1,
            "ref_skills_csv": "team-lead",
            "script_skills_csv": "team-lead",
            "cst_day": "2026-11-27",
            "goal_latest_day": "2026-11-27",
            "window_start": "2026-11-14",
            "window_end": "2026-11-27",
            "window_cst": "14d",
            "source_as_of": "2026-11-27",
            "sample_size": 6,
        },
        # Unassigned daily session
        {
            "session_uid": "sw:daily1",
            "source": "copilot_cli",
            "session_id_short": "eeee5555",
            "goal_id": "unassigned-daily",
            "is_unassigned_bucket": 1,
            "goal_title": "日常独立会话（未绑定独立 Goal）",
            "repo_name": "OwnerOrg/SampleRepo",
            "branch_name": "main",
            "goal_status": "daily",
            "review_round_badge": None,
            "role_key": "explorer",
            "model_id": "gemini-3.8-flash",
            "summary_label": "Quick lookup",
            "started_at": "2026-11-27T01:00:00Z",
            "ended_at": "2026-11-27T01:03:00Z",
            "duration_sec": 180.0,
            "turn_count": 2,
            "total_tokens": 4000,
            "skills_json": "[]",
            "search_read_calls": 2,
            "code_edit_calls": 0,
            "verify_script_calls": 0,
            "spin_rework_calls": 0,
            "files_changed_count": 0,
            "commits_count": 0,
            "pr_number": None,
            "slow_or_failed_scripts_json": "[]",
            "ref_hit_count": 0,
            "script_call_count": 0,
            "ref_skills_csv": None,
            "script_skills_csv": None,
            "cst_day": "2026-11-27",
            "goal_latest_day": "2026-11-27",
            "window_start": "2026-11-14",
            "window_end": "2026-11-27",
            "window_cst": "14d",
            "source_as_of": "2026-11-27",
            "sample_size": 6,
        },
    ]

    watermarks = [
        {"goal_id": "goal-legacy-v18", "skill": "team-lead", "skill_version": "v18@0000111", "is_post_fix": 0, "occurrence_count": 2},
        {"goal_id": "goal-postfix-collision", "skill": "team-lead", "skill_version": "v19@1a2b3c4", "is_post_fix": 1, "occurrence_count": 1},
        {"goal_id": "goal-steady-1", "skill": "my-designer", "skill_version": "v12@abcd999", "is_post_fix": 0, "occurrence_count": 0},
    ]

    snap = wss.build_work_status_snapshot(
        stream_rows,
        goal_retro_findings={"goal-postfix-collision": {"handoff": 1}},
        skill_version_watermarks=watermarks,
        table_present=True,
    )

    by_gid = {g["goal_id"]: g for g in snap["goals"]}
    assert by_gid["goal-active-now"]["focus_bucket"] == "active_or_blocked"
    assert by_gid["goal-active-now"]["is_focus_anomaly"] is True
    assert by_gid["goal-postfix-collision"]["focus_bucket"] == "post_fix_collision"
    assert by_gid["goal-postfix-collision"]["is_focus_anomaly"] is True
    assert by_gid["goal-legacy-v18"]["focus_bucket"] == "post_fix_collision"
    assert by_gid["goal-steady-1"]["focus_bucket"] == "steady_delivered"
    assert by_gid["goal-steady-1"]["is_focus_anomaly"] is False
    assert by_gid["unassigned-daily"]["focus_bucket"] == "unassigned_daily"
    assert by_gid["unassigned-daily"]["is_focus_anomaly"] is False

    # Role relay ordered m1 -> writer with exact duration & share_pct == 100%
    steady_relay = by_gid["goal-steady-1"]["role_relay"]
    assert [r["role_key"] for r in steady_relay] == ["m1", "writer"]
    assert [r["duration_sec"] for r in steady_relay] == [300.0, 900.0]
    assert [r["share_pct"] for r in steady_relay] == [25.0, 75.0]
    for r in steady_relay:
        _assert_plain_language_labels(r["role_label_zh"])
        _assert_plain_language_labels(r["role_label_en"])

    # Skill watermarks distinguish post_fix_recurring vs pre_fix_legacy vs post_fix_clean
    col_wm = {w["skill"]: w for w in by_gid["goal-postfix-collision"]["skill_watermarks"]}
    assert col_wm["team-lead"]["version_label"] == "v19"
    assert col_wm["team-lead"]["watermark_state"] == "post_fix_recurring"
    _assert_plain_language_labels(col_wm["team-lead"]["summary_zh"])
    _assert_plain_language_labels(col_wm["team-lead"]["label_zh"])

    leg_wm = {w["skill"]: w for w in by_gid["goal-legacy-v18"]["skill_watermarks"]}
    assert leg_wm["team-lead"]["version_label"] == "v18"
    assert leg_wm["team-lead"]["watermark_state"] == "pre_fix_legacy"

    steady_wm = {w["skill"]: w for w in by_gid["goal-steady-1"]["skill_watermarks"]}
    assert steady_wm["team-lead"]["version_label"] == "v19"
    assert steady_wm["team-lead"]["watermark_state"] == "post_fix_clean"

    # Skill version cohort v18 -> v19
    cohorts = {c["skill"]: c for c in snap["skill_version_cohorts"]}
    tl_cohort = cohorts["team-lead"]
    assert tl_cohort["cohort_id"] == "team-lead:v18->v19"
    assert tl_cohort["previous_version"] == "v18"
    assert tl_cohort["current_version"] == "v19"
    assert tl_cohort["watermark_sha"] == "1a2b3c4"
    assert tl_cohort["before_goal_ids"] == ["goal-legacy-v18"]
    assert set(tl_cohort["after_goal_ids"]) == {"goal-steady-1", "goal-postfix-collision", "goal-active-now"}
    assert tl_cohort["before_first_pass_pct"] == 0.0
    assert tl_cohort["after_first_pass_pct"] == 50.0
    assert tl_cohort["first_pass_delta_pct"] == 50.0
    assert tl_cohort["post_fix_recurrence_count"] == 1
    assert tl_cohort["rework_delta_pct"] < 0.0

    # Repo delivered groups fold only steady_delivered goals
    repo_groups = snap["repo_delivered_groups"]
    assert len(repo_groups) == 1
    assert repo_groups[0]["repo"] == "SampleRepo"
    assert repo_groups[0]["goals_count"] == 1
    assert repo_groups[0]["prs_count"] == 1
    assert repo_groups[0]["first_pass_rate_pct"] == 100.0
    assert repo_groups[0]["goal_ids"] == ["goal-steady-1"]

    # Time series preserves honest None when day has 0 evaluated review badges (2026-11-27)
    ts_by_day = {pt["day"]: pt for pt in snap["time_series"]}
    assert ts_by_day["2026-11-20"]["first_pass_rate"] == 0.0
    assert ts_by_day["2026-11-25"]["first_pass_rate"] == 100.0
    assert ts_by_day["2026-11-27"]["first_pass_rate"] is None

    trend = snap["trend_summary"]
    assert trend["first_pass_rate_pct"] == 33.3
    assert trend["first_pass_delta_pct"] is not None
    assert trend["spin_rework_delta_pct"] < 0.0
