"""Hermetic unit tests for the Hermes tool and skill streams."""

import json
import sqlite3
from pathlib import Path

import adapters.hermes_tools as ht
import pytest


def _make_messages_db(tmp_path: Path) -> Path:
    db = tmp_path / "state.db"
    conn = sqlite3.connect(db)
    conn.execute(
        "CREATE TABLE messages ("
        "session_id TEXT, role TEXT, tool_name TEXT, timestamp REAL, "
        "content TEXT, tool_calls TEXT)"
    )
    rows = [
        ("assistant", "terminal", 1783771243.5, "SECRET-CMD", "SECRET-CALLS"),
        ("assistant", "terminal", 1783771250.0, "SECRET-CMD", "SECRET-CALLS"),
        ("assistant", "write_file", 1783771260.0, "SECRET", "SECRET"),
        ("user", None, 1783771270.0, "user text", None),
    ]
    conn.executemany(
        "INSERT INTO messages (role, tool_name, timestamp, content, tool_calls) "
        "VALUES (?, ?, ?, ?, ?)", rows)
    conn.commit()
    conn.close()
    return db


def _call(call_id="c1", skill="grounded-citations"):
    return [{"id": call_id, "type": "function", "function": {
        "name": "skill_view", "arguments": json.dumps({"name": skill})
    }}]


@pytest.mark.unit
def test_collect_reads_tool_rows_and_sets_legacy_watermark(monkeypatch, tmp_path):
    db = _make_messages_db(tmp_path)
    monkeypatch.setattr(ht, "HERMES_STATE_DB", db)
    monkeypatch.setattr(ht, "get_watermark", lambda source: None)
    captured = {"rows": []}
    monkeypatch.setattr(ht, "write_raw", lambda source, rows:
                        captured["rows"].extend(rows) or len(rows))
    monkeypatch.setattr(ht, "set_watermark", lambda source, value:
                        captured.setdefault("watermarks", {})
                        .__setitem__(source, value))
    assert ht.collect() == 3
    tool_rows = [row for row in captured["rows"] if "tool_name" in row]
    assert len(tool_rows) == 3
    assert captured["watermarks"][ht.SOURCE] == 1783771260.0
    assert all(set(row) == {"tool_name", "timestamp"} for row in tool_rows)
    assert "SECRET-CMD" not in repr(tool_rows)
    assert "SECRET-CALLS" not in repr(tool_rows)


@pytest.mark.unit
def test_collect_skill_history_has_independent_watermark(monkeypatch, tmp_path):
    db = tmp_path / "state.db"
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE messages (role TEXT, timestamp REAL, tool_name TEXT, tool_calls TEXT)")
    con.execute("INSERT INTO messages VALUES (?, ?, ?, ?)",
                ("assistant", 10.0, None, json.dumps(_call())))
    con.execute("INSERT INTO messages VALUES (?, ?, ?, ?)",
                ("user", 11.0, None, json.dumps(_call("u1"))))
    con.commit()
    con.close()
    captured = {"rows": [], "watermarks": {}}
    monkeypatch.setattr(ht, "HERMES_STATE_DB", db)
    monkeypatch.setattr(ht, "get_watermark", lambda source: 100.0 if source == ht.SOURCE else 0)
    monkeypatch.setattr(ht, "write_raw", lambda source, rows:
                        captured["rows"].extend(rows) or len(rows))
    monkeypatch.setattr(ht, "set_watermark", lambda source, value:
                        captured["watermarks"].__setitem__(source, value))
    assert ht.collect() == 1
    assert captured["rows"] == [{"call_id": "c1", "timestamp": 10.0,
                                  "skill": "grounded-citations"}]
    assert captured["watermarks"][ht.SKILL_SOURCE] == 10.0
    assert ht.SOURCE not in captured["watermarks"]


@pytest.mark.unit
def test_extracts_only_skill_name_and_call_id():
    row = ht._skill_calls(json.dumps(_call()), 1780000000.0)[0]
    assert row == {"call_id": "c1", "timestamp": 1780000000.0,
                   "skill": "grounded-citations"}


@pytest.mark.unit
def test_ignores_other_functions_and_malformed_arguments():
    calls = _call("ok") + [{"id": "other", "function": {"name": "web_search",
        "arguments": "{}"}}, {"id": "bad", "function": {
        "name": "skill_view", "arguments": "not-json"}}]
    assert ht._skill_calls(json.dumps(calls), 1.0) == [
        {"call_id": "ok", "timestamp": 1.0, "skill": "grounded-citations"}
    ]


@pytest.mark.unit
def test_normalize_preserves_tool_day_and_adds_skill_day(monkeypatch):
    raw = [
        {"tool_name": "terminal", "timestamp": 1783771243.5},
        {"tool_name": "terminal", "timestamp": 1783771250.0},
        {"call_id": "c1", "timestamp": 1783670400.0, "skill": "a"},
        {"call_id": "c1", "timestamp": 1783670400.0, "skill": "a"},
    ]
    captured = []
    monkeypatch.setattr(ht, "read_raw", lambda _: raw)
    monkeypatch.setattr(ht, "write_clean", lambda source, table, ddl, rows, cols:
                        captured.append((table, rows, cols)) or len(rows))
    assert ht.normalize() == 1
    assert [item[0] for item in captured] == ["tool_day", "skill_day"]
    assert captured[0][2] == ("day", "tool_name", "n")
    assert captured[0][1] == [{"day": "2026-07-11", "tool_name": "terminal", "n": 2}]
    assert captured[1][2] == ("day", "skill", "n")
    assert captured[1][1] == [{"day": "2026-07-10", "skill": "a", "n": 1}]


@pytest.mark.unit
def test_missing_db_degrades(monkeypatch, tmp_path):
    monkeypatch.setattr(ht, "HERMES_STATE_DB", tmp_path / "missing.db")
    monkeypatch.setattr(ht, "query_ro", lambda *args: pytest.fail("must not query"))
    assert ht.collect() == 0
