"""codex_prompts adapter — what went into Codex, split by who actually wrote it.

Grain: one submitted prompt.

**Two tiers, because 87% of Codex traffic is not me.** A full scan of all 7,540
session files by `session_meta.payload.originator`:

    multica-agent-sdk / vscode   6,580   Multica's automated agents
    codex_exec       / exec        699   scripted `codex exec`
    Codex Desktop    / vscode       44   me, in the desktop app
    Claude Code      / vscode       11   Claude Code driving Codex
    codex-tui        / cli           4   me, typing in a terminal

  TIER A (`originator` in {codex-tui, Codex Desktop}) — this is me. Store the
    bounded text preview, as with every other prompt source.

  TIER B (everything else) — machine-issued. Store NO body: only a grouping
    hash, a short prefix, length, and metadata. These prompts are heavily
    templated, which makes them useful for a different question — "the same
    prompt ran N times, what did it cost on average?" — without paying to
    store thousands of near-identical bodies.

**Why the hash covers only the first 100 characters.** Measured reuse across a
random 250-file sample (297 multica prompts):

    prefix   distinct templates   reuse
     100            116            61%
     200            220            26%
     400            267            10%
     800            270             9%

The template is the opening (`You are running as a local coding agent for a
Multica workspace...`, seen 80x); the divergence is the trailing per-issue
detail. Hashing the full body would put nearly every prompt in its own group
and destroy the comparison this tier exists for.

**Read `event_msg`, not `response_item`.** Both carry user text, but
`response_item(role=user)` also contains injected AGENTS.md dumps,
`<environment_context>`, and `<turn_aborted>` markers. Measured across 63
interactive sessions: 583 `user_message` vs 613 `response_item`, and 576 of the
613 matched a `user_message` exactly — the 37 extras were pure injection. So
`event_msg/user_message` is already the submitted prompt, no filtering needed.

**Known blind spot, stated rather than guessed:** the 699 `codex_exec` sessions
are undecidable. A human typing `codex exec "..."` at a terminal produces a log
byte-identical to a script issuing the same call — no field distinguishes them.
They are classified TIER B (`agent_authored`); sampling showed them to be
agent-written review prompts, but that is evidence, not proof. `originator` is
stored on every row so this can be re-derived if a discriminator ever appears.

L1 collect: per-file byte offsets (its own watermark). Session-level metadata
comes from the file's first record, so every emitted row knows its originator.

L2 normalize: one row per prompt in `clean/codex_prompts.db`.

Degrade-safe (ADR-23): a missing sessions dir collects 0 and normalizes to 0.
"""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from typing import Any

from config import CODEX_SESSIONS_DIR
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark
from timeutil import CST

SOURCE = "codex_prompts"

_PREVIEW_CHARS = 500
_PREFIX_CHARS = 100

# Originators that mean a human was at the keyboard. Everything else is TIER B.
HUMAN_ORIGINATORS = frozenset({"codex-tui", "Codex Desktop"})

# Harness-generated text that reaches `user_message` even in an interactive
# session — the CLI submits these on the user's behalf. Measured: 220 of 583
# tier-A records (38%) are one of these, so leaving them labelled `typed` would
# put a large amount of machine text into "things I said". Mirrors the
# equivalent table in adapters/claude_prompts.py.
_WRAPPERS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("task_notification", re.compile(r"^<task-notification>")),
    ("slash_command", re.compile(r"^<command-(name|message|args)>")),
    ("bash_io", re.compile(r"^<bash-(input|stdout|stderr)>")),
    ("interrupted", re.compile(r"^\[Request interrupted")),
    ("image", re.compile(r"^\[image")),
    # Named harness tags only. A catch-all `^<[a-z-]+>` would also swallow
    # genuine input that opens with markup (`<div>`, `<html>`), mislabelling my
    # own words as injected — the one error this source most needs to avoid.
    ("injected", re.compile(
        r"^<(system-reminder|environment_context|user_instructions|"
        r"user_shell_command|turn_aborted|task|local-command-[a-z]+)>")),
    ("injected", re.compile(r"^# AGENTS\.md")),
    ("injected", re.compile(r"^You are running as a local coding agent")),
)


