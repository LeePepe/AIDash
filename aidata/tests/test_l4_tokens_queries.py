"""Hermetic acceptance tests for the L4 token-union queries."""

import sqlite3
from pathlib import Path

from aidata import serve


def _fixture(tmp_path: Path, monkeypatch):
    warehouse = tmp_path / "warehouse.db"
    conn = sqlite3.connect(warehouse)
    conn.executescript(
        """
        CREATE TABLE fact_request (
            request_id TEXT PRIMARY KEY, cst_day TEXT, client TEXT, model TEXT,
            model_canon TEXT, input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_write INTEGER, cost_usd REAL
        );
        CREATE TABLE fact_turn (
            turn_uuid TEXT PRIMARY KEY, session_id TEXT, ts TEXT, cst_day TEXT,
            role TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_creation INTEGER, cost_usd REAL
        );
        CREATE TABLE dim_automation_rule (kind TEXT, match TEXT, class TEXT);
        INSERT INTO dim_automation_rule VALUES
          ('cwd_prefix', '/private/tmp/herdr-', 'automated'),
          ('cwd_prefix', '/Users/lee/Development/worktrees/', 'automated'),
          ('client', 'multica-agent-sdk', 'automated'),
          ('client', 'codex_exec', 'automated'),
          ('client', 'codex-tui', 'interactive'),
          ('client', 'claude-code', 'interactive');
        INSERT INTO fact_request VALUES
          ('r1', '2026-10-15', 'multica-agent-sdk', 'raven-model', 'raven-model', 100, 50, 7, 8, 1.25),
          ('r2', '2026-10-15', 'codex-tui', 'excluded-model', 'excluded-model', 999, 999, 1, 1, 9.0),
          ('r3', '2026-10-15', 'codex_exec', 'exec-model', 'exec-model', 20, 10, 2, 3, NULL);
        INSERT INTO fact_turn VALUES
          ('t1', 's1', '2026-10-15T00:00:20Z', '2026-10-15', 'assistant', 'claude-model', 30, 20, 4, 5, 2.0),
          ('t2', 's2', '2026-10-15T00:00:30Z', '2026-10-15', 'assistant', 'claude-model', 40, 10, 1, 2, NULL),
          ('t3', 's3', '2026-10-15T00:00:00Z', '2026-10-15', 'assistant', 'claude-model', 5, 5, 0, 0, NULL);
        """
    )
    conn.commit()
    conn.close()

    state_db = tmp_path / "state_db.db"
    conn = sqlite3.connect(state_db)
    conn.executescript(
        """
        CREATE TABLE session (
            started_at REAL, input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_write_tokens INTEGER,
            actual_cost_usd REAL, estimated_cost_usd REAL, model TEXT,
            is_automated INTEGER
        );
        INSERT INTO session VALUES
          (1792022400, 10, 5, 2, 3, NULL, 0.5, 'hermes-model', 0);
        """
    )
    conn.commit()
    conn.close()

    prompts_db = tmp_path / "claude_prompts.db"
    conn = sqlite3.connect(prompts_db)
    conn.executescript(
        """
        CREATE TABLE prompt (prompt_id TEXT PRIMARY KEY, session_id TEXT,
                             ts REAL, cwd TEXT);
        INSERT INTO prompt VALUES
          ('p1', 's1', 1792022410, '/Users/lee/Development'),
          ('p2', 's1', 1792022415, '/private/tmp/herdr-s1'),
          ('p-a', 's2', 1792022430, '/Users/lee/Development'),
          ('p-z', 's2', 1792022430, '/private/tmp/herdr-s2'),
          ('p-first', 's3', 1792022500, '/private/tmp/herdr-s3');
        """
    )
    conn.commit()
    conn.close()

    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(serve, "clean_path", lambda source: {
        "state_db": state_db, "claude_prompts": prompts_db
    }[source])


def _run(name):
    return serve.run_query(name, {"day_from": "2026-10-15", "day_to": "2026-10-15"})


def test_daily_by_client_unions_sources_and_keeps_cache_separate(tmp_path, monkeypatch):
    _fixture(tmp_path, monkeypatch)
    rows, cols = _run("tokens/daily-by-client")
    by_client = {row[1]: dict(zip(cols, row)) for row in rows}

    assert set(by_client) == {
        "multica-agent-sdk", "codex_exec", "codex-tui", "claude-code", "hermes"
    }
    assert by_client["multica-agent-sdk"]["input"] == 100
    assert by_client["multica-agent-sdk"]["output"] == 50
    assert by_client["multica-agent-sdk"]["cache_read"] == 7
    assert by_client["multica-agent-sdk"]["cost_usd"] == 1.25
    assert by_client["codex_exec"]["cost_usd"] is None
    assert by_client["codex_exec"]["unpriced_rows"] == 1
    assert round(sum(row["share_pct"] for row in by_client.values()), 2) == 100.0


def test_share_by_model_conserves_input_output_and_excludes_raven_exclusions(
    tmp_path, monkeypatch
):
    _fixture(tmp_path, monkeypatch)
    rows, cols = _run("tokens/share-by-model")
    assert any(row[1] == "excluded-model" for row in rows)
    assert round(sum(row[-1] for row in rows), 2) == 100.0
    claude = next(dict(zip(cols, row)) for row in rows if row[1] == "claude-model")
    assert claude["cache_read"] == 5
    assert claude["cache_write"] == 7


def test_automated_share_applies_cwd_precedence_ties_and_earliest_fallback(
    tmp_path, monkeypatch
):
    _fixture(tmp_path, monkeypatch)
    rows, cols = _run("tokens/automated-share")
    by_class = {row[1]: dict(zip(cols, row)) for row in rows}

    # Raven multica/codex_exec + all three Claude turns are automated. The
    # equal-timestamp s2 tie chooses p-z, and s3 falls back to p-first.
    assert by_class["automated"]["input"] == 195
    assert by_class["automated"]["output"] == 95
    assert by_class["interactive"]["input"] == 1009  # codex-tui + Hermes
    assert by_class["interactive"]["output"] == 1004
    assert round(sum(row["share_pct"] for row in by_class.values()), 2) == 100.0
