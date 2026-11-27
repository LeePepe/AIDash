from __future__ import annotations

import json
import sqlite3

import merge
from adapters.session_work import normalize_records


def test_l3_session_work_merge_populates_fact_and_stored_cst_day(tmp_path, monkeypatch):
    clean_dir = tmp_path / "clean"
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")

    normalize_records(
        [
            {
                "source": "copilot_cli",
                "session_id": "aaaa1111-bbbb-cccc-dddd-eeeeffff0001",
                "goal_id": "goal-alpha",
                "repo_name": "OwnerOrg/SampleRepo",
                "branch_name": "feat/goal-alpha",
                "role_key": "writer",
                "model_id": "gpt-5.6-luna",
                "summary_label": "Build session work summary L3 merge",
                "started_at": "2026-11-24T18:10:00Z",
                # 18:30Z crosses midnight in CST (+8 hours -> 2026-11-25)
                "ended_at": "2026-11-24T18:30:00Z",
                "duration_sec": 1200.0,
                "turn_count": 10,
                "total_tokens": 36000,
                "skills": ["aidash-metrics", "team-lead"],
                "search_read_calls": 4,
                "code_edit_calls": 3,
                "verify_script_calls": 2,
                "spin_rework_calls": 1,
                "files_changed_count": 3,
                "commits_count": 1,
                "pr_number": 348,
                "slow_or_failed_scripts": [{"script": "ci-monitor.py", "skill": "team-lead", "exit_code": 1, "duration_ms": 5100}],
            },
            {
                "source": "copilot_cli",
                "session_id": "bbbb2222-bbbb-cccc-dddd-eeeeffff0002",
                "repo_name": "OwnerOrg/SampleRepo",
                "branch_name": "main",
                "role_key": "explorer",
                "model_id": "gemini-3.8-flash",
                "summary_label": "Standalone exploration",
                "started_at": "2026-11-24T04:00:00Z",
                "ended_at": "2026-11-24T04:05:00Z",
                "duration_sec": 300.0,
                "turn_count": 3,
                "total_tokens": 8000,
                "skills": [],
                "search_read_calls": 3,
                "code_edit_calls": 0,
                "verify_script_calls": 0,
                "spin_rework_calls": 0,
                "files_changed_count": 0,
                "commits_count": 0,
            },
        ],
        db_path=clean_dir / "session_work.db",
    )

    counts = merge.run_merge()
    assert counts["fact_session_work_summary"] == 2

    with sqlite3.connect(warehouse) as conn:
        xinfo = [r[1] for r in conn.execute("PRAGMA table_xinfo(fact_session_work_summary)")]
        rows = conn.execute(
            "SELECT session_id_short, goal_id, role_key, duration_sec, search_read_calls, "
            "code_edit_calls, verify_script_calls, spin_rework_calls, files_changed_count, "
            "commits_count, pr_number, skills_json, cst_day "
            "FROM fact_session_work_summary ORDER BY cst_day DESC, session_id_short ASC"
        ).fetchall()

    assert "cst_day" in xinfo
    assert rows[0][:11] == (
        "aaaa1111", "goal-alpha", "writer", 1200.0, 4, 3, 2, 1, 3, 1, 348,
    )
    assert json.loads(rows[0][11]) == ["aidash-metrics", "team-lead"]
    assert rows[0][12] == "2026-11-25"

    assert rows[1][:11] == (
        "bbbb2222", None, "explorer", 300.0, 3, 0, 0, 0, 0, 0, None,
    )
    assert rows[1][12] == "2026-11-24"


def test_l3_session_work_merge_commits_before_detaching_and_handles_missing_clean_db(tmp_path, monkeypatch):
    clean_dir = tmp_path / "clean"
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")

    # 1. Missing clean/session_work.db degrades to 0 rows
    counts_empty = merge.run_merge()
    assert counts_empty["fact_session_work_summary"] == 0

    # 2. Direct transactional connection commits cleanly before DETACH DATABASE
    normalize_records(
        [
            {
                "source": "copilot_cli",
                "session_id": "cccc3333-0000-1111-2222-333344445555",
                "goal_id": "goal-gamma",
                "role_key": "m1",
                "started_at": "2026-11-25T02:00:00Z",
                "ended_at": "2026-11-25T02:10:00Z",
                "turn_count": 4,
                "total_tokens": 12000,
            }
        ],
        db_path=clean_dir / "session_work.db",
    )
    with sqlite3.connect(warehouse) as conn:
        conn.executescript((merge.SCHEMA_DIR / "warehouse.sql").read_text(encoding="utf-8"))
        conn.execute("INSERT OR REPLACE INTO dim_skill_registry VALUES ('team-lead', 'test', 1, 'v1', NULL)")
        assert conn.in_transaction
        sub_counts = merge._merge_session_work_facts(conn)
    assert sub_counts["fact_session_work_summary"] == 1
