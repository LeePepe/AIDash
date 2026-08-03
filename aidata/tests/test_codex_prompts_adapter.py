"""Hermetic unit tests for adapters/codex_prompts — no real session logs needed.

The defining behaviour here is the TIER SPLIT: 87% of Codex sessions are driven
by automation, not by me, and the two populations are stored differently (my
prompts keep a body preview; machine prompts keep only a grouping hash). These
tests pin the split, the grouping key, and the resume path that could silently
break it.
"""

import json

import pytest

import adapters.codex_prompts as cx


def _meta(originator="codex-tui", session="sess-1"):
    return json.dumps({
        "type": "session_meta",
        "timestamp": "2026-08-03T04:00:00.000Z",
        "payload": {"id": session, "originator": originator,
                    "source": "cli", "cwd": "/repo"},
    })


def _user_msg(text, ts="2026-08-03T04:01:00.000Z"):
    return json.dumps({
        "timestamp": ts,
        "type": "event_msg",
        "payload": {"type": "user_message", "message": text},
    })


# --------------------------------------------------------------------------- #
# Reading the right record type
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_user_message_only_matches_the_event():
    assert cx._user_message(json.loads(_user_msg("hi"))) == "hi"
    # response_item also carries user text but includes AGENTS.md dumps and
    # <environment_context> injections — deliberately not read here.
    assert cx._user_message({
        "type": "response_item",
        "payload": {"type": "message", "role": "user", "content": "injected"},
    }) is None
    assert cx._user_message({"type": "event_msg",
                             "payload": {"type": "token_count"}}) is None
    assert cx._user_message({"type": "event_msg",
                             "payload": {"type": "user_message",
                                         "message": ""}}) is None


@pytest.mark.unit
def test_session_meta_parsing_and_degradation():
    got = cx._session_meta(_meta(originator="Codex Desktop", session="s9"))
    assert got["originator"] == "Codex Desktop"
    assert got["session_id"] == "s9"
    # A non-meta or unparseable first line must not raise — the file is still
    # collected, just without originator (rows then fall to tier B).
    assert cx._session_meta("not json") == {}
    assert cx._session_meta(_user_msg("x")) == {}


# --------------------------------------------------------------------------- #
# The tier split — the whole point of this source
# --------------------------------------------------------------------------- #
@pytest.mark.unit
@pytest.mark.parametrize("originator,kind,keeps_body", [
    ("codex-tui", "typed", True),            # me, terminal
    ("Codex Desktop", "typed", True),        # me, desktop
    ("multica-agent-sdk", "agent_authored", False),
    ("codex_exec", "agent_authored", False),  # documented blind spot
    ("Claude Code", "agent_authored", False),
    (None, "agent_authored", False),          # unknown -> conservative
])
def test_tier_split(originator, kind, keeps_body):
    row = cx._row({"id": "p1", "text": "x" * 900, "originator": originator,
                   "timestamp": "2026-08-03T04:00:00Z"})
    assert row["source_kind"] == kind
    if keeps_body:
        assert len(row["text_preview"]) == cx._PREVIEW_CHARS
    else:
        assert row["text_preview"] is None, "tier B must store no body"
    # Both tiers keep length + grouping key regardless.
    assert row["text_len"] == 900
    assert row["prompt_sha"] and row["prefix_100"]


@pytest.mark.unit
@pytest.mark.parametrize("text,expected", [
    ("<command-name>/clear</command-name>", "slash_command"),
    ("[Request interrupted by user]", "interrupted"),
    ("<task-notification>x", "task_notification"),
    ("<bash-input> ls", "bash_io"),
    ("# AGENTS.md instructions for /repo", "injected"),
    ("You are running as a local coding agent for a Multica workspace.", "injected"),
])
def test_wrappers_demoted_even_in_interactive_sessions(text, expected):
    """The CLI submits these on my behalf inside real interactive sessions.

    Measured on live data: 220 of 583 originator-interactive records (38%) were
    one of these. Labelling them `typed` would put a large amount of machine
    text into "things I said" — the exact corruption this source exists to
    prevent.
    """
    assert cx._classify(text, "codex-tui") == expected


@pytest.mark.unit
def test_originator_still_dominates_classification():
    """A machine session stays tier B no matter how human its text looks."""
    assert cx._classify("这看起来像人话", "multica-agent-sdk") == "agent_authored"


@pytest.mark.unit
def test_originator_is_retained_for_reclassification():
    """The blind spot is real, so the evidence must survive in the row.

    `codex_exec` cannot be told apart from a human running the same command.
    Storing `originator` means a future discriminator can reclassify without
    re-collecting 2.2 GB.
    """
    row = cx._row({"id": "p1", "text": "t", "originator": "codex_exec",
                   "timestamp": "2026-08-03T04:00:00Z"})
    assert row["originator"] == "codex_exec"


