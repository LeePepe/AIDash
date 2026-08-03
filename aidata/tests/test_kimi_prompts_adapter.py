"""Hermetic unit tests for adapters/kimi_prompts.

Kimi is the one source with an explicit provenance field, so these tests focus
on trusting it correctly — and on the unit trap: Kimi records epoch
MILLISECONDS while the Hermes sources record seconds. Mixing them silently
yields dates decades off.
"""

import json

import pytest

import adapters.kimi_prompts as kp


def _prompt(text="真人输入", kind="user", time_ms=1785700800000):
    return json.dumps({
        "type": "turn.prompt",
        "input": [{"type": "text", "text": text}],
        "origin": {"kind": kind},
        "time": time_ms,
    })


# --------------------------------------------------------------------------- #
# origin.kind — the discriminator, trusted directly
# --------------------------------------------------------------------------- #
@pytest.mark.unit
@pytest.mark.parametrize("kind,expected,keeps_body", [
    ("user", "typed", True),
    ("system_trigger", "agent_authored", False),
    ("background_task", "agent_authored", False),
    ("injection", "injected", False),
    ("skill_activation", "injected", False),
    ("shell_command", "bash_io", False),
])
def test_origin_kind_maps_to_source_kind(kind, expected, keeps_body):
    row = kp._row({"id": "p1", "text": "x" * 900, "origin_kind": kind,
                   "time": 1785700800000})
    assert row["source_kind"] == expected
    assert (row["text_preview"] is not None) is keeps_body
    # The raw tag is kept verbatim so a mapping change can be re-derived.
    assert row["origin_kind"] == kind


@pytest.mark.unit
def test_unmapped_origin_is_unknown_not_typed():
    """A provenance value Kimi adds later must not be assumed to be human."""
    row = kp._row({"id": "p1", "text": "t", "origin_kind": "future_kind",
                   "time": 1785700800000})
    assert row["source_kind"] == "unknown"
    assert row["text_preview"] is None
    row_missing = kp._row({"id": "p2", "text": "t", "time": 1785700800000})
    assert row_missing["source_kind"] == "unknown"


# --------------------------------------------------------------------------- #
# The unit trap — Kimi is milliseconds, the Hermes sources are seconds
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_timestamps_are_milliseconds():
    """1785700800000 ms = 2026-08-02T20:00:00Z -> CST 2026-08-03.

    Feeding the same number to a seconds-based helper would land ~55,000 years
    out; feeding seconds to this one lands in 1970. Both fail silently, so the
    unit is pinned here.
    """
    assert kp._cst_day(1785700800000) == "2026-08-03"
    # 2026-08-02T15:59:00Z -> still 2026-08-02 in CST
    assert kp._cst_day(1785686340000) == "2026-08-02"
    assert kp._cst_day(None) is None
    assert kp._cst_day(0) is None
    assert kp._cst_day(-5) is None


@pytest.mark.unit
def test_ts_column_is_stored_in_seconds():
    """Cross-agent ordering breaks if one source stores a different unit."""
    row = kp._row({"id": "p1", "text": "t", "origin_kind": "user",
                   "time": 1785700800000})
    assert row["ts"] == 1785700800.0


# --------------------------------------------------------------------------- #
# _text_of
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_text_of_joins_blocks_and_rejects_junk():
    assert kp._text_of([{"type": "text", "text": "a"},
                        {"type": "text", "text": "b"}]) == "a\nb"
    assert kp._text_of([{"type": "image"}]) is None
    assert kp._text_of([]) is None
    assert kp._text_of(None) is None
    assert kp._text_of("not a list") is None
    assert kp._text_of([{"type": "text", "text": ""}]) is None


# --------------------------------------------------------------------------- #
# collect
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_collect_degrades_when_dir_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(kp, "KIMI_SESSIONS_DIR", tmp_path / "nope")
    monkeypatch.setattr(kp, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("must not write"))
    assert kp.collect() == 0


@pytest.mark.unit
def test_collect_reads_wire_and_derives_session_id(monkeypatch, tmp_path):
    wire = tmp_path / "wd_x" / "session_abc" / "agents" / "main" / "wire.jsonl"
    wire.parent.mkdir(parents=True)
    wire.write_text("\n".join([
        _prompt("我的输入", kind="user"),
        _prompt("子 agent 派的", kind="system_trigger"),
        json.dumps({"type": "llm.request", "time": 1}),   # ignored
        "not json",                                        # tolerated
    ]) + "\n", encoding="utf-8")

    monkeypatch.setattr(kp, "KIMI_SESSIONS_DIR", tmp_path)
    captured = {}
    monkeypatch.setattr(kp, "write_raw_snapshot",
                        lambda s, records: captured.setdefault("recs", records)
                        and 0 or len(records))

    assert kp.collect() == 2
    recs = captured["recs"]
    assert all(r["session_id"] == "session_abc" for r in recs)
    assert {r["origin_kind"] for r in recs} == {"user", "system_trigger"}


@pytest.mark.unit
def test_collect_is_empty_when_no_prompts(monkeypatch, tmp_path):
    wire = tmp_path / "s" / "agents" / "main" / "wire.jsonl"
    wire.parent.mkdir(parents=True)
    wire.write_text(json.dumps({"type": "usage.record"}) + "\n", encoding="utf-8")
    monkeypatch.setattr(kp, "KIMI_SESSIONS_DIR", tmp_path)
    monkeypatch.setattr(kp, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("no write when nothing found"))
    assert kp.collect() == 0


# --------------------------------------------------------------------------- #
# normalize
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_normalize_dedupes_on_id(monkeypatch):
    records = [
        {"id": "p1", "text": "old", "origin_kind": "user", "time": 1785700800000},
        {"id": "p1", "text": "new", "origin_kind": "user", "time": 1785700800000},
    ]
    monkeypatch.setattr(kp, "read_raw", lambda source: records)
    captured = {}
    monkeypatch.setattr(kp, "write_clean",
                        lambda s, t, d, rows, c: captured.setdefault("rows", rows)
                        and 0 or len(rows))
    assert kp.normalize() == 1
    assert captured["rows"][0]["text_preview"] == "new"


@pytest.mark.unit
def test_row_rejects_empty():
    assert kp._row({"id": "p", "text": ""}) is None
    assert kp._row({"id": "p", "text": None}) is None
    assert kp._row({"text": "no id"}) is None


@pytest.mark.unit
def test_source_name_matches_module():
    assert kp.SOURCE == "kimi_prompts"
