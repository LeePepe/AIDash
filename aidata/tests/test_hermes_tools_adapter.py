"""Hermetic tests for Hermes skill-view extraction."""

import json
import sqlite3

import adapters.hermes_tools as ht
import pytest


def _call(call_id="c1", skill="grounded-citations"):
    return [{"id": call_id, "type": "function", "function": {
        "name": "skill_view", "arguments": json.dumps({"name": skill})
    }}]


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
def test_collect_reads_assistant_tool_calls_without_message_bodies(monkeypatch, tmp_path):
    db = tmp_path / "state.db"
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE messages (role TEXT, timestamp REAL, tool_calls TEXT, content TEXT)")
    con.execute("INSERT INTO messages VALUES (?, ?, ?, ?)",
                ("assistant", 10.0, json.dumps(_call()), "PRIVATE BODY"))
    con.execute("INSERT INTO messages VALUES (?, ?, ?, ?)",
                ("user", 11.0, json.dumps(_call("u1")), "PRIVATE BODY"))
    con.commit()
    con.close()
    captured = {}
    monkeypatch.setattr(ht, "HERMES_STATE_DB", db)
    monkeypatch.setattr(ht, "get_watermark", lambda _: 0)
    def capture_raw(source, rows):
        captured["rows"] = list(rows)
        return len(captured["rows"])
    monkeypatch.setattr(ht, "write_raw", capture_raw)
    monkeypatch.setattr(ht, "set_watermark", lambda source, value: captured.__setitem__("watermark", value))
    assert ht.collect() == 1
    assert captured["rows"] == [{"call_id": "c1", "timestamp": 10.0,
                                  "skill": "grounded-citations"}]
    assert captured["watermark"] == 10.0


@pytest.mark.unit
def test_normalize_dedupes_call_ids_and_buckets_cst(monkeypatch):
    raw = [{"call_id": "c1", "timestamp": 1783670400.0, "skill": "a"},
           {"call_id": "c1", "timestamp": 1783670400.0, "skill": "a"},
           {"call_id": "c2", "timestamp": 1783699200.0, "skill": "a"}]
    captured = {}
    monkeypatch.setattr(ht, "read_raw", lambda _: raw)
    monkeypatch.setattr(ht, "write_clean", lambda s, t, d, rows, cols:
                        captured.update(table=t, rows=rows, cols=cols) or len(rows))
    assert ht.normalize() == 2
    assert captured["table"] == "skill_day"
    assert {(r["day"], r["skill"]): r["n"] for r in captured["rows"]} == {
        ("2026-07-10", "a"): 1, ("2026-07-11", "a"): 1}


@pytest.mark.unit
def test_missing_db_degrades(monkeypatch, tmp_path):
    monkeypatch.setattr(ht, "HERMES_STATE_DB", tmp_path / "missing.db")
    monkeypatch.setattr(ht, "query_ro", lambda *args: pytest.fail("must not query"))
    assert ht.collect() == 0
