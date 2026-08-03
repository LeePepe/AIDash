"""Hermetic unit tests for adapters/state_db — no real state.db required.

query_ro and the raw/clean/watermark IO are monkeypatched, so the automation
mapping and degrade paths are proven deterministically.
"""

from pathlib import Path

import pytest

import adapters.state_db as sdb


_ROWS = [
    {"id": "s1", "started_at": 1783771243.89, "ended_at": 1783771300.0,
     "message_count": 4, "tool_call_count": 2, "input_tokens": 100,
     "output_tokens": 50, "cache_read_tokens": 800, "cache_write_tokens": 40,
     "reasoning_tokens": 12, "end_reason": "stop",
     "source": "cron", "model": "claude-opus-4.7"},
    {"id": "s2", "started_at": 1783771303.98, "ended_at": None,
     "message_count": 1, "tool_call_count": 0, "input_tokens": 10,
     "output_tokens": 5, "cache_read_tokens": 0, "cache_write_tokens": 0,
     "reasoning_tokens": 0, "end_reason": None,
     "source": "cli", "model": "claude-opus-4.7"},
    {"id": "s3", "started_at": 1783774857.67, "ended_at": None,
     "message_count": 2, "tool_call_count": 1, "input_tokens": 20,
     "output_tokens": 8, "cache_read_tokens": 160, "cache_write_tokens": 8,
     "reasoning_tokens": 3, "end_reason": "max_tokens",
     "source": "subagent", "model": "gpt-5.5"},
    {"id": "s4", "started_at": 1783760000.00, "ended_at": None,
     "message_count": 1, "tool_call_count": 0, "input_tokens": 1,
     "output_tokens": 1, "cache_read_tokens": 0, "cache_write_tokens": 0,
     "reasoning_tokens": 0, "end_reason": None,
     "source": "weixin", "model": "x"},
    {"id": "s5", "started_at": 1783761000.00, "ended_at": None,
     "message_count": 1, "tool_call_count": 0, "input_tokens": 1,
     "output_tokens": 1, "cache_read_tokens": 0, "cache_write_tokens": 0,
     "reasoning_tokens": 0, "end_reason": None,
     "source": "unknown", "model": "x"},
]


@pytest.mark.unit
def test_collect_degrades_when_db_missing(monkeypatch):
    monkeypatch.setattr(sdb, "HERMES_STATE_DB", Path("/nope/does/not/exist.db"))
    monkeypatch.setattr(sdb, "query_ro",
                        lambda *a, **k: pytest.fail("should not query a missing db"))
    assert sdb.collect() == 0


@pytest.mark.unit
def test_collect_reads_and_sets_watermark(monkeypatch, tmp_path):
    db = tmp_path / "state.db"
    db.write_text("stub")  # existence check only; query_ro is stubbed
    monkeypatch.setattr(sdb, "HERMES_STATE_DB", db)
    monkeypatch.setattr(sdb, "query_ro", lambda *a, **k: _ROWS)
    monkeypatch.setattr(sdb, "get_watermark", lambda source: None)
    captured = {}

    def _cap_raw(source, records):
        captured["recs"] = records
        return len(records)

    monkeypatch.setattr(sdb, "write_raw", _cap_raw)
    monkeypatch.setattr(sdb, "set_watermark",
                        lambda source, value: captured.__setitem__("wm", value))
    n = sdb.collect()
    assert n == 5
    assert captured["wm"] == max(r["started_at"] for r in _ROWS)


@pytest.mark.unit
def test_collect_empty_is_zero_no_watermark(monkeypatch, tmp_path):
    db = tmp_path / "state.db"
    db.write_text("stub")
    monkeypatch.setattr(sdb, "HERMES_STATE_DB", db)
    monkeypatch.setattr(sdb, "query_ro", lambda *a, **k: [])
    monkeypatch.setattr(sdb, "get_watermark", lambda source: 0)
    monkeypatch.setattr(sdb, "set_watermark",
                        lambda *a, **k: pytest.fail("no watermark on empty"))
    monkeypatch.setattr(sdb, "write_raw",
                        lambda *a, **k: pytest.fail("no write on empty"))
    assert sdb.collect() == 0


@pytest.mark.unit
def test_select_reads_all_columns():
    """Collection is full-column by design (changed 2026-08-03).

    The previous test asserted the opposite — that system_prompt/model_config/
    billing_* stayed OUT. That allowlist was reversed deliberately: those fields
    answer questions the warehouse otherwise cannot (which prompt/effort setting
    produced which cost; provider-reported vs aidata-derived cost), and the repo
    was made private so the exposure calculus changed.

    `SELECT *` rather than a wider allowlist is also deliberate — an allowlist
    silently drops columns Hermes adds later, and that failure is invisible.

    Redaction still applies on the way to raw/ (rawio.write_raw -> redact_obj),
    but note what it can and cannot do: it matches credential SHAPES (keys,
    bearer tokens, emails). Prose inside system_prompt is NOT redacted.
    """
    assert "SELECT *" in sdb._SELECT
    assert "FROM sessions" in sdb._SELECT
    # The watermark predicate must survive any rewrite, or collect() re-reads
    # the entire table on every run.
    assert "started_at > ?" in sdb._SELECT


