"""Hermetic unit tests for adapters/claude_prompts — no real transcripts needed.

The heart of this source is the discriminator: which "user" lines are things a
human actually typed, versus tool output, subagent prompts, and harness
injections wearing the user role. Corpus-wide only ~6.6% of user lines survive,
so a filter that is too loose silently corrupts the answer to "what did I send".
These tests pin each rule to a concrete case.
"""

import json

import pytest

import adapters.claude_prompts as cp


def _user(text_or_blocks, **kw):
    """A `type=user` transcript line with sensible interactive defaults."""
    line = {
        "type": "user",
        "uuid": kw.pop("uuid", "u1"),
        "sessionId": kw.pop("session", "s1"),
        "timestamp": kw.pop("ts", "2026-08-03T04:00:00.000Z"),
        "cwd": "/repo",
        "gitBranch": "main",
        "entrypoint": kw.pop("entrypoint", "cli"),
        "isSidechain": kw.pop("sidechain", False),
        "isMeta": kw.pop("meta", False),
        "message": {"content": text_or_blocks},
    }
    line.update(kw)
    return line


# --------------------------------------------------------------------------- #
# _text_of — is there human-authored text on this line at all?
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_text_of_accepts_plain_string():
    assert cp._text_of("commit 然后 push") == "commit 然后 push"


@pytest.mark.unit
def test_text_of_rejects_any_tool_result():
    """93.4% of user lines are tool output — a tool_result anywhere disqualifies."""
    assert cp._text_of([{"type": "tool_result", "content": "ok"}]) is None
    # Mixed block lists must ALSO be rejected, not partially harvested: the text
    # block there is the harness framing the tool output, not the user talking.
    assert cp._text_of([
        {"type": "text", "text": "here it is"},
        {"type": "tool_result", "content": "ok"},
    ]) is None


@pytest.mark.unit
def test_text_of_joins_text_blocks():
    assert cp._text_of([
        {"type": "text", "text": "line1"},
        {"type": "text", "text": "line2"},
    ]) == "line1\nline2"


@pytest.mark.unit
def test_text_of_handles_junk():
    assert cp._text_of(None) is None
    assert cp._text_of([]) is None
    assert cp._text_of([{"type": "image"}]) is None
    assert cp._text_of(["not-a-dict"]) is None


# --------------------------------------------------------------------------- #
# _classify — never promote something uncertain to `typed`
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_classify_typed_is_the_narrow_case():
    assert cp._classify("重新 build 一下", "cli", False, False) == "typed"


@pytest.mark.unit
@pytest.mark.parametrize("entrypoint,sidechain,meta,expected", [
    ("sdk-cli", False, False, "agent_authored"),  # programmatic `claude -p`
    ("cli", True, False, "agent_authored"),       # subagent Task prompt
    ("cli", False, True, "injected"),             # harness-injected
])
def test_classify_structural_filters(entrypoint, sidechain, meta, expected):
    assert cp._classify("looks human", entrypoint, sidechain, meta) == expected


@pytest.mark.unit
@pytest.mark.parametrize("text,expected", [
    ("<task-notification>\n<task-id>abc</task-id>", "task_notification"),
    ("<command-name>/clear</command-name>", "slash_command"),
    ("<bash-input> gh pr create", "bash_io"),
    ("[Request interrupted by user for tool use]", "interrupted"),
    ("<local-command-stdout>(no content)</local-command-stdout>", "local_command"),
    ("[Image: original 1179x2556]", "image"),
    ("This session is being continued from a previous", "compact_resume"),
    ("<some-other-tag>x</some-other-tag>", "injected"),
])
def test_classify_wrappers(text, expected):
    assert cp._classify(text, "cli", False, False) == expected


@pytest.mark.unit
def test_classify_unknown_entrypoint_is_not_typed():
    """An unproven line must land in `unknown`, never be upgraded to `typed`.

    Mislabelling here is the failure that matters: it puts machine text into
    the corpus of "things I said" with no way to tell afterwards.
    """
    assert cp._classify("plain text", None, False, False) == "unknown"
    assert cp._classify("plain text", "future-mode", False, False) == "unknown"


# --------------------------------------------------------------------------- #
# collect — offsets are this source's OWN, independent of claude_jsonl
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_collect_degrades_when_dir_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(cp, "CLAUDE_PROJECTS_DIR", tmp_path / "nope")
    monkeypatch.setattr(cp, "write_raw",
                        lambda *a, **k: pytest.fail("must not write"))
    assert cp.collect() == 0


