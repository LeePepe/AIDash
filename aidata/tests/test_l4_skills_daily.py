"""Hermetic contract tests for the skills/daily exploratory query."""

import sqlite3
from pathlib import Path

import serve

QUERY = Path(__file__).resolve().parents[1] / "L4_serve/queries/skills/daily.sql"


def _dbs(tmp_path):
    warehouse = tmp_path / "warehouse.db"
    con = sqlite3.connect(warehouse)
    con.executescript("""
        CREATE TABLE fact_turn (
            cst_day TEXT, session_id TEXT, attribution_skill TEXT,
            skill_names TEXT
        );
        INSERT INTO fact_turn VALUES
          ('2026-10-15', 'claude-1', 'deep-research', '["web"]'),
          ('2026-10-15', 'claude-2', NULL, '["web", "pdf"]');
    """)
    con.commit(); con.close()
    clean = tmp_path / "clean"; clean.mkdir()
    for name, ddl, rows in (
        ("claude_prompts", "CREATE TABLE prompt (day TEXT, source_kind TEXT, text_preview TEXT, session_id TEXT)",
         [("2026-10-15", "slash_command", "<command-name>commit</command-name>", "claude-1")]),
        ("codex_prompts", "CREATE TABLE skill_use (day TEXT, session_id TEXT, skill TEXT, call_id TEXT); CREATE TABLE prompt (day TEXT, source_kind TEXT, session_id TEXT)",
         [("2026-10-15", "codex-1", "skill-x", "call-1")]),
        ("hermes_tools", "CREATE TABLE skill_day (day TEXT, skill TEXT, n INTEGER)",
         [("2026-10-15", "grounded-citations", 3)]),
    ):
        db = sqlite3.connect(clean / f"{name}.db")
        db.executescript(ddl)
        if name == "claude_prompts":
            db.executemany("INSERT INTO prompt VALUES (?, ?, ?, ?)", rows)
        elif name == "codex_prompts":
            db.execute("INSERT INTO skill_use VALUES (?, ?, ?, ?)", rows[0])
            db.execute("INSERT INTO prompt VALUES (?, ?, ?)", ("2026-10-15", "slash_command", "codex-1"))
        else:
            db.executemany("INSERT INTO skill_day VALUES (?, ?, ?)", rows)
        db.commit(); db.close()
    return warehouse, clean


def test_skills_daily_emits_each_source_without_cross_source_totals(tmp_path, monkeypatch):
    warehouse, clean = _dbs(tmp_path)
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(serve, "clean_path", lambda source: clean / f"{source}.db")
    monkeypatch.setattr(serve, "QUERIES_DIR", QUERY.parent.parent)
    rows, cols = serve.run_query("skills/daily", {"day_from": "2026-10-15",
                                                    "day_to": "2026-10-15"})
    assert cols == ["day", "source", "skill", "n", "sessions"]
    values = {(row[1], row[2]): row[3] for row in rows}
    assert values == {
        ("claude_attribution", "deep-research"): 1,
        ("claude_skill_tool", "pdf"): 1,
        ("claude_skill_tool", "web"): 2,
        ("claude_slash", "commit"): 1,
        ("codex_skill_read", "skill-x"): 1,
        ("codex_slash", "(unrecorded)"): 1,
        ("hermes_skill_view", "grounded-citations"): 3,
    }