# --------------------------------------------------------------------------- #
# The grouping key — what makes tier B useful
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_prompt_sha_groups_shared_openings():
    """Templated prompts share an opening and diverge in the tail.

    Measured: hashing 100 chars gives 61% reuse; hashing 800 gives 9%. The key
    must therefore be prefix-based, or the whole tier-B comparison collapses to
    one-row-per-group.
    """
    head = "You are running as a local coding agent for a Multica workspace. " + "-" * 40
    a = cx._row({"id": "a", "text": head + " issue ABC", "originator": "multica-agent-sdk"})
    b = cx._row({"id": "b", "text": head + " issue XYZ", "originator": "multica-agent-sdk"})
    assert a["prompt_sha"] == b["prompt_sha"], "same template must group together"

    other = cx._row({"id": "c", "text": "完全不同的开头", "originator": "multica-agent-sdk"})
    assert other["prompt_sha"] != a["prompt_sha"]


@pytest.mark.unit
def test_row_rejects_empty():
    assert cx._row({"id": "p", "text": ""}) is None
    assert cx._row({"id": "p", "text": None}) is None
    assert cx._row({"text": "no id"}) is None


# --------------------------------------------------------------------------- #
# collect
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_collect_degrades_when_dir_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(cx, "CODEX_SESSIONS_DIR", tmp_path / "nope")
    monkeypatch.setattr(cx, "write_raw", lambda *a, **k: pytest.fail("no write"))
    assert cx.collect() == 0


@pytest.mark.unit
def test_collect_attaches_session_meta_to_every_row(monkeypatch, tmp_path):
    log = tmp_path / "2026" / "08" / "03" / "rollout-x.jsonl"
    log.parent.mkdir(parents=True)
    log.write_text("\n".join([
        _meta(originator="multica-agent-sdk", session="s1"),
        _user_msg("prompt one"),
        json.dumps({"type": "event_msg", "payload": {"type": "token_count"}}),
        _user_msg("prompt two"),
    ]) + "\n", encoding="utf-8")

    monkeypatch.setattr(cx, "CODEX_SESSIONS_DIR", tmp_path)
    monkeypatch.setattr(cx, "get_watermark", lambda source: None)
    captured = {}
    monkeypatch.setattr(cx, "write_raw",
                        lambda s, records: captured.setdefault("recs", list(records))
                        and 0 or len(captured["recs"]))
    monkeypatch.setattr(cx, "set_watermark",
                        lambda s, v: captured.__setitem__("wm", v))

    assert cx.collect() == 2
    assert all(r["originator"] == "multica-agent-sdk" for r in captured["recs"])
    assert all(r["session_id"] == "s1" for r in captured["recs"])
    assert captured["wm"][str(log)] == log.stat().st_size


@pytest.mark.unit
def test_collect_rereads_meta_when_resuming(monkeypatch, tmp_path):
    """Resuming mid-file must still read session_meta from byte 0.

    Otherwise a file collected in two passes loses its originator on the second
    pass, and every prompt in it silently drops to tier B — the exact failure
    that would corrupt "which of these did I write".
    """
    log = tmp_path / "r.jsonl"
    head = _meta(originator="codex-tui", session="s2") + "\n" + _user_msg("old") + "\n"
    log.write_text(head + _user_msg("new") + "\n", encoding="utf-8")

    monkeypatch.setattr(cx, "CODEX_SESSIONS_DIR", tmp_path)
    monkeypatch.setattr(cx, "get_watermark",
                        lambda source: {str(log): len(head.encode())})
    captured = {}
    monkeypatch.setattr(cx, "write_raw",
                        lambda s, records: captured.setdefault("recs", list(records))
                        and 0 or len(captured["recs"]))
    monkeypatch.setattr(cx, "set_watermark", lambda s, v: None)

    assert cx.collect() == 1
    only = captured["recs"][0]
    assert only["text"] == "new"
    assert only["originator"] == "codex-tui", "meta must survive a resume"


# --------------------------------------------------------------------------- #
# normalize
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_normalize_dedupes_and_counts(monkeypatch):
    records = [
        {"id": "p1", "text": "old", "originator": "codex-tui",
         "timestamp": "2026-08-03T04:00:00Z", "session_id": "s1"},
        {"id": "p1", "text": "new", "originator": "codex-tui",
         "timestamp": "2026-08-03T04:00:00Z", "session_id": "s1"},
        {"id": "p2", "text": "other", "originator": "multica-agent-sdk",
         "timestamp": "2026-08-03T04:00:00Z", "session_id": "s2"},
    ]
    monkeypatch.setattr(cx, "read_raw", lambda source: records)
    captured = {}
    monkeypatch.setattr(cx, "write_clean",
                        lambda s, t, d, rows, c: captured.setdefault("rows", rows)
                        and 0 or len(rows))
    assert cx.normalize() == 2
    by_id = {r["prompt_id"]: r for r in captured["rows"]}
    assert by_id["p1"]["text_preview"] == "new", "last write must win"
    assert by_id["p2"]["text_preview"] is None


@pytest.mark.unit
def test_cst_day_uses_fixed_offset():
    """ADR-22: explicit +8h, never localtime."""
    assert cx._cst_day("2026-08-02T20:00:00.000Z") == "2026-08-03"
    assert cx._cst_day("2026-08-02T15:59:00.000Z") == "2026-08-02"
    assert cx._cst_day(None) is None
    assert cx._cst_day("nonsense") is None


@pytest.mark.unit
def test_source_name_matches_module():
    assert cx.SOURCE == "codex_prompts"
    assert cx.HUMAN_ORIGINATORS == frozenset({"codex-tui", "Codex Desktop"})