@pytest.mark.unit
def test_collect_keeps_human_lines_and_skips_tool_results(monkeypatch, tmp_path):
    transcript = tmp_path / "proj" / "s1.jsonl"
    transcript.parent.mkdir(parents=True)
    transcript.write_text("\n".join(json.dumps(o) for o in [
        _user("真人输入", uuid="u-human"),
        _user([{"type": "tool_result", "content": "SECRET-TOOL-OUTPUT"}], uuid="u-tool"),
        {"type": "assistant", "uuid": "a1", "message": {"content": []}},
    ]) + "\n", encoding="utf-8")

    monkeypatch.setattr(cp, "CLAUDE_PROJECTS_DIR", tmp_path)
    monkeypatch.setattr(cp, "get_watermark", lambda source: None)
    captured = {}
    monkeypatch.setattr(cp, "write_raw",
                        lambda source, records: captured.setdefault("recs", list(records)) and 0
                        or len(captured["recs"]))
    monkeypatch.setattr(cp, "set_watermark",
                        lambda source, value: captured.__setitem__("wm", value))

    n = cp.collect()
    assert n == 1
    assert captured["recs"][0]["uuid"] == "u-human"
    # Tool output must never reach raw/ through this source.
    assert "SECRET-TOOL-OUTPUT" not in repr(captured["recs"])
    # Offset advanced to EOF so the next run re-reads nothing.
    assert captured["wm"][str(transcript)] == transcript.stat().st_size


@pytest.mark.unit
def test_collect_resumes_from_offset(monkeypatch, tmp_path):
    transcript = tmp_path / "s.jsonl"
    first = json.dumps(_user("old", uuid="u-old")) + "\n"
    transcript.write_text(first + json.dumps(_user("new", uuid="u-new")) + "\n",
                          encoding="utf-8")
    monkeypatch.setattr(cp, "CLAUDE_PROJECTS_DIR", tmp_path)
    monkeypatch.setattr(cp, "get_watermark",
                        lambda source: {str(transcript): len(first.encode())})
    captured = {}
    monkeypatch.setattr(cp, "write_raw",
                        lambda source, records: captured.setdefault("recs", list(records))
                        and 0 or len(captured["recs"]))
    monkeypatch.setattr(cp, "set_watermark", lambda source, value: None)

    assert cp.collect() == 1
    assert captured["recs"][0]["uuid"] == "u-new"


# --------------------------------------------------------------------------- #
# AskUserQuestion — question/answer pairing
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_asks_guard_against_str_questions():
    """`input.questions` arrives as a raw str in ~75/1117 real invocations."""
    line = {
        "type": "assistant", "sessionId": "s1", "timestamp": "2026-08-03T00:00:00Z",
        "message": {"content": [{
            "type": "tool_use", "id": "t1", "name": "AskUserQuestion",
            "input": {"questions": "truncated-streaming-garbage"},
        }]},
    }
    assert cp._asks_from_assistant(line) == []


@pytest.mark.unit
def test_answers_read_structured_field_not_prose():
    """Use toolUseResult.answers; the prose form is ambiguous to parse."""
    line = _user([{"type": "tool_result", "tool_use_id": "t1",
                   "content": 'Your questions have been answered: "Q"="A".'}])
    line["toolUseResult"] = {"answers": {"用哪种机制?": "GitHub Actions + Claude"}}
    got = cp._answers_from_user(line)
    assert got["tool_use_id"] == "t1"
    assert got["answers"] == {"用哪种机制?": "GitHub Actions + Claude"}


@pytest.mark.unit
def test_normalize_pairs_ask_with_chosen_answer(monkeypatch):
    records = [
        {"kind": "ask", "tool_use_id": "t1", "sessionId": "s1",
         "timestamp": "2026-08-03T04:00:00Z",
         "questions": [{"question": "用哪种?",
                        "options": [{"label": "A"}, {"label": "B"}]}]},
        {"kind": "answer", "tool_use_id": "t1", "sessionId": "s1",
         "timestamp": "2026-08-03T04:01:00Z", "answers": {"用哪种?": "B"}},
    ]
    monkeypatch.setattr(cp, "read_raw", lambda source: records)
    captured = {}

    def _cap(source, table, ddl, rows, cols):
        captured[table] = rows
        return len(rows)

    monkeypatch.setattr(cp, "write_clean", _cap)
    cp.normalize()
    ask = captured["ask"][0]
    assert ask["question"] == "用哪种?"
    assert json.loads(ask["options"]) == ["A", "B"]
    assert ask["chosen"] == "B"
    assert ask["is_timeout"] == 0


