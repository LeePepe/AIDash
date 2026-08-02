"""Hermetic unit tests for adapters/claude_jsonl — no real transcripts required.

read_raw / write_clean are monkeypatched so the finish_reason extraction (from
message.stop_reason through collect's _slim into the clean `turn` row) is proven
deterministically, alongside the existing token/tool columns.
"""

import pytest

import adapters.claude_jsonl as cj


def _assistant_line(uuid, stop_reason, **usage):
    """A minimal Claude Code assistant transcript line."""
    return {
        "type": "assistant",
        "uuid": uuid,
        "sessionId": "sess-A",
        "timestamp": "2026-07-27T01:02:03.456Z",
        "cwd": "/Users/me/Development/AIDash",
        "gitBranch": "main",
        "message": {
            "role": "assistant",
            "model": "claude-opus-4-8",
            "stop_reason": stop_reason,
            "usage": {
                "input_tokens": usage.get("input", 10),
                "output_tokens": usage.get("output", 5),
                "cache_read_input_tokens": usage.get("cache_read", 100),
                "cache_creation_input_tokens": usage.get("cache_creation", 20),
            },
            "content": [{"type": "tool_use", "name": "Read"}],
        },
    }


@pytest.mark.unit
def test_slim_keeps_stop_reason():
    slim = cj._slim(_assistant_line("u1", "max_tokens"))
    # collect's _slim must preserve stop_reason into raw (it is the upstream of
    # normalize's finish_reason); previously it was dropped.
    assert slim["stop_reason"] == "max_tokens"
    # existing fields still intact
    assert slim["uuid"] == "u1"
    assert slim["sessionId"] == "sess-A"
    assert slim["tool_calls"] == ["Read"]
    assert slim["usage"]["cache_read_input_tokens"] == 100


@pytest.mark.unit
def test_slim_stop_reason_nullable():
    # streaming/control assistant frames may omit stop_reason -> None, not error.
    line = _assistant_line("u2", None)
    del line["message"]["stop_reason"]
    slim = cj._slim(line)
    assert slim["stop_reason"] is None


@pytest.mark.unit
def test_normalize_extracts_finish_reason(monkeypatch):
    raw = [
        cj._slim(_assistant_line("u1", "end_turn")),
        cj._slim(_assistant_line("u2", "tool_use")),
        cj._slim(_assistant_line("u3", "max_tokens")),
        cj._slim(_assistant_line("u4", None)),
    ]
    monkeypatch.setattr(cj, "read_raw", lambda source: raw)
    captured = {}

    def _cap_clean(source, table, ddl, rows, cols):
        captured["rows"] = {r["turn_uuid"]: r for r in rows}
        captured["cols"] = cols
        captured["ddl"] = ddl
        return len(rows)

    monkeypatch.setattr(cj, "write_clean", _cap_clean)
    n = cj.normalize()
    assert n == 4
    # column is declared in both the DDL and the insert column list
    assert "finish_reason" in captured["cols"]
    assert "finish_reason TEXT" in captured["ddl"]
    # value comes straight from raw stop_reason
    assert captured["rows"]["u1"]["finish_reason"] == "end_turn"
    assert captured["rows"]["u2"]["finish_reason"] == "tool_use"
    assert captured["rows"]["u3"]["finish_reason"] == "max_tokens"
    # NULL survives as None (not coerced)
    assert captured["rows"]["u4"]["finish_reason"] is None
    # existing columns untouched
    r1 = captured["rows"]["u1"]
    assert r1["project"] == "AIDash"
    assert r1["cache_read"] == 100
    assert r1["model"] == "claude-opus-4-8"


@pytest.mark.unit
def test_normalize_dedupes_on_uuid(monkeypatch):
    raw = [
        cj._slim(_assistant_line("dup", "end_turn")),
        cj._slim(_assistant_line("dup", "max_tokens")),  # same uuid -> wins
    ]
    monkeypatch.setattr(cj, "read_raw", lambda source: raw)
    captured = {}
    monkeypatch.setattr(
        cj, "write_clean",
        lambda source, table, ddl, rows, cols: captured.setdefault("rows", rows),
    )
    cj.normalize()
    assert len(captured["rows"]) == 1
    # last-write-wins: read_raw yields shards oldest->newest, so a newer record
    # for the same turn overwrites an older one. Critical for full re-collect
    # backfill — the newer shard carries fields the old parser dropped.
    assert captured["rows"][0]["finish_reason"] == "max_tokens"
