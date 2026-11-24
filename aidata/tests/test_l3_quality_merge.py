from __future__ import annotations

import sqlite3

import merge
from adapters.quality_behavior import normalize_records


def test_l3_quality_merge_preserves_source_session_grain(tmp_path, monkeypatch):
    clean_dir = tmp_path / "clean"
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")
    normalize_records(
        [
            {
                "source": "copilot_cli", "session_id": "same-session", "event_id": "cp-p",
                "timestamp": "2026-11-24T01:00:00Z", "skill": "team-lead",
                "source_kind": "typed", "text": "run the workflow",
            },
            {
                "source": "copilot_cli", "session_id": "same-session", "event_id": "cp-a",
                "timestamp": "2026-11-24T01:01:00Z", "skill": "team-lead",
                "event_type": "assistant_activity", "assistant_activity": True,
                "assistant_turn": True,
            },
            {
                "source": "codex_prompts", "session_id": "same-session", "event_id": "cx-p",
                "timestamp": "2026-11-24T02:00:00Z", "skill": "team-lead",
                "source_kind": "typed", "text": "run the workflow",
            },
            {
                "source": "codex_prompts", "session_id": "same-session", "event_id": "cx-a",
                "timestamp": "2026-11-24T02:01:00Z", "skill": "team-lead",
                "event_type": "assistant_activity", "assistant_activity": True,
                "assistant_turn": True,
            },
        ],
        db_path=clean_dir / "quality_behavior.db",
    )
    counts = merge.run_merge()
    assert counts["fact_skill_invocation"] == 2
    with sqlite3.connect(warehouse) as connection:
        rows = connection.execute(
            "SELECT source, session_id, skill, prompt_linked, eligible "
            "FROM fact_skill_invocation ORDER BY source"
        ).fetchall()
    assert rows == [
        ("codex_prompts", "same-session", "team-lead", 1, 1),
        ("copilot_cli", "same-session", "team-lead", 1, 1),
    ]
