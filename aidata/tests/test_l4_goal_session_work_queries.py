from __future__ import annotations

import sqlite3

import merge
import serve
from adapters.session_work import normalize_records


def _build_fixture_warehouse(tmp_path, monkeypatch):
    clean_dir = tmp_path / "clean"
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)

    normalize_records(
        [
            {
                "source": "copilot_cli",
                "session_id": "1111aaaa-0000-0000-0000-000000000001",
                "goal_id": "goal-alpha",
                "repo_name": "OwnerOrg/SampleRepo",
                "branch_name": "feat/goal-alpha",
                "role_key": "m1",
                "model_id": "gpt-6.1-sol",
                "summary_label": "Plan Goal goal-alpha contract",
                "started_at": "2026-11-24T02:00:00Z",
                "ended_at": "2026-11-24T02:10:00Z",
                "duration_sec": 600.0,
                "turn_count": 6,
                "total_tokens": 18000,
                "skills": ["team-lead", "aidash-metrics"],
                "search_read_calls": 4,
                "code_edit_calls": 1,
                "verify_script_calls": 1,
                "spin_rework_calls": 0,
                "files_changed_count": 1,
                "commits_count": 1,
            },
            {
                "source": "copilot_cli",
                "session_id": "2222bbbb-0000-0000-0000-000000000002",
                "goal_id": "goal-alpha",
                "repo_name": "OwnerOrg/SampleRepo",
                "branch_name": "feat/goal-alpha",
                "role_key": "writer",
                "model_id": "gpt-5.6-luna",
                "summary_label": "Implement L1-L5 slices and open PR",
                "started_at": "2026-11-24T03:00:00Z",
                "ended_at": "2026-11-24T03:30:00Z",
                "duration_sec": 1800.0,
                "turn_count": 14,
                "total_tokens": 52000,
                "skills": ["aidash-metrics"],
                "search_read_calls": 5,
                "code_edit_calls": 5,
                "verify_script_calls": 3,
                "spin_rework_calls": 1,
                "files_changed_count": 6,
                "commits_count": 4,
                "pr_number": 351,
            },
            {
                "source": "copilot_cli",
                "session_id": "3333cccc-0000-0000-0000-000000000003",
                "repo_name": "OwnerOrg/SampleRepo",
                "branch_name": "main",
                "role_key": "explorer",
                "model_id": "gemini-3.8-flash",
                "summary_label": "Quick ad-hoc repo lookup",
                "started_at": "2026-11-24T01:00:00Z",
                "ended_at": "2026-11-24T01:04:00Z",
                "duration_sec": 240.0,
                "turn_count": 3,
                "total_tokens": 6000,
                "skills": [],
                "search_read_calls": 3,
                "code_edit_calls": 0,
                "verify_script_calls": 0,
                "spin_rework_calls": 0,
                "files_changed_count": 0,
                "commits_count": 0,
            },
            {
                "source": "copilot_cli",
                "session_id": "9999zzzz-0000-0000-0000-000000000099",
                "goal_id": "goal-stale",
                "repo_name": "OwnerOrg/SampleRepo",
                "role_key": "writer",
                # Outside 14d CST window ending 2026-11-24
                "started_at": "2026-10-10T01:00:00Z",
                "ended_at": "2026-10-10T01:10:00Z",
                "duration_sec": 600.0,
                "turn_count": 4,
                "total_tokens": 9000,
            },
        ],
        db_path=clean_dir / "session_work.db",
    )
    merge.run_merge()

    with sqlite3.connect(warehouse) as conn:
        conn.execute(
            "INSERT INTO dim_goal (goal_uid, machine_id, goal_id, title, derived_actual_status, last_event_at) "
            "VALUES ('mac:goal-alpha', 'mac', 'goal-alpha', 'Session Work Summary Workbench', 'done', '2026-11-24T04:00:00Z')"
        )
        conn.executemany(
            "INSERT INTO fact_gtt_task_run (receipt_uid, goal_uid, machine_id, goal_id, task_id, role_name, round_no, status, v5_verdict, receipt_sha256) "
            "VALUES (?, 'mac:goal-alpha', 'mac', 'goal-alpha', 'T1', ?, ?, ?, ?, ?)",
            [
                ("r1", "reviewer", 1, "completed", "FAIL", "sha-r1"),
                ("r2", "reviewer", 2, "completed", "PASS", "sha-r2"),
            ],
        )
        conn.execute(
            "INSERT INTO reference_hits (hit_uid, source, session_id, skill, reference_path, byte_len, ts) "
            "VALUES ('rh1', 'copilot_cli', '1111aaaa-0000-0000-0000-000000000001', 'aidash-metrics', "
            "'skills/aidash-metrics/references/aidata-l1-l5-lineage.md', 4096, '2026-11-24T02:02:00Z')"
        )
        conn.execute(
            "INSERT INTO script_call (call_uid, source, session_id, skill, script_path, exit_code, duration_ms, ts) "
            "VALUES ('sc1', 'copilot_cli', '2222bbbb-0000-0000-0000-000000000002', 'aidash-metrics', "
            "'skills/aidash-metrics/scripts/inspect_aidata_pipeline.py', 0, 350, '2026-11-24T03:05:00Z')"
        )
        conn.commit()
    return warehouse


