from __future__ import annotations

import sqlite3

import merge
from adapters.agent_retro import normalize_records


def test_l3_agent_retro_merge_populates_findings_horizon_and_stored_cst_day(tmp_path, monkeypatch):
    clean_dir = tmp_path / "clean"
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")

    normalize_records(
        [
            {
                "kind": "retro_finding",
                "source": "copilot_cli",
                "session_id": "sess-utc-boundary",
                "goal_id": "goal-1",
                "role_key": "m1",
                "skill": "team-lead",
                "layer_key": "handoff",
                "finding_code": "H3_r10_receipt_gap_or_dirty_schema",
                "severity": "high",
                "skill_version": "v12@ab12cd3",
                "is_post_fix": 1,
                "occurrence_count": 2,
                # 18:30Z crosses midnight in CST (+8 hours -> 2026-11-25)
                "ts": "2026-11-24T18:30:00Z",
            },
            {
                "kind": "retro_finding",
                "source": "copilot_cli",
                "session_id": "sess-prefix",
                "goal_id": "goal-1",
                "role_key": "m2",
                "skill": "m2-dispatcher",
                "layer_key": "role",
                "finding_code": "R2_m2_direct_code_edit",
                "severity": "critical",
                "skill_version": "v4@9988776",
                "is_post_fix": 0,
                "occurrence_count": 3,
                "ts": "2026-11-24T04:00:00Z",
            },
            {
                "kind": "horizon_waste",
                "source": "copilot_cli",
                "session_id": "sess-utc-boundary",
                "role_key": "m1",
                "skill": "agent-retro",
                "horizon_code": "HZN1_context_carry_tax",
                "category_key": "context_carry",
                "wasted_turns": 8,
                "wasted_tokens": 24500,
                "duration_sec": 75.0,
                "ts": "2026-11-24T18:30:00Z",
            },
        ],
        db_path=clean_dir / "agent_retro.db",
    )

    counts = merge.run_merge()
    assert counts["fact_agent_retro_finding"] == 2
    assert counts["fact_agent_horizon_waste"] == 1

    with sqlite3.connect(warehouse) as conn:
        findings = conn.execute(
            "SELECT skill, layer_key, skill_version, is_post_fix, occurrence_count, cst_day "
            "FROM fact_agent_retro_finding ORDER BY is_post_fix DESC"
        ).fetchall()
        waste = conn.execute(
            "SELECT skill, role_key, category_key, wasted_turns, wasted_tokens, duration_sec, cst_day "
            "FROM fact_agent_horizon_waste"
        ).fetchall()
        xinfo_f = [r[1] for r in conn.execute("PRAGMA table_xinfo(fact_agent_retro_finding)")]
        xinfo_w = [r[1] for r in conn.execute("PRAGMA table_xinfo(fact_agent_horizon_waste)")]

    assert "cst_day" in xinfo_f
    assert "cst_day" in xinfo_w
    assert findings == [
        ("team-lead", "handoff", "v12@ab12cd3", 1, 2, "2026-11-25"),
        ("m2-dispatcher", "role", "v4@9988776", 0, 3, "2026-11-24"),
    ]
    assert waste == [
        ("agent-retro", "m1", "context_carry", 8, 24500, 75.0, "2026-11-25"),
    ]


def test_l3_agent_retro_merge_commits_before_detaching_and_handles_missing_clean_db(tmp_path, monkeypatch):
    clean_dir = tmp_path / "clean"
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")

    # 1. Missing clean/agent_retro.db degrades to 0 rows
    counts_empty = merge.run_merge()
    assert counts_empty["fact_agent_retro_finding"] == 0
    assert counts_empty["fact_agent_horizon_waste"] == 0

    # 2. Direct transactional connection commits cleanly before DETACH DATABASE
    normalize_records(
        [
            {
                "kind": "retro_finding",
                "source": "copilot_cli",
                "session_id": "s1",
                "role_key": "writer",
                "skill": "agent-retro",
                "layer_key": "exec",
                "finding_code": "E2_r3_plus_divergence",
                "severity": "high",
                "skill_version": "v3@1122334",
                "is_post_fix": 1,
                "occurrence_count": 1,
                "ts": "2026-11-25T02:00:00Z",
            }
        ],
        db_path=clean_dir / "agent_retro.db",
    )
    with sqlite3.connect(warehouse) as conn:
        conn.executescript((merge.SCHEMA_DIR / "warehouse.sql").read_text(encoding="utf-8"))
        conn.execute("INSERT OR REPLACE INTO dim_skill_registry VALUES ('agent-retro', 'test', 1, 'v1', NULL)")
        assert conn.in_transaction
        sub_counts = merge._merge_agent_retro_facts(conn)
    assert sub_counts["fact_agent_retro_finding"] == 1
    assert sub_counts["fact_agent_horizon_waste"] == 0