def _classify(text: str, originator: str | None) -> str:
    """Label a prompt. `typed` is reserved for text a human actually submitted.

    Originator decides the tier; wrappers then demote individual records that
    the CLI generated inside an otherwise-interactive session.
    """
    if originator not in HUMAN_ORIGINATORS:
        return "agent_authored"
    stripped = text.lstrip()
    for kind, pattern in _WRAPPERS:
        if pattern.search(stripped):
            return kind
    return "typed"


def _iso_to_epoch(ts: Any) -> float | None:
    """ISO-8601 -> epoch seconds. A naive string is read as UTC, never local.

    `datetime.fromisoformat` treats a tz-less string as LOCAL time, which would
    make the derived CST day depend on the host timezone — exactly what ADR-22
    forbids. Codex writes `Z` today, so this never fires in practice; the
    explicit fallback keeps it correct if that ever changes.
    """
    if not isinstance(ts, str) or not ts:
        return None
    try:
        parsed = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.timestamp()


def _cst_day(ts: Any) -> str | None:
    """ISO-8601 -> 'YYYY-MM-DD' in CST (ADR-22: fixed +8h, never localtime)."""
    epoch = _iso_to_epoch(ts)
    if epoch is None:
        return None
    return datetime.fromtimestamp(epoch, timezone.utc).astimezone(CST).strftime("%Y-%m-%d")


def _session_meta(first_line: str) -> dict[str, Any]:
    """Originator/session/cwd from a file's first record. {} when unreadable."""
    try:
        obj = json.loads(first_line)
    except (json.JSONDecodeError, TypeError):
        return {}
    if obj.get("type") != "session_meta":
        return {}
    payload = obj.get("payload") or {}
    return {
        "originator": payload.get("originator"),
        "source": payload.get("source"),
        "session_id": payload.get("id") or payload.get("session_id"),
        "cwd": payload.get("cwd"),
    }


def _user_message(obj: dict[str, Any]) -> str | None:
    """The submitted prompt text, or None if this record is not one."""
    if obj.get("type") != "event_msg":
        return None
    payload = obj.get("payload") or {}
    if payload.get("type") != "user_message":
        return None
    message = payload.get("message")
    return message if isinstance(message, str) and message else None


def collect() -> int:
    """Scan session logs from this source's own offsets. Returns records written."""
    if not CODEX_SESSIONS_DIR.exists():
        return 0
    offsets: dict[str, int] = dict(get_watermark(SOURCE) or {})
    new_offsets = dict(offsets)
    total = 0

    for path in CODEX_SESSIONS_DIR.glob("**/*.jsonl"):
        key = str(path)
        # Relative path, not just the filename: sessions live under a
        # YYYY/MM/DD tree, so two dates can hold the same basename and would
        # otherwise mint identical ids at the same offset.
        try:
            rel_path = str(path.relative_to(CODEX_SESSIONS_DIR))
        except ValueError:
            rel_path = path.name
        start = offsets.get(key, 0)
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size < start:
            # Truncated: the stored offset now points past EOF, so a plain
            # `size <= start` would skip this file forever. Restart from zero.
            #
            # Safe against the id-collision this would otherwise raise: ids are
            # `<relpath>:<offset>`, so re-reading DIFFERENT content at the same
            # offset would overwrite an unrelated record. That cannot happen
            # here — Codex names each file `rollout-<ISO>-<session-uuid>.jsonl`
            # (verified: zero duplicate basenames across all 7,540 files), so a
            # given path is one append-only session. A file can shrink, but it
            # cannot come back holding a different session's prompts.
            start = 0
        elif size == start:
            continue

        # session_meta is the FIRST record, so it must be read from byte 0 even
        # when resuming mid-file — otherwise a resumed file loses its originator
        # and every row from it would be misclassified.
        try:
            with path.open("r", encoding="utf-8", errors="replace") as head:
                meta = _session_meta(head.readline())
        except OSError:
            continue

        batch: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            fh.seek(start)
            # `fh.tell()` is exact and legal here. It is NOT usable inside a
            # `for line in fh` loop ("telling position disabled by next()
            # call"), which is why this reads via explicit readline().
            #
            # Do NOT compute the offset by summing len(line.encode()): in text
            # mode that is not the true byte position. Universal newlines turn
            # \r\n into \n (1 byte short per line) and errors="replace" turns
            # one bad byte into U+FFFD (2 bytes long). Either way the running
            # total drifts from the real file position — and this value is the
            # watermark, is compared against st_size, and forms prompt_id, so
            # drift means a resume seeks mid-line and silently drops records.
            line_offset = fh.tell()
            while True:
                raw_line = fh.readline()
                if not raw_line:
                    break
                current_offset = line_offset
                line_offset = fh.tell()
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                text = _user_message(obj)
                if text is None:
                    continue
                batch.append({
                    # Absolute file offset, NOT a batch index: an index
                    # restarts at 0 on every resume, so one file collected in
                    # two passes can mint duplicate ids and let normalize's
                    # last-write-wins silently drop a row.
                    "id": f"{rel_path}:{current_offset}",
                    "timestamp": obj.get("timestamp"),
                    "text": text,
                    **meta,
                })
            new_offsets[key] = line_offset
        if batch:
            total += write_raw(SOURCE, batch)

    if new_offsets != offsets:
        set_watermark(SOURCE, new_offsets)
    return total


