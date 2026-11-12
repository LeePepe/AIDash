"""Hermetic unit tests for the Hermes tool and skill streams."""

import json
import sqlite3
from pathlib import Path

import adapters.copilot_cli as copilot
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


@pytest.mark.unit
def test_copilot_collects_skill_metadata_without_prompt_bodies(monkeypatch, tmp_path):
    db = tmp_path / "session-store.db"
    with sqlite3.connect(db) as con:
        con.execute("CREATE TABLE turns (id INTEGER PRIMARY KEY, session_id TEXT, timestamp TEXT, assistant_response TEXT)")
        con.execute("INSERT INTO turns VALUES (1, 's1', '2026-11-12T01:00:00Z', '/skill team-lead SECRET_PROMPT')")
        con.commit()
    captured = []
    monkeypatch.setattr(copilot, "COPILOT_SESSION_DB", db)
    monkeypatch.setattr(copilot, "write_raw", lambda source, rows: captured.extend(rows) or len(rows))
    monkeypatch.setattr(copilot, "get_watermark", lambda source: 0)
    monkeypatch.setattr(copilot, "set_watermark", lambda source, value: None)
    assert copilot.collect() == 1
    assert len(captured) == 1
    assert {key: captured[0][key] for key in ("turn_id", "session_id", "timestamp", "skill")} == {"turn_id": 1, "session_id": "s1", "timestamp": "2026-11-12T01:00:00Z", "skill": "team-lead"}
    assert "SECRET_PROMPT" not in repr(captured)


@pytest.mark.unit
@pytest.mark.parametrize("omit", [None, "turns", "session_files"])
def test_copilot_real_skill_markers_are_bounded_metadata_and_deduped(tmp_path, monkeypatch, omit):
    from datetime import datetime, timezone

    db = tmp_path / "copilot.db"
    with sqlite3.connect(db) as con:
        if omit != "turns":
            con.execute("CREATE TABLE turns (id INTEGER PRIMARY KEY, session_id TEXT, turn_index INTEGER, timestamp TEXT, user_message TEXT, assistant_response TEXT)")
            con.executemany("INSERT INTO turns VALUES (?, ?, ?, ?, ?, ?)", [
                (1, "s1", 0, "2026-11-12T01:00:00Z", '<skill-context name="team-lead">SECRET_BODY</skill-context>', '/Users/test/.copilot/skills/team-lead/SKILL.md SECRET_REPLY'),
                (2, "s1", 1, "2026-11-12T02:00:00Z", "read /Users/test/.agents/skills/aidash-content/SKILL.md", '<skill-context name="aidash-content">'),
                (3, "old", 0, "2025-01-01T00:00:00Z", '<skill-context name="old-skill">', ""),
                (4, "ordinary", 0, "2026-11-12T01:00:00Z", "skillful prose /skills is not an invocation", ""),
            ])
        if omit != "session_files":
            con.execute("CREATE TABLE session_files (session_id TEXT, file_path TEXT, tool_name TEXT, turn_index INTEGER, first_seen_at TEXT)")
            con.executemany("INSERT INTO session_files VALUES (?, ?, ?, ?, ?)", [
                ("s1", "/Users/test/.copilot/skills/team-lead/SKILL.md", "view", 0, "2026-11-12T01:00:01Z"),
                ("s1", "/Users/test/.copilot/skills/team-lead/SKILL.md", "view", 0, "2026-11-12T01:00:02Z"),
                ("s2", "/Users/test/.agents/skills/retro-loop/SKILL.md", "view", 2, "2026-11-12T03:00:00Z"),
                ("old", "/Users/test/skills/old-skill/SKILL.md", "view", 0, "2025-01-01T00:00:00Z"),
            ])
    before = db.read_bytes()
    raw, checkpoints = [], {}
    monkeypatch.setattr(copilot, "COPILOT_SESSION_DB", db)
    monkeypatch.setattr(copilot, "get_watermark", lambda _: dict(checkpoints))
    monkeypatch.setattr(copilot, "set_watermark", lambda _, value: checkpoints.update(value))
    monkeypatch.setattr(copilot, "write_raw", lambda _, rows: raw.extend(rows) or len(rows))
    now = datetime(2026, 11, 12, 12, tzinfo=timezone.utc)  # noqa: UP017 - hook Python 3.9
    expected = {"team-lead", "aidash-content", "retro-loop"}
    if omit == "turns":
        expected.remove("aidash-content")
    if omit == "session_files":
        expected.remove("retro-loop")
    assert copilot.collect(now=now) == len(expected)
    assert {row["skill"] for row in raw} == expected
    assert len({row["event_id"] for row in raw}) == len(expected)
    assert all(row["timestamp"].startswith("2026-11-12") for row in raw)
    assert "SECRET" not in repr(raw)
    assert "/Users/test" not in repr(raw)
    assert copilot.collect(now=now) == 0
    assert db.read_bytes() == before
    monkeypatch.setattr(copilot, "read_raw", lambda _: raw + raw)
    clean = []
    monkeypatch.setattr(copilot, "write_clean", lambda source, table, ddl, rows, cols: clean.extend(rows) or len(rows))
    assert copilot.normalize() == len(expected)
    assert all(row["n"] == 1 for row in clean)
