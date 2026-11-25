from __future__ import annotations

import sqlite3

import merge
import serve
from adapters.agent_retro import normalize_records


def _build_fixture_warehouse(tmp_path, monkeypatch):
    clean_dir = tmp_path / "clean"
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)

    normalize_records(
        [
            {
                "kind": "retro_finding",
                "source": "copilot_cli",
                "session_id": "sess-1",
                "goal_id": "g1",
                "role_key": "m2",
                "skill": "m2-dispatcher",
                "layer_key": "role",
                "finding_code": "R2_m2_direct_code_edit",
                "severity": "critical",
                "skill_version": "v4@1111aaa",
                "is_post_fix": 0,
                "occurrence_count": 4,
                "ts": "2026-11-22T10:00:00+08:00",
            },
            {
                "kind": "retro_finding",
                "source": "copilot_cli",
                "session_id": "sess-2",
                "goal_id": "g2",
                "role_key": "m2",
                "skill": "m2-dispatcher",
                "layer_key": "role",
                "finding_code": "R2_m2_direct_code_edit",
                "severity": "critical",
                "skill_version": "v5@2222bbb",
                "is_post_fix": 1,
                "occurrence_count": 1,
                "ts": "2026-11-24T12:00:00+08:00",
            },
            {
                "kind": "retro_finding",
                "source": "copilot_cli",
                "session_id": "sess-3",
                "goal_id": "g3",
                "role_key": "explorer",
                "skill": "agent-retro",
                "layer_key": "invoke",
                "finding_code": "I3_l2_exit2_and_output_bloat",
                "severity": "high",
                "skill_version": "v9@3333ccc",
                "is_post_fix": 1,
                "occurrence_count": 2,
                "ts": "2026-11-24T15:00:00+08:00",
            },
            {
                "kind": "retro_finding",
                "source": "copilot_cli",
                "session_id": "sess-old",
                "goal_id": "g0",
                "role_key": "m1",
                "skill": "team-lead",
                "layer_key": "handoff",
                "finding_code": "H3_r10_receipt_gap_or_dirty_schema",
                "severity": "high",
                "skill_version": "v1@0000aaa",
                "is_post_fix": 0,
                "occurrence_count": 9,
                # Outside 14d rolling window ending 2026-11-24
                "ts": "2026-10-15T10:00:00+08:00",
            },
            {
                "kind": "horizon_waste",
                "source": "copilot_cli",
                "session_id": "sess-3",
                "role_key": "m1",
                "skill": "agent-retro",
                "horizon_code": "HZN1_context_carry_tax",
                "category_key": "context_carry",
                "wasted_turns": 7,
                "wasted_tokens": 30000,
                "duration_sec": 55.2,
                "ts": "2026-11-24T15:05:00+08:00",
            },
            {
                "kind": "horizon_waste",
                "source": "copilot_cli",
                "session_id": "sess-2",
                "role_key": "m1",
                "skill": "team-lead",
                "horizon_code": "HZN5_steering_overkill_mechanical_span",
                "category_key": "steering_overkill",
                "wasted_turns": 5,
                "wasted_tokens": 10000,
                "duration_sec": 30.0,
                "ts": "2026-11-24T12:10:00+08:00",
            },
        ],
        db_path=clean_dir / "agent_retro.db",
    )
    merge.run_merge()
    return warehouse


def test_l4_agent_retro_six_layer_query_aggregates_prefix_postfix_and_attributions(tmp_path, monkeypatch):
    _build_fixture_warehouse(tmp_path, monkeypatch)
    rows, cols = serve.run_query("retro/agent_retro_six_layer", {"until_day": "2026-11-24", "days": 14})
    by_layer = {row[cols.index("layer_key")]: dict(zip(cols, row)) for row in rows}

    assert [row[cols.index("layer_key")] for row in rows] == [
        "role", "handoff", "invoke", "exec", "friction", "horizon",
    ]
    assert by_layer["role"]["pre_fix_count"] == 4
    assert by_layer["role"]["post_fix_count"] == 1
    assert by_layer["role"]["total_occurrences"] == 5
    assert by_layer["role"]["top_role_key"] == "m2"
    assert by_layer["role"]["top_skill"] == "m2-dispatcher"
    assert by_layer["role"]["top_skill_version"] == "v5@2222bbb"
    assert by_layer["role"]["coverage_status"] == "covered"
    assert by_layer["role"]["source_as_of"] == "2026-11-24"
    assert by_layer["role"]["sample_size"] == 3

    # Old October row excluded by rolling 14d CST window
    assert by_layer["handoff"]["total_occurrences"] == 0
    assert by_layer["invoke"]["post_fix_count"] == 2
    assert by_layer["invoke"]["top_skill"] == "agent-retro"


def test_l4_agent_horizon_waste_query_aggregates_wasted_turns_and_tokens(tmp_path, monkeypatch):
    _build_fixture_warehouse(tmp_path, monkeypatch)
    rows, cols = serve.run_query("retro/agent_horizon_waste", {"until_day": "2026-11-24", "days": 14})
    items = [dict(zip(cols, row)) for row in rows]

    assert len(items) == 2
    assert items[0]["category_key"] == "context_carry"
    assert items[0]["skill"] == "agent-retro"
    assert items[0]["wasted_turns"] == 7
    assert items[0]["wasted_tokens"] == 30000
    assert items[0]["token_share_pct"] == 75.0
    assert items[1]["category_key"] == "steering_overkill"
    assert items[1]["wasted_tokens"] == 10000
    assert items[1]["token_share_pct"] == 25.0


def test_l4_skill_roi_diagnostics_accepts_agent_retro_skill(tmp_path, monkeypatch):
    warehouse = _build_fixture_warehouse(tmp_path, monkeypatch)
    with sqlite3.connect(warehouse) as conn:
        conn.execute(
            "INSERT INTO fact_turn (turn_uuid, session_id, ts, role, attribution_skill, skill_names, input_tokens, output_tokens) "
            "VALUES ('t-ar-1', 's-ar-1', '2026-11-24T08:00:00Z', 'assistant', 'agent-retro', '[\"agent-retro\"]', 1200, 400)"
        )
        conn.commit()

    rows, cols = serve.run_query("retro/skill_roi_diagnostics")
    by_skill = {row[cols.index("skill")]: dict(zip(cols, row)) for row in rows}
    assert "agent-retro" in by_skill
    assert by_skill["agent-retro"]["loads_7d"] == 1
    assert by_skill["agent-retro"]["coverage_status"] == "covered"