_CLEAN_DDL = """
CREATE TABLE prompt (
    prompt_id     TEXT PRIMARY KEY,
    agent         TEXT,
    session_id    TEXT,
    originator    TEXT,          -- why a row is tier A or B; kept for re-derivation
    day           TEXT,
    ts            REAL,
    source_kind   TEXT,          -- 'typed' (tier A) | 'agent_authored' (tier B)
    text_len      INTEGER,
    text_preview  TEXT,          -- tier A only; NULL for tier B by design
    prompt_sha    TEXT,          -- hash of the first 100 chars: the grouping key
    prefix_100    TEXT,          -- same 100 chars in clear, so the hash is readable
    cwd           TEXT
)
"""
_CLEAN_COLS = ("prompt_id", "agent", "session_id", "originator", "day", "ts",
               "source_kind", "text_len", "text_preview", "prompt_sha",
               "prefix_100", "cwd")


def _row(rec: dict[str, Any]) -> dict[str, Any] | None:
    text = rec.get("text")
    prompt_id = rec.get("id")
    if not isinstance(text, str) or not text or not prompt_id:
        return None
    source_kind = _classify(text, rec.get("originator"))
    prefix = text[:_PREFIX_CHARS]
    return {
        "prompt_id": str(prompt_id),
        "agent": "codex",
        "session_id": rec.get("session_id"),
        "originator": rec.get("originator"),
        "day": _cst_day(rec.get("timestamp")),
        "ts": _iso_to_epoch(rec.get("timestamp")),
        "source_kind": source_kind,
        "text_len": len(text),
        # Body kept ONLY for `typed`. Keyed off source_kind, not originator:
        # 232 of 583 interactive records are CLI-generated wrappers
        # (slash_command / task_notification / ...), and storing their bodies
        # would put machine text in the column that answers "what did I write".
        "text_preview": text[:_PREVIEW_CHARS] if source_kind == "typed" else None,
        "prompt_sha": hashlib.sha256(prefix.encode("utf-8")).hexdigest()[:16],
        "prefix_100": prefix,
        "cwd": rec.get("cwd"),
    }


def normalize() -> int:
    """One row per prompt, keyed by prompt_id (last write wins)."""
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        row = _row(rec)
        if row:
            rows[row["prompt_id"]] = row
    return write_clean(SOURCE, "prompt", _CLEAN_DDL, list(rows.values()),
                       _CLEAN_COLS)
