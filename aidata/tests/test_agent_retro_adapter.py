from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone

import config
from adapters import agent_retro


def test_agent_retro_not_in_scheduled_or_automatic_sources():
    assert "agent_retro" not in config.SOURCES
    assert "agent_retro" not in config.SCHEDULED_SOURCES
    assert "agent_retro" not in config.MERGE_SOURCES


def test_normalize_records_persists_privacy_safe_6_layers_watermarks_and_horizon(tmp_path):
    db_path = tmp_path / "clean" / "agent_retro.db"
    records = [
        {
            "kind": "retro_finding",
            "source": "copilot_cli",
            "session_id": "/Users/secretuser/private/session-001",
            "goal_id": "aidata-agent-retro-v2",
            "role": "m1_steering",
            "skill": "goal-target-task",
            "layer": "L-Invoke",
            "finding_code": "I3_l2_exit2_and_output_bloat",
            "severity": "high",
            "skill_version": "2.1.0+v14@9abc123",
            "pre_fix_count": 2,
            "post_fix_count": 1,
            "prompt": "Bearer ghp_secretTokenShouldNeverPersist1234567890",
            "transcript": "raw user transcript that must never land in sqlite",
            "file_path": "/Users/secretuser/secret-key.pem",
            "ts": "2026-11-24T18:30:00Z",
        },
        {
            "kind": "retro_finding",
            "source": "copilot_cli",
            "session_id": "sess-healthy",
            "skill": "agent-retro",
            "layer_key": "exec",
            "finding_code": "E1_blind_spin_loop_vs_progressive_catch",
            "status": "healthy_progressive_disclosure",
            "occurrence_count": 3,
            "ts": "2026-11-24T19:00:00Z",
        },
        {
            "kind": "horizon_waste",
            "source": "copilot_cli",
            "session_id": "/Users/secretuser/private/session-001",
            "role_key": "m1",
            "skill": "agent-retro",
            "horizon_code": "HZN1_context_carry_tax",
            "category_key": "context_carry",
            "wasted_turns": 6,
            "wasted_tokens": 18400,
            "duration_sec": 42.5,
            "raw_output": "huge secret tool output",
            "ts": "2026-11-24T18:45:00Z",
        },
    ]

    result = agent_retro.normalize_records(records, db_path=db_path)
    assert db_path.is_file()
    assert len(result["retro_findings"]) == 2  # split into pre_fix (0) and post_fix (1); healthy skipped
    assert len(result["horizon_waste"]) == 1

    with sqlite3.connect(db_path) as conn:
        f_cols = [r[1] for r in conn.execute("PRAGMA table_info(retro_finding)")]
        w_cols = [r[1] for r in conn.execute("PRAGMA table_info(horizon_waste)")]
        f_rows = [dict(zip(f_cols, vals)) for vals in conn.execute("SELECT * FROM retro_finding ORDER BY is_post_fix")]
        w_rows = [dict(zip(w_cols, vals)) for vals in conn.execute("SELECT * FROM horizon_waste")]

    assert [r["is_post_fix"] for r in f_rows] == [0, 1]
    assert [r["occurrence_count"] for r in f_rows] == [2, 1]
    assert f_rows[0]["skill"] == "team-lead"  # alias resolved
    assert f_rows[0]["role_key"] == "m1"
    assert f_rows[0]["layer_key"] == "invoke"
    assert f_rows[0]["skill_version"] == "v14@9abc123"
    assert f_rows[0]["session_id"].startswith("sess:")
    assert "secretuser" not in json.dumps(f_rows)
    assert "ghp_" not in json.dumps(f_rows)
    assert "transcript" not in json.dumps(f_rows)

    assert len(w_rows) == 1
    assert w_rows[0]["skill"] == "agent-retro"
    assert w_rows[0]["category_key"] == "context_carry"
    assert w_rows[0]["wasted_turns"] == 6
    assert w_rows[0]["wasted_tokens"] == 18400
    assert w_rows[0]["duration_sec"] == 42.5
    assert w_rows[0]["session_id"] == f_rows[0]["session_id"]
    assert "secretuser" not in json.dumps(w_rows)


def test_collect_is_deduplicated_and_degrades_to_zero_when_absent(tmp_path, monkeypatch):
    raw_store: list[dict] = []
    monkeypatch.setattr(agent_retro, "read_raw", lambda _src: list(raw_store))
    monkeypatch.setattr(
        agent_retro,
        "write_raw",
        lambda _src, rows: raw_store.extend(rows) or len(rows),
    )

    # Absent snapshot degrades to 0
    assert agent_retro.collect(snapshot_path=tmp_path / "missing.json") == 0

    snapshot_file = tmp_path / "collect-snapshot.json"
    snapshot_payload = {
        "schema": "agent-retro-collect/v1",
        "ok": True,
        "scan": {
            "version_watermark": {
                "current": "v8@abc1234",
                "target_skill_watermarks": {
                    "m2-dispatcher": {"current": "v5@def5678"},
                },
            },
            "observations": [
                {
                    "metric": "R2_m2_direct_code_edit",
                    "layer": "role",
                    "upstream_skill": "m2-dispatcher",
                    "count": 2,
                    "pre_fix_count": 0,
                    "post_fix_count": 2,
                    "fix_bucket": "post_fix",
                    "evidence": ["sess-alpha: direct edit blocked"],
                },
                {
                    "metric": "HZN5_steering_overkill_mechanical_span",
                    "layer": "horizon",
                    "upstream_skill": "team-lead",
                    "count": 5,
                    "post_fix_count": 5,
                    "fix_bucket": "post_fix",
                    "evidence": ["sess-beta: wakeup_lag_sec=210"],
                },
            ],
        },
    }
    snapshot_file.write_text(json.dumps(snapshot_payload), encoding="utf-8")
    clean_db = tmp_path / "clean" / "agent_retro.db"
    fixed_now = datetime(2026, 11, 25, 10, 0, tzinfo=timezone.utc)  # noqa: UP017

    written_first = agent_retro.collect(now=fixed_now, snapshot_path=snapshot_file, db_path=clean_db)
    assert written_first == 3  # 2 retro_findings + 1 horizon_waste
    assert clean_db.is_file()

    # Second run against identical snapshot appends 0 duplicate records
    written_second = agent_retro.collect(now=fixed_now, snapshot_path=snapshot_file, db_path=clean_db)
    assert written_second == 0

    with sqlite3.connect(clean_db) as conn:
        assert conn.execute("SELECT count(*) FROM retro_finding").fetchone()[0] == 2
        assert conn.execute("SELECT count(*) FROM horizon_waste").fetchone()[0] == 1
        m2_ver = conn.execute(
            "SELECT skill_version, is_post_fix FROM retro_finding WHERE skill = 'm2-dispatcher'"
        ).fetchone()
        assert m2_ver == ("v5@def5678", 1)
