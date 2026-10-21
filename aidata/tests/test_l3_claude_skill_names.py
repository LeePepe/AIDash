import sqlite3

import merge


def _make_clean_claude(path, *, with_skill_names):
    path.unlink(missing_ok=True)
    conn = sqlite3.connect(path)
    skill_column = ", skill_names TEXT" if with_skill_names else ""
    conn.execute(
        f"""CREATE TABLE turn (
            turn_uuid TEXT PRIMARY KEY, session_id TEXT, parent_session_id TEXT,
            ts TEXT, project TEXT, git_branch TEXT, role TEXT, model TEXT,
            attribution_skill TEXT, input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_creation INTEGER, tool_calls TEXT,
            finish_reason TEXT{skill_column}
        )"""
    )
    columns = 16 if with_skill_names else 15
    values = [
        "turn-1", "session-1", None, "2026-10-20T01:02:03Z", "AIDash",
        "main", "assistant", "claude-opus-4-8", None, 100, 20, 30, 4,
        '["Skill"]', "end_turn",
    ]
    if with_skill_names:
        values.append('["$goal-target-task"]')
    conn.execute(
        f"INSERT INTO turn VALUES ({', '.join('?' for _ in range(columns))})",
        values,
    )
    conn.commit()
    conn.close()


def test_merge_copies_skill_names_and_defaults_old_clean_db(
    tmp_path, monkeypatch
):
    clean_dir = tmp_path / "clean"
    clean_dir.mkdir()
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")
    monkeypatch.setattr(merge, "SCHEMA_DIR", merge.SCHEMA_DIR)

    claude_db = clean_dir / "claude_jsonl.db"
    _make_clean_claude(claude_db, with_skill_names=True)
    assert merge.run_merge()["fact_turn"] == 1
    conn = sqlite3.connect(warehouse)
    row = conn.execute("SELECT skill_names FROM fact_turn").fetchone()
    conn.close()
    assert row == ('["$goal-target-task"]',)

    _make_clean_claude(claude_db, with_skill_names=False)
    assert merge.run_merge()["fact_turn"] == 1
    conn = sqlite3.connect(warehouse)
    row = conn.execute("SELECT skill_names FROM fact_turn").fetchone()
    conn.close()
    assert row == (None,)
