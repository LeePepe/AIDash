"""Hermetic unit tests for adapters/claude_jsonl — no real transcripts required.

Collect reads only temporary transcripts with injected raw and checkpoint sinks.
Normalization uses injected read_raw / write_clean to exercise token/tool fields.
"""

import json

import adapters.claude_jsonl as cj
import pytest


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


def _skill_line(uuid, blocks):
    line = _assistant_line(uuid, "end_turn")
    line["message"]["content"] = blocks
    return line


@pytest.mark.unit
def test_collect_reads_temp_log_and_resumes_after_malformed_records(tmp_path, monkeypatch):
    projects = tmp_path / "projects"
    projects.mkdir()
    log = projects / "session.jsonl"
    first = _assistant_line("first", "end_turn")
    first["message"]["content"].append({"type": "text", "text": "私密正文"})
    original = (
        json.dumps(first, ensure_ascii=False) + "\n"
        + '{malformed record}\n\n'
        + json.dumps({"type": "user", "message": {"content": "do not collect"}}) + "\n"
        + 'null\n[]\n'
    ).encode("utf-8")
    log.write_bytes(original)
    offsets = {}
    raw = []
    writes = []
    monkeypatch.setattr(cj, "CLAUDE_PROJECTS_DIR", projects)
    monkeypatch.setattr(cj, "get_watermark", lambda source: dict(offsets))

    def checkpoint(source, value):
        assert source == cj.SOURCE
        offsets.update(value)
        writes.append(dict(value))

    def append_raw(source, records):
        assert source == cj.SOURCE
        raw.extend(records)
        return len(records)

    monkeypatch.setattr(cj, "set_watermark", checkpoint)
    monkeypatch.setattr(cj, "write_raw", append_raw)

    assert cj.collect() == 1
    assert offsets == {str(log): len(original)}
    assert [row["uuid"] for row in raw] == ["first"]
    assert "私密正文" not in json.dumps(raw, ensure_ascii=False)
    assert cj.collect() == 0
    assert len(writes) == 1
    assert log.read_bytes() == original

    second = (json.dumps(_assistant_line("second", "tool_use")) + "\n").encode("utf-8")
    with log.open("ab") as handle:
        handle.write(second)
    assert cj.collect() == 1
    assert [row["uuid"] for row in raw] == ["first", "second"]
    assert offsets[str(log)] == len(original + second)
    assert log.read_bytes() == original + second
    assert cj.collect() == 0


@pytest.mark.unit
def test_collect_retains_incomplete_line_until_appended_newline(tmp_path, monkeypatch):
    log = tmp_path / "session.jsonl"
    record = json.dumps(_assistant_line("partial", "end_turn")).encode("utf-8")
    log.write_bytes(record[:40])
    offsets = {}
    raw = []
    monkeypatch.setattr(cj, "CLAUDE_PROJECTS_DIR", tmp_path)
    monkeypatch.setattr(cj, "get_watermark", lambda source: dict(offsets))
    monkeypatch.setattr(cj, "set_watermark", lambda source, value: offsets.update(value))
    monkeypatch.setattr(cj, "write_raw", lambda source, records: raw.extend(records) or len(records))

    assert cj.collect() == 0
    assert offsets == {}
    with log.open("ab") as handle:
        handle.write(record[40:] + b"\n")
    assert cj.collect() == 1
    assert offsets == {str(log): len(record) + 1}
    assert [row["uuid"] for row in raw] == ["partial"]


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
def test_slim_keeps_only_redacted_skill_inputs():
    slim = cj._slim(
        _skill_line(
            "skills-1",
            [
                {
                    "type": "tool_use",
                    "name": "Skill",
                    "input": {
                        "skill": "  $goal-target-task\n",
                        "args": "private prompt text that must not persist",
                    },
                },
                {
                    "type": "tool_use",
                    "name": "Read",
                    "input": {"skill": "not-a-skill-tool"},
                },
                {
                    "type": "tool_use",
                    "name": "Skill",
                    "input": {"skill": "x" * 200, "secret": "drop me"},
                },
            ],
        )
    )

    assert slim["skill_names"] == ["$goal-target-task", "x" * 128]
    assert all(len(skill) <= 128 for skill in slim["skill_names"])
    assert "args" not in slim
    assert "secret" not in slim
    assert "not-a-skill-tool" not in slim["skill_names"]


@pytest.mark.unit
def test_normalize_serializes_skill_names_as_json(monkeypatch):
    raw = [cj._slim(_skill_line("skills-1", [{
        "type": "tool_use",
        "name": "Skill",
        "input": {"skill": "alpha"},
    }]))]
    monkeypatch.setattr(cj, "read_raw", lambda source: raw)
    captured = {}
    monkeypatch.setattr(
        cj,
        "write_clean",
        lambda source, table, ddl, rows, cols: captured.setdefault("rows", rows),
    )

    cj.normalize()

    assert captured["rows"][0]["skill_names"] == '["alpha"]'


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
