from __future__ import annotations

import json
import re
import sqlite3

from L5_apps.digest import work_status_snapshot as wss

_BANNED_LABEL_PATTERNS = (
    re.compile(r"\bS(?:[1-9]|1[0-2])\b"),
    re.compile(r"\bM[1-5]\b"),
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
    assert json.loads(out_missing.read_text(encoding="utf-8"))["contract"] == "aidash-work-status/v1"