def test_l4_goal_session_work_stream_rolls_up_goals_rounds_touches_and_unassigned(tmp_path, monkeypatch):
    _build_fixture_warehouse(tmp_path, monkeypatch)
    rows, cols = serve.run_query("retro/goal_session_work_stream", {"until_day": "2026-11-24", "days": 14})
    items = [dict(zip(cols, row)) for row in rows]

    # 3 sessions inside 14d window; October stale row excluded
    assert len(items) == 3
    assert all(item["sample_size"] == 3 for item in items)
    assert all(item["source_as_of"] == "2026-11-24" for item in items)
    assert all(item["window_cst"] == "14d" for item in items)

    # Newest goal ('goal-alpha', latest ended_at 03:30Z) sorts ahead of unassigned-daily (01:04Z)
    assert [it["session_id_short"] for it in items] == ["2222bbbb", "1111aaaa", "3333cccc"]

    alpha_writer = items[0]
    assert alpha_writer["goal_id"] == "goal-alpha"
    assert alpha_writer["goal_title"] == "Session Work Summary Workbench"
    assert alpha_writer["goal_status"] == "done"
    assert alpha_writer["review_round_badge"] == "R2"
    assert alpha_writer["goal_session_count"] == 2
    assert alpha_writer["goal_duration_sec"] == 2400.0
    assert alpha_writer["goal_total_tokens"] == 70000
    assert alpha_writer["goal_search_read_calls"] == 9
    assert alpha_writer["goal_code_edit_calls"] == 6
    assert alpha_writer["goal_verify_script_calls"] == 4
    assert alpha_writer["goal_spin_rework_calls"] == 1
    assert alpha_writer["goal_files_changed_count"] == 7
    assert alpha_writer["goal_commits_count"] == 5
    assert alpha_writer["goal_pr_number"] == 351
    assert alpha_writer["goal_ref_hit_count"] == 1
    assert alpha_writer["goal_script_call_count"] == 1
    assert alpha_writer["goal_search_to_edit_ratio"] == 1.5
    assert alpha_writer["script_call_count"] == 1
    assert alpha_writer["script_skills_csv"] == "aidash-metrics"

    alpha_tl = items[1]
    assert alpha_tl["ref_hit_count"] == 1
    assert alpha_tl["ref_skills_csv"] == "aidash-metrics"

    unassigned = items[2]
    assert unassigned["goal_id"] == "unassigned-daily"
    assert unassigned["is_unassigned_bucket"] == 1
    assert unassigned["goal_title"] == "日常独立会话（未绑定独立 Goal）"
    assert unassigned["review_round_badge"] is None
    assert unassigned["session_search_to_edit_ratio"] is None