@pytest.mark.unit
def test_normalize_keeps_free_text_answers(monkeypatch):
    """~22% of answers are typed, not picked — sometimes a counter-question."""
    records = [
        {"kind": "ask", "tool_use_id": "t1", "sessionId": "s1",
         "timestamp": "2026-08-03T04:00:00Z",
         "questions": [{"question": "选哪个?", "options": [{"label": "A"}]}]},
        {"kind": "answer", "tool_use_id": "t1", "sessionId": "s1",
         "timestamp": "2026-08-03T04:01:00Z",
         "answers": {"选哪个?": "之前的改动是为了什么？"}},
    ]
    monkeypatch.setattr(cp, "read_raw", lambda source: records)
    captured = {}
    monkeypatch.setattr(cp, "write_clean",
                        lambda s, t, d, rows, c: captured.setdefault(t, rows) and 0 or len(rows))
    cp.normalize()
    assert captured["ask"][0]["chosen"] == "之前的改动是为了什么？"


@pytest.mark.unit
def test_normalize_unanswered_ask_has_null_chosen(monkeypatch):
    """Questions asked but abandoned (~half of invocations) keep chosen=NULL."""
    records = [{"kind": "ask", "tool_use_id": "t9", "sessionId": "s1",
                "timestamp": "2026-08-03T04:00:00Z",
                "questions": [{"question": "在吗?", "options": []}]}]
    monkeypatch.setattr(cp, "read_raw", lambda source: records)
    captured = {}
    monkeypatch.setattr(cp, "write_clean",
                        lambda s, t, d, rows, c: captured.setdefault(t, rows) and 0 or len(rows))
    cp.normalize()
    assert captured["ask"][0]["chosen"] is None


# --------------------------------------------------------------------------- #
# normalize — the prompt table
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_normalize_prompt_row_shape(monkeypatch):
    long_text = "x" * 900
    records = [{"kind": "prompt", "uuid": "u1", "sessionId": "s1",
                "timestamp": "2026-08-03T04:00:00.000Z", "cwd": "/repo",
                "gitBranch": "main", "entrypoint": "cli",
                "isSidechain": False, "isMeta": False, "text": long_text}]
    monkeypatch.setattr(cp, "read_raw", lambda source: records)
    captured = {}
    monkeypatch.setattr(cp, "write_clean",
                        lambda s, t, d, rows, c: captured.setdefault(t, rows) and 0 or len(rows))
    cp.normalize()
    row = captured["prompt"][0]
    assert row["agent"] == "claude"
    assert row["source_kind"] == "typed"
    assert row["text_len"] == 900, "length must describe the ORIGINAL"
    assert len(row["text_preview"]) == cp._PREVIEW_CHARS
    assert len(row["prefix_100"]) == cp._PREFIX_CHARS
    assert row["day"] == "2026-08-03"  # 04:00Z -> 12:00 CST, same day


@pytest.mark.unit
def test_cst_day_crosses_midnight_correctly():
    """ADR-22: fixed +8h. 20:00Z belongs to the NEXT CST day."""
    assert cp._cst_day("2026-08-02T20:00:00.000Z") == "2026-08-03"
    assert cp._cst_day("2026-08-02T15:59:00.000Z") == "2026-08-02"
    assert cp._cst_day(None) is None
    assert cp._cst_day("garbage") is None


@pytest.mark.unit
def test_normalize_dedupes_on_uuid(monkeypatch):
    """read_raw yields oldest->newest, so a re-collected line must overwrite."""
    records = [
        {"kind": "prompt", "uuid": "u1", "text": "old", "entrypoint": "cli",
         "timestamp": "2026-08-03T04:00:00Z"},
        {"kind": "prompt", "uuid": "u1", "text": "new", "entrypoint": "cli",
         "timestamp": "2026-08-03T04:00:00Z"},
    ]
    monkeypatch.setattr(cp, "read_raw", lambda source: records)
    captured = {}
    monkeypatch.setattr(cp, "write_clean",
                        lambda s, t, d, rows, c: captured.setdefault(t, rows) and 0 or len(rows))
    n = cp.normalize()
    assert n == 1
    assert captured["prompt"][0]["text_preview"] == "new"


@pytest.mark.unit
def test_source_name_matches_module():
    assert cp.SOURCE == "claude_prompts"
