import sqlite3
from pathlib import Path

import pytest
from adapters import gtt_ledger, gtt_receipt, workspace_hygiene


@pytest.mark.unit
def test_gtt_ledger_normalizes_events_with_line_based_uid(monkeypatch):
    raw = [{
        "machine_id": "mac-mini",
        "goal_id": "demo",
        "record_type": "ledger",
        "content": (
            "# Goal: demo\n"
            "| task | status |\n"
            "| tk1 | done |\n"
            "- 2026-10-28T01:00:00+08:00 | EVT=DONE | id=E1 task=tk1 "
            "ref=PR#12 note=finished\n"
        ),
    }]
    captured = {}
    monkeypatch.setattr(gtt_ledger, "read_raw", lambda _source: raw)

    def capture(source, table, ddl, rows, columns):
        captured[table] = (rows, columns)
        return len(rows)

    monkeypatch.setattr(gtt_ledger, "write_clean", capture)
    assert gtt_ledger.normalize() == 1
    assert captured["gtt_event"][0][0]["event_uid"] == "mac-mini:demo:L4:E1"
    assert captured["gtt_event"][0][0]["pr_number"] == 12


@pytest.mark.unit
def test_gtt_receipt_accepts_bundle_style_record(monkeypatch):
    raw = [{
        "machine_id": "macbook",
        "goal_id": "demo",
        "record_type": "receipt",
        "rel_path": "demo/receipts/tk1-writer-r1.md",
        "content": "Status: completed\nModel: gpt-5.6-luna\nTimestamp: 2026-10-28T01:00:00+08:00\n",
    }]
    captured = {}
    monkeypatch.setattr(gtt_receipt, "read_raw", lambda _source: raw)
    monkeypatch.setattr(gtt_receipt, "_profiles", list)

    def capture(source, table, ddl, rows, columns):
        captured[table] = rows
        return len(rows)

    monkeypatch.setattr(gtt_receipt, "write_clean", capture)
    assert gtt_receipt.normalize() == 1
    assert captured["task_run"][0]["goal_uid"] == "macbook:demo"
    assert captured["task_run"][0]["round_no"] == 1


@pytest.mark.unit
def test_workspace_hygiene_f01_guard():
    assert workspace_hygiene._safe_to_reclaim("worktree", 0, 1, 0, 0) == (1, None)
    assert workspace_hygiene._safe_to_reclaim("worktree", 2, 1, 0, 0)[0] == 0
    assert workspace_hygiene._safe_to_reclaim("worktree", 0, 0, 0, 0)[0] == 0
    assert workspace_hygiene._safe_to_reclaim("worktree", 0, 1, 1, 0)[0] == 0
    assert workspace_hygiene._safe_to_reclaim("worktree", 0, 1, 0, 1)[0] == 0
    assert workspace_hygiene._safe_to_reclaim("repo", 0, 1, 0, 0)[0] == 0


@pytest.mark.unit
def test_run_merge_wires_p0_tables(tmp_path, monkeypatch):
    import config
    import merge

    warehouse = tmp_path / "warehouse.db"
    clean = tmp_path / "clean"
    clean.mkdir()
    monkeypatch.setattr(config, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(config, "CLEAN_DIR", clean)
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "SCHEMA_DIR", Path(config.SCHEMA_DIR))
    for source, ddl, table, row in (
        ("gtt_ledger", "CREATE TABLE goal (goal_uid TEXT, machine_id TEXT, goal_id TEXT, title TEXT, owner TEXT, coordinator_bot TEXT, tl_agent TEXT, tl_model TEXT, contract_sha TEXT, static_header_status TEXT, derived_actual_status TEXT, is_status_drifted INTEGER, task_total_count INTEGER, task_done_count INTEGER, task_blocked_count INTEGER, created_at TEXT, last_event_at TEXT, ledger_sha256 TEXT)", "goal", ("m:g", "m", "g", None, None, None, None, None, None, "unknown", "in_progress", 1, 0, 0, 0, None, None, "x")),
        ("gtt_ledger", "CREATE TABLE gtt_event (event_uid TEXT, goal_uid TEXT, machine_id TEXT, goal_id TEXT, line_no INTEGER, event_id TEXT, ts TEXT, evt_type TEXT, task_id TEXT, actor_from TEXT, actor_to TEXT, ref_artifact TEXT, head_sha TEXT, pr_number INTEGER, model_id TEXT, contract_sha TEXT, is_bot_bypass INTEGER, blocker_class TEXT, note_preview TEXT)", "gtt_event", ("m:L1:none", "m:g", "m", "g", 1, "none", "2026-01-01", "READY", None, None, None, None, None, None, None, None, 0, None, None)),
        ("gtt_receipt", "CREATE TABLE model_role (role_model_key TEXT, role_name TEXT, tier TEXT, cli_tool TEXT, model_id TEXT, vendor TEXT, is_escalated INTEGER)", "model_role", ("r", "writer", "standard", "copilot", "gpt", "openai", 0)),
        ("gtt_receipt", "CREATE TABLE task_run (receipt_uid TEXT, goal_uid TEXT, machine_id TEXT, goal_id TEXT, task_id TEXT, role_name TEXT, round_no INTEGER, agent_name TEXT, cli_tool TEXT, model_id TEXT, vendor TEXT, status TEXT, v5_verdict TEXT, head_sha TEXT, receipt_sha256 TEXT, completed_at TEXT)", "task_run", ("r", "m:g", "m", "g", "t", "writer", 1, None, "copilot", "gpt", None, "completed", None, None, "x", None)),
        ("workspace_hygiene", "CREATE TABLE hygiene_snapshot (snapshot_date TEXT, machine_id TEXT, entity_type TEXT, canonical_path TEXT, repo_key TEXT, goal_id TEXT, branch_name TEXT, head_sha TEXT, is_dirty INTEGER, dirty_count INTEGER, is_merged_to_default INTEGER, has_active_pane INTEGER, has_implicit_dep INTEGER, safe_to_reclaim INTEGER, reclaim_block_reason TEXT)", "hygiene_snapshot", ("2026-01-01", "m", "worktree", "/tmp/w", "local:w", None, "main", "h", 0, 0, 1, 0, 0, 1, None)),
    ):
        db = clean / f"{source}.db"
        conn = sqlite3.connect(db)
        conn.execute(ddl)
        conn.execute(f"INSERT INTO {table} VALUES ({','.join('?' for _ in row)})", row)
        conn.commit()
        conn.close()
    counts = merge.run_merge()
    assert counts["dim_goal"] == 1
    assert counts["fact_gtt_task_run"] == 1
    assert counts["fact_workspace_hygiene_snapshot"] == 1
