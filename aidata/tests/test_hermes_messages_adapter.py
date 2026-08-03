"""Hermetic unit tests for adapters/hermes_messages.

Covers the `clarify` Q&A table added on top of the existing message collection,
plus the message-level behaviour that had no test file of its own.

The load-bearing rule here is the TIMEOUT SENTINEL: 104 of 225 real clarify
records (47%) are not answers at all — Hermes writes a sentinel string when I
never replied. Treating those as choices would invent decisions I never made,
which is worse than having no data.
"""

import json

import pytest

import adapters.hermes_messages as hm


def _clarify(question="选哪个?", choices=None, response="A", mid="m1",
             ts=1785000000.0):
    """A `tool_name='clarify'` raw record; content is a self-contained blob."""
    return {
        "id": mid,
        "session_id": "s1",
        "timestamp": ts,
        "role": "tool",
        "tool_name": "clarify",
        "content": json.dumps({
            "question": question,
            "choices_offered": ["A", "B"] if choices is None else choices,
            "user_response": response,
        }, ensure_ascii=False),
    }


# --------------------------------------------------------------------------- #
# The timeout sentinel — the whole reason this table needs a flag column
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_timeout_sentinel_is_flagged_not_stored_as_a_choice():
    row = hm._clarify_row(_clarify(
        response="The user did not provide a response within the time limit. "
                 "Use your best judgement..."))
    assert row["is_timeout"] == 1
    assert row["chosen"] is None, (
        "a timeout must not masquerade as an answer — that would fabricate a "
        "decision the user never made"
    )


@pytest.mark.unit
def test_real_answer_is_kept_and_not_flagged():
    row = hm._clarify_row(_clarify(response="B"))
    assert row["is_timeout"] == 0
    assert row["chosen"] == "B"


@pytest.mark.unit
def test_free_text_answer_survives():
    """~19% of real answers are typed, not picked — sometimes a counter-question."""
    row = hm._clarify_row(_clarify(response="之前的改动是为了什么？"))
    assert row["chosen"] == "之前的改动是为了什么？"
    assert row["is_timeout"] == 0
    assert row["chosen"] not in json.loads(row["options"]), (
        "chosen is not guaranteed to be one of the offered options"
    )


# --------------------------------------------------------------------------- #
# Parsing robustness — 2 of 225 real rows are unparseable
# --------------------------------------------------------------------------- #
@pytest.mark.unit
@pytest.mark.parametrize("rec", [
    {"id": "m1", "content": "not json"},
    {"id": "m1", "content": "[1,2,3]"},          # valid JSON, wrong shape
    {"id": "m1", "content": ""},
    {"id": "m1", "content": None},
    {"id": "m1"},                                 # no content at all
    {"content": json.dumps({"question": "q"})},   # no id
    {"id": "m1", "content": json.dumps({"choices_offered": []})},  # no question
])
def test_unparseable_rows_degrade_to_none(rec):
    """A malformed blob must not break the whole normalize (ADR-23)."""
    assert hm._clarify_row(rec) is None


@pytest.mark.unit
def test_missing_choices_becomes_empty_list():
    rec = {"id": "m1", "content": json.dumps({"question": "q",
                                              "user_response": "x"})}
    row = hm._clarify_row(rec)
    assert json.loads(row["options"]) == []


# --------------------------------------------------------------------------- #
# normalize wires both tables off ONE raw pass
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_normalize_builds_both_tables_without_recollecting(monkeypatch):
    records = [
        _clarify(mid="c1", response="A"),
        _clarify(mid="c2", response="The user did not provide a response "
                                    "within the time limit."),
        {"id": "m9", "session_id": "s1", "timestamp": 1785000001.0,
         "role": "user", "content": "普通消息"},
    ]
    monkeypatch.setattr(hm, "read_raw", lambda source: records)
    captured = {}

    def _cap(source, table, ddl, rows, cols):
        captured[table] = rows
        return len(rows)

    monkeypatch.setattr(hm, "write_clean", _cap)

    n = hm.normalize()
    assert n == 3, "normalize returns the MESSAGE count, not the clarify count"
    assert len(captured["clarify"]) == 2
    assert {r["ask_id"] for r in captured["clarify"]} == {"c1", "c2"}
    by_id = {r["ask_id"]: r for r in captured["clarify"]}
    assert by_id["c1"]["is_timeout"] == 0
    assert by_id["c2"]["is_timeout"] == 1
    # Clarify rows also remain in the message table — they are still messages.
    assert len(captured["message"]) == 3


@pytest.mark.unit
def test_non_clarify_tools_are_not_mined(monkeypatch):
    """Only `clarify` carries the Q&A blob; delegate_task must be ignored."""
    records = [{"id": "d1", "tool_name": "delegate_task", "role": "tool",
                "timestamp": 1785000000.0,
                "content": json.dumps({"question": "not a clarify"})}]
    monkeypatch.setattr(hm, "read_raw", lambda source: records)
    captured = {}
    monkeypatch.setattr(hm, "write_clean",
                        lambda s, t, d, rows, c: captured.setdefault(t, rows)
                        and 0 or len(rows))
    hm.normalize()
    assert captured["clarify"] == []


@pytest.mark.unit
def test_clarify_dedupes_on_id(monkeypatch):
    """read_raw yields oldest->newest, so a re-collected row must overwrite."""
    records = [_clarify(mid="c1", response="old"),
               _clarify(mid="c1", response="new")]
    monkeypatch.setattr(hm, "read_raw", lambda source: records)
    captured = {}
    monkeypatch.setattr(hm, "write_clean",
                        lambda s, t, d, rows, c: captured.setdefault(t, rows)
                        and 0 or len(rows))
    hm.normalize()
    assert len(captured["clarify"]) == 1
    assert captured["clarify"][0]["chosen"] == "new"


@pytest.mark.unit
def test_clarify_day_is_cst():
    """ADR-22: epoch seconds -> CST day via the shared helper, never localtime."""
    # 2026-08-02T20:00:00Z = 1785700800 -> CST 2026-08-03
    row = hm._clarify_row(_clarify(ts=1785700800))
    assert row["day"] == hm.epoch_s_to_cst_day(1785700800)
    assert row["agent"] == "hermes"


# --------------------------------------------------------------------------- #
# Message-level behaviour (no test file existed for this source before)
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_preview_is_bounded_and_length_is_original():
    length, preview = hm._preview("x" * 2000)
    assert length == 2000, "length must describe the ORIGINAL body"
    assert len(preview) == hm._PREVIEW_CHARS
    assert hm._preview(None) == (None, None)
    assert hm._preview("") == (None, None)


@pytest.mark.unit
def test_clean_schema_stores_no_full_body():
    """`content` totals ~506 MB across the table — previews only."""
    assert "content_preview" in hm._CLEAN_COLS
    assert "content_len" in hm._CLEAN_COLS
    assert "content" not in hm._CLEAN_COLS


@pytest.mark.unit
def test_collect_degrades_when_db_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(hm, "HERMES_STATE_DB", tmp_path / "nope.db")
    monkeypatch.setattr(hm, "query_ro",
                        lambda *a, **k: pytest.fail("must not query"))
    assert hm.collect() == 0


@pytest.mark.unit
def test_source_name_matches_module():
    assert hm.SOURCE == "hermes_messages"
