import sqlite3

import merge
import pytest


def _make_clean_raven(path, *, with_cache):
    conn = sqlite3.connect(path)
    cache_columns = ", cache_read INTEGER, cache_write INTEGER" if with_cache else ""
    conn.execute(
        f"""CREATE TABLE req (
            request_id TEXT PRIMARY KEY, ts INTEGER, client TEXT, version TEXT,
            model TEXT, model_canon TEXT, resolved_model TEXT,
            input_tokens INTEGER, output_tokens INTEGER{cache_columns},
            total_tokens INTEGER, latency_ms INTEGER, ttft_ms INTEGER,
            status TEXT, cost_usd REAL, session_uuid TEXT,
            has_session INTEGER, tool_call_count INTEGER, strategy TEXT,
            path TEXT
        )"""
    )
    values = [
        "r1", 1_760_500_000_000, "codex_exec", "1", "gpt-5-mini",
        "gpt-5-mini", None, 100, 20,
    ]
    if with_cache:
        values.extend([30, 4])
    values.extend([120, None, None, "success", None, None, 0, None, None, "/tmp"])
    placeholders = ", ".join("?" for _ in values)
    conn.execute(f"INSERT INTO req VALUES ({placeholders})", values)
    conn.commit()
    conn.close()


@pytest.mark.unit
@pytest.mark.parametrize("with_cache", [True, False])
def test_merge_copies_cache_tokens_and_defaults_old_clean_db(
    tmp_path, monkeypatch, with_cache
):
    clean_dir = tmp_path / "clean"
    clean_dir.mkdir()
    warehouse = tmp_path / "warehouse.db"
    raven_db = clean_dir / "raven.db"
    _make_clean_raven(raven_db, with_cache=with_cache)

    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: clean_dir / f"{source}.db")
    monkeypatch.setattr(merge, "SCHEMA_DIR", merge.SCHEMA_DIR)

    assert merge.run_merge()["fact_request"] == 1
    conn = sqlite3.connect(warehouse)
    row = conn.execute(
        "SELECT input_tokens, output_tokens, cache_read, cache_write "
        "FROM fact_request"
    ).fetchone()
    conn.close()

    assert row[:2] == (100, 20)
    assert row[2:] == ((30, 4) if with_cache else (None, None))


@pytest.mark.unit
def test_run_merge_loads_dated_raven_model_price(tmp_path, monkeypatch):
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    monkeypatch.setattr(merge, "clean_path", lambda source: tmp_path / f"{source}.db")

    merge.run_merge()

    conn = sqlite3.connect(warehouse)
    row = conn.execute(
        "SELECT input_per_mtok, output_per_mtok, cache_read_per_mtok, "
        "cache_write_per_mtok FROM dim_model WHERE model = ?",
        ("gpt-4.1-2025-04-14",),
    ).fetchone()
    conn.close()
    assert row == (2.0, 8.0, 0.5, 0.0)
