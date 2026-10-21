"""Hermetic tests for tokens/by-project and its prompt allocation rule."""

import sqlite3
from pathlib import Path

import pytest
import serve


def _dbs(tmp_path: Path):
    warehouse = tmp_path / "warehouse.db"
    con = sqlite3.connect(warehouse)
    con.executescript("""
        CREATE TABLE fact_request (
            cst_day TEXT, client TEXT, input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_write INTEGER
        );
        CREATE TABLE fact_turn (
            cst_day TEXT, session_id TEXT, ts TEXT, input_tokens INTEGER,
                output_tokens INTEGER, cache_read INTEGER, cache_creation INTEGER
        );
    """)
    con.executemany("INSERT INTO fact_request VALUES (?, ?, ?, ?, ?, ?)", [
        ("2026-10-20", "codex_exec", 10, 5, 2, 1),
        ("2026-10-20", "Claude", 999, 999, 0, 0),  # excluded client
    ])
    con.executemany("INSERT INTO fact_turn VALUES (?, ?, ?, ?, ?, ?, ?)", [
        ("2026-10-20", "s1", "1970-01-01T00:16:40Z", 20, 10, 3, 4),
        ("2026-10-20", "s2", "1970-01-01T00:08:20Z", 4, 1, 0, 0),
        ("2026-10-20", "s3", "1970-01-01T00:25:00Z", 2, 3, 0, 0),
    ])
    con.commit()
    con.close()

    prompts = tmp_path / "claude_prompts.db"
    con = sqlite3.connect(prompts)
    con.execute("CREATE TABLE prompt (prompt_id TEXT, session_id TEXT, ts REAL, repo TEXT)")
    con.executemany("INSERT INTO prompt VALUES (?, ?, ?, ?)", [
        ("a", "s1", 900, "owner/old"),
        ("a", "s1", 1000, "owner/early-tie"),
        ("z", "s1", 1000, "owner/latest-tie"),
        ("b", "s2", 700, "owner/fallback"),
    ])
    con.commit()
    con.close()

    state = tmp_path / "state_db.db"
    con = sqlite3.connect(state)
    con.execute("""CREATE TABLE session (
        started_at REAL, repo TEXT, input_tokens INTEGER, output_tokens INTEGER,
        cache_read_tokens INTEGER, cache_write_tokens INTEGER
    )""")
    con.execute("INSERT INTO session VALUES (1792454400, 'owner/hermes', 6, 4, 1, 2)")
    con.commit()
    con.close()
    return warehouse, prompts, state


def test_project_query_allocates_prompts_and_conserves_share(tmp_path, monkeypatch):
    warehouse, prompts, state = _dbs(tmp_path)
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(serve, "clean_path", lambda source: {
        "claude_prompts": prompts, "state_db": state}[source])
    rows, cols = serve.run_query("tokens/by-project")
    by_repo = {row[1]: row for row in rows}
    assert by_repo["owner/latest-tie"][2:4] == (20, 10)
    assert by_repo["owner/fallback"][2:4] == (4, 1)
    assert by_repo["(unresolved)"][2:4] == (2, 3)
    assert by_repo["(unattributed)"][2:4] == (10, 5)
    assert sum(row[6] for row in rows) == pytest.approx(100.0, abs=0.001)
    assert cols == ["cst_day", "repo", "input", "output", "cache_read",
                    "cache_write", "share_pct"]