@pytest.mark.unit
def test_clean_schema_stores_prompt_identity_not_prompt_text():
    """L2 keeps a hash + short preview, never the ~15 KB prompt body.

    Full text lives in raw/. Storing it again in the clean DB would multiply a
    ~203 MB field for no query benefit — grouping by hash answers the actual
    question ("did prompt X cost more than Y?").
    """
    assert "system_prompt_sha" in sdb._CLEAN_COLS
    assert "system_prompt_preview" in sdb._CLEAN_COLS
    assert "system_prompt" not in sdb._CLEAN_COLS


@pytest.mark.unit
def test_prompt_identity_is_stable_and_bounded():
    sha_a, preview_a, len_a = sdb._prompt_identity("x" * 5000)
    sha_b, _, _ = sdb._prompt_identity("x" * 5000)
    sha_c, _, _ = sdb._prompt_identity("y" * 5000)
    assert sha_a == sha_b, "same prompt must hash identically (grouping key)"
    assert sha_a != sha_c
    assert len(preview_a) == sdb._PREVIEW_CHARS
    assert len_a == 5000, "length reflects the ORIGINAL, not the preview"
    assert sdb._prompt_identity(None) == (None, None, None)
    assert sdb._prompt_identity("") == (None, None, None)


@pytest.mark.unit
def test_model_config_parses_and_degrades():
    effort, enabled, iters = sdb._model_config(
        '{"max_iterations": 60, "reasoning_config": '
        '{"enabled": true, "effort": "medium"}, "max_tokens": null}'
    )
    assert (effort, enabled, iters) == ("medium", 1, 60)
    # Degrade-safe (ADR-23): malformed/absent config must not raise — an upstream
    # config-shape change cannot be allowed to break the whole normalize.
    assert sdb._model_config("not json") == (None, None, None)
    assert sdb._model_config(None) == (None, None, None)
    assert sdb._model_config("[1,2,3]") == (None, None, None)
    assert sdb._model_config('{"reasoning_config": "wrong-type"}') == (None, None, None)


@pytest.mark.unit
def test_normalize_is_automated_mapping(monkeypatch):
    monkeypatch.setattr(sdb, "read_raw", lambda source: _ROWS)
    captured = {}

    def _cap_clean(source, table, ddl, rows, cols):
        captured["rows"] = {r["session_id"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(sdb, "write_clean", _cap_clean)
    n = sdb.normalize()
    assert n == 5
    r = captured["rows"]
    assert r["s1"]["is_automated"] == 1   # cron
    assert r["s3"]["is_automated"] == 1   # subagent
    assert r["s2"]["is_automated"] == 0   # cli
    assert r["s4"]["is_automated"] == 0   # weixin
    assert r["s5"]["is_automated"] == 0   # unknown -> manual (conservative)


@pytest.mark.unit
def test_normalize_carries_new_token_columns(monkeypatch):
    monkeypatch.setattr(sdb, "read_raw", lambda source: _ROWS)
    captured = {}

    def _cap_clean(source, table, ddl, rows, cols):
        captured["rows"] = {r["session_id"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(sdb, "write_clean", _cap_clean)
    sdb.normalize()
    # New columns are declared and populated (closing the cache-read gap).
    for col in ("cache_read_tokens", "cache_write_tokens",
                "reasoning_tokens", "end_reason"):
        assert col in captured["cols"]
    s1 = captured["rows"]["s1"]
    assert s1["cache_read_tokens"] == 800
    assert s1["cache_write_tokens"] == 40
    assert s1["reasoning_tokens"] == 12
    assert s1["end_reason"] == "stop"
    # Nullable end_reason survives as None (not coerced).
    assert captured["rows"]["s2"]["end_reason"] is None


@pytest.mark.unit
def test_normalize_started_at_is_epoch_seconds_float(monkeypatch):
    monkeypatch.setattr(sdb, "read_raw", lambda source: _ROWS[:1])
    captured = {}
    monkeypatch.setattr(
        sdb, "write_clean",
        lambda source, table, ddl, rows, cols: captured.setdefault("rows", rows),
    )
    sdb.normalize()
    row = captured["rows"][0]
    # Stored unchanged so SQL date(started_at,'unixepoch','+8 hours') is correct.
    assert row["started_at"] == 1783771243.89
    assert isinstance(row["started_at"], float)


@pytest.mark.unit
def test_automated_sources_definition():
    assert sdb.AUTOMATED_SOURCES == frozenset({"cron", "subagent"})
