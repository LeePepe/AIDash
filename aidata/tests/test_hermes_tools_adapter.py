"""Hermetic unit tests for adapters/hermes_tools — no real state.db required.

collect() is exercised against a real temp SQLite `messages` table (proving the
tool_name/timestamp watermark SELECT and the content/tool_calls red line), while
normalize() is monkeypatched at the raw/clean boundary to prove the per-CST-day
x per-tool aggregation and the +8h day-bucket convention deterministically.
"""

import sqlite3
from pathlib import Path

import pytest

import adapters.hermes_tools as ht


def _make_messages_db(tmp_path: Path) -> Path:
    """A minimal messages table mirroring the real schema's relevant columns,
    including content/tool_calls so tests can prove those are never read."""
    db = tmp_path / "state.db"
    conn = sqlite3.connect(db)
    conn.execute(
        "CREATE TABLE messages ("
        "session_id TEXT, role TEXT, tool_name TEXT, timestamp REAL, "
        "content TEXT, tool_calls TEXT)"
    )
    rows = [
        # tool_name, timestamp (epoch secs), content, tool_calls
        ("terminal", 1783771243.5, "SECRET-CMD", "SECRET-CALLS"),
        ("terminal", 1783771250.0, "SECRET-CMD", "SECRET-CALLS"),
        ("write_file", 1783771260.0, "SECRET", "SECRET"),
        (None, 1783771270.0, "user text", None),  # non-tool row -> excluded
    ]
    conn.executemany(
        "INSERT INTO messages (tool_name, timestamp, content, tool_calls) "
        "VALUES (?, ?, ?, ?)",
        rows,
    )
    conn.commit()
    conn.close()
    return db


@pytest.mark.unit
def test_collect_degrades_when_db_missing(monkeypatch):
    monkeypatch.setattr(ht, "HERMES_STATE_DB", Path("/nope/does/not/exist.db"))
    monkeypatch.setattr(ht, "query_ro",
                        lambda *a, **k: pytest.fail("should not query a missing db"))
    assert ht.collect() == 0


@pytest.mark.unit
def test_collect_reads_tool_rows_and_sets_watermark(monkeypatch, tmp_path):
    db = _make_messages_db(tmp_path)
    monkeypatch.setattr(ht, "HERMES_STATE_DB", db)
    monkeypatch.setattr(ht, "get_watermark", lambda source: None)
    captured = {}

    def _cap_raw(source, records):
        captured["recs"] = list(records)
        return len(captured["recs"])

    monkeypatch.setattr(ht, "write_raw", _cap_raw)
    monkeypatch.setattr(ht, "set_watermark",
                        lambda source, value: captured.__setitem__("wm", value))
    n = ht.collect()
    # Only the 3 tool rows survive (NULL tool_name excluded by the WHERE clause).
    assert n == 3
    assert captured["wm"] == 1783771260.0  # max timestamp of collected rows
    # Red line: only tool_name + timestamp leave the DB — never content/tool_calls.
    for rec in captured["recs"]:
        assert set(rec.keys()) == {"tool_name", "timestamp"}
    assert "SECRET-CMD" not in repr(captured["recs"])
    assert "SECRET-CALLS" not in repr(captured["recs"])


@pytest.mark.unit
def test_collect_respects_watermark(monkeypatch, tmp_path):
    db = _make_messages_db(tmp_path)
    monkeypatch.setattr(ht, "HERMES_STATE_DB", db)
    # Watermark past the first two rows -> only write_file (1783771260) remains.
    monkeypatch.setattr(ht, "get_watermark", lambda source: 1783771255.0)
    captured = {}

    def _cap_raw(source, records):
        captured["recs"] = list(records)
        return len(captured["recs"])

    monkeypatch.setattr(ht, "write_raw", _cap_raw)
    monkeypatch.setattr(ht, "set_watermark",
                        lambda source, value: captured.__setitem__("wm", value))
    n = ht.collect()
    assert n == 1
    assert captured["recs"][0]["tool_name"] == "write_file"


@pytest.mark.unit
def test_collect_empty_is_zero_no_watermark(monkeypatch, tmp_path):
    db = tmp_path / "state.db"
    db.write_text("stub")
    monkeypatch.setattr(ht, "HERMES_STATE_DB", db)
    monkeypatch.setattr(ht, "query_ro", lambda *a, **k: [])
    monkeypatch.setattr(ht, "set_watermark",
                        lambda *a, **k: pytest.fail("no watermark on empty"))
    monkeypatch.setattr(ht, "write_raw",
                        lambda *a, **k: pytest.fail("no write on empty"))
    assert ht.collect() == 0


@pytest.mark.unit
def test_normalize_aggregates_per_day_per_tool(monkeypatch):
    # 08:00 UTC 2026-07-10 = 16:00 CST 2026-07-10.
    day10 = 1783670400.0   # 2026-07-10T08:00:00Z -> CST 2026-07-10
    # 16:00 UTC 2026-07-10 = 00:00 CST 2026-07-11 (the exact day flip).
    day11 = 1783699200.0   # 2026-07-10T16:00:00Z -> CST 2026-07-11
    raw = [
        {"tool_name": "terminal", "timestamp": day10},
        {"tool_name": "terminal", "timestamp": day10 + 10},
        {"tool_name": "terminal", "timestamp": day11},
        {"tool_name": "write_file", "timestamp": day10},
        {"tool_name": None, "timestamp": day10},        # skipped (no tool)
        {"tool_name": "read_file", "timestamp": None},   # skipped (bad ts)
    ]
    monkeypatch.setattr(ht, "read_raw", lambda source: raw)
    captured = {}

    def _cap_clean(source, table, ddl, rows, cols):
        captured["rows"] = {(r["day"], r["tool_name"]): r["n"] for r in rows}
        captured["cols"] = cols
        captured["table"] = table
        return len(rows)

    monkeypatch.setattr(ht, "write_clean", _cap_clean)
    n = ht.normalize()
    assert captured["table"] == "tool_day"
    assert captured["cols"] == ("day", "tool_name", "n")
    assert captured["rows"][("2026-07-10", "terminal")] == 2
    assert captured["rows"][("2026-07-11", "terminal")] == 1   # +8h day flip
    assert captured["rows"][("2026-07-10", "write_file")] == 1
    # Skipped rows contribute nothing.
    assert n == 3


@pytest.mark.unit
def test_normalize_empty_raw_is_zero(monkeypatch):
    monkeypatch.setattr(ht, "read_raw", lambda source: [])
    monkeypatch.setattr(ht, "write_clean",
                        lambda source, table, ddl, rows, cols: len(rows))
    assert ht.normalize() == 0


@pytest.mark.unit
def test_source_name():
    assert ht.SOURCE == "hermes_tools"
