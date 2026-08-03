"""claude_prompts adapter — what *I* actually typed into Claude Code.

Grain: one human prompt. Plus a second table of agent-asked questions and the
answer I picked.

**Why this is a new source and not a widening of `claude_jsonl`.** Three
independent reasons, each sufficient on its own:

  1. `claude_jsonl` feeds `fact_turn`, and `tests/test_warehouse_quality.py`
     asserts `fact_turn.session_id -> fact_request` resolves at >99% (measured:
     100.0%). User lines produce no API request, so mixing them in drops that
     to ~64% — an immediate red.
  2. `claude_jsonl._slim()` is built for assistant lines: it extracts tool
     NAMES, and has no content path at all. Widening its filter would collect
     user rows with the text thrown away.
  3. Its 2,229 per-file offsets have all reached EOF, so backfilling would need
     a full watermark reset, re-emitting the entire assistant history into raw/.

This mirrors the precedent set by `hermes_messages`: when the existing source's
cursor has moved past the history you need, add a source at the right grain
rather than mutating the old one.

L1 collect: scan `~/.claude/projects/**/*.jsonl` with its OWN per-file byte
offsets (starting from zero — independent of `claude_jsonl`'s watermark), and
keep only what a human could have produced.

**The discriminator** (all four fields verified against live transcripts; of
65,257 user lines corpus-wide only ~6.6% survive the first filter):

  - `message.content` is a list containing `tool_result` -> tool output, drop.
    This alone removes 93.4%.
  - `entrypoint == "sdk-cli"` -> a programmatic `claude -p` run; the "user"
    text is an agent-authored prompt. Effectively a per-file flag.
  - `isSidechain` -> subagent transcript; the "user" text is the Task prompt.
  - `isMeta` -> harness-injected (caveats, image metadata, skill bodies).

Everything surviving that is classified by `_classify()` rather than dropped,
so a misjudgement can be re-derived later from `source_kind` without
re-collecting (`typed` / `slash_command` / `task_notification` / ...).

L2 normalize: two tables in `clean/claude_prompts.db` —
  `prompt` — one row per surviving user line; body kept as length + bounded
             preview, never in full (full text stays in raw/).
  `ask`    — one row per AskUserQuestion question, with the chosen answer.

Degrade-safe (ADR-23): a missing projects dir collects 0 and normalizes to 0.
"""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

from config import CLAUDE_PROJECTS_DIR
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark
from timeutil import CST

SOURCE = "claude_prompts"

# Bounded preview kept in the clean DB. Human prompts here have a median of ~22
# chars, so 500 captures nearly all of them whole while capping the outliers.
_PREVIEW_CHARS = 500

# Prefix hashed into `prompt_sha` for grouping repeated prompts. Short on
# purpose — templated prompts share an opening and diverge later.
_PREFIX_CHARS = 100

# Leading markers that identify a harness-generated line that survived the
# structural filters. Order matters: first match wins in _classify().
_WRAPPERS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("task_notification", re.compile(r"^<task-notification>")),
    ("slash_command", re.compile(r"^<command-(name|message|args)>")),
    ("bash_io", re.compile(r"^<bash-(input|stdout|stderr)>")),
    ("interrupted", re.compile(r"^\[Request interrupted")),
    ("local_command", re.compile(r"^<local-command-(stdout|caveat)>")),
    ("image", re.compile(r"^\[Image[ :]")),
    ("compact_resume", re.compile(r"^This session is being continued")),
    # Any other leading XML-ish tag is harness scaffolding, not typing.
    ("injected", re.compile(r"^<[a-z][a-z0-9_-]*>")),
)


def _text_of(content: Any) -> str | None:
    """Human-authored text from `message.content`, or None if there is none.

    A bare str is typing. A list is only human when it holds `text` blocks and
    no `tool_result` — a `tool_result` anywhere means the line is tool output
    wearing the user role.
    """
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None
    parts: list[str] = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "tool_result":
            return None
        if block.get("type") == "text":
            text = block.get("text")
            if isinstance(text, str):
                parts.append(text)
    return "\n".join(parts) if parts else None


def _classify(text: str, entrypoint: str | None,
              is_sidechain: bool, is_meta: bool) -> str:
    """Label a surviving user line. Never guesses `typed` — unclear goes elsewhere."""
    if is_meta:
        return "injected"
    if is_sidechain:
        return "agent_authored"
    if entrypoint == "sdk-cli":
        return "agent_authored"
    stripped = text.lstrip()
    for kind, pattern in _WRAPPERS:
        if pattern.search(stripped):
            return kind
    if entrypoint == "cli":
        return "typed"
    # Unknown entrypoint with no wrapper: plausible but unproven. Do not
    # promote it to `typed` — a wrong label here silently corrupts the answer
    # to "what did I actually send".
    return "unknown"


def _iso_to_epoch(ts: Any) -> float | None:
    """ISO-8601 (Z or offset) -> epoch seconds. None when absent/malformed."""
    if not isinstance(ts, str) or not ts:
        return None
    try:
        from datetime import datetime
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None


def _cst_day(ts: Any) -> str | None:
    """ISO-8601 timestamp -> 'YYYY-MM-DD' in CST (ADR-22: fixed +8h)."""
    epoch = _iso_to_epoch(ts)
    if epoch is None:
        return None
    from datetime import datetime, timezone
    return datetime.fromtimestamp(epoch, timezone.utc).astimezone(CST).strftime("%Y-%m-%d")


def _slim_user(obj: dict[str, Any], text: str) -> dict[str, Any]:
    """Keep the fields the prompt table needs. Full text IS kept in raw/."""
    return {
        "kind": "prompt",
        "uuid": obj.get("uuid"),
        "sessionId": obj.get("sessionId"),
        "timestamp": obj.get("timestamp"),
        "cwd": obj.get("cwd"),
        "gitBranch": obj.get("gitBranch"),
        "entrypoint": obj.get("entrypoint"),
        "isSidechain": bool(obj.get("isSidechain")),
        "isMeta": bool(obj.get("isMeta")),
        "text": text,
    }


def _asks_from_assistant(obj: dict[str, Any]) -> list[dict[str, Any]]:
    """AskUserQuestion invocations on an assistant line, keyed by tool_use_id."""
    msg = obj.get("message") or {}
    out: list[dict[str, Any]] = []
    for block in (msg.get("content") or []):
        if not isinstance(block, dict):
            continue
        if block.get("type") != "tool_use" or block.get("name") != "AskUserQuestion":
            continue
        questions = (block.get("input") or {}).get("questions")
        # Guard: `questions` is a raw str in ~75/1117 invocations (truncated
        # streaming input), not the documented list. Skip rather than crash.
        if not isinstance(questions, list):
            continue
        out.append({
            "kind": "ask",
            "tool_use_id": block.get("id"),
            "sessionId": obj.get("sessionId"),
            "timestamp": obj.get("timestamp"),
            "questions": questions,
        })
    return out


def _answers_from_user(obj: dict[str, Any]) -> dict[str, Any] | None:
    """The answer map for an AskUserQuestion, if this user line carries one.

    Reads `toolUseResult.answers` — a machine-readable {question: answer} dict
    on the same line. Deliberately NOT parsed out of the
    "Your questions have been answered: ..." prose, which is ambiguous whenever
    a question or answer contains a quote, `=` or `, ` (Chinese quotes appear
    routinely in this corpus).
    """
    result = obj.get("toolUseResult")
    if not isinstance(result, dict):
        return None
    answers = result.get("answers")
    if not isinstance(answers, dict) or not answers:
        return None
    tool_use_id = None
    for block in ((obj.get("message") or {}).get("content") or []):
        if isinstance(block, dict) and block.get("type") == "tool_result":
            tool_use_id = block.get("tool_use_id")
            break
    return {
        "kind": "answer",
        "tool_use_id": tool_use_id,
        "sessionId": obj.get("sessionId"),
        "timestamp": obj.get("timestamp"),
        "answers": answers,
    }


def collect() -> int:
    """Scan transcripts from this source's own offsets. Returns records written."""
    if not CLAUDE_PROJECTS_DIR.exists():
        return 0
    offsets: dict[str, int] = dict(get_watermark(SOURCE) or {})
    new_offsets = dict(offsets)
    total = 0

    for path in CLAUDE_PROJECTS_DIR.glob("**/*.jsonl"):
        key = str(path)
        start = offsets.get(key, 0)
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size <= start:
            continue
        batch: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            fh.seek(start)
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                kind = obj.get("type")
                if kind == "assistant":
                    batch.extend(_asks_from_assistant(obj))
                elif kind == "user":
                    answer = _answers_from_user(obj)
                    if answer is not None:
                        batch.append(answer)
                    text = _text_of((obj.get("message") or {}).get("content"))
                    if text:
                        batch.append(_slim_user(obj, text))
            new_offsets[key] = fh.tell()
        if batch:
            total += write_raw(SOURCE, batch)

    if new_offsets != offsets:
        set_watermark(SOURCE, new_offsets)
    return total


_PROMPT_DDL = """
CREATE TABLE prompt (
    prompt_id     TEXT PRIMARY KEY,
    agent         TEXT,
    session_id    TEXT,
    day           TEXT,
    ts            REAL,
    source_kind   TEXT,
    text_len      INTEGER,
    text_preview  TEXT,
    prompt_sha    TEXT,
    prefix_100    TEXT,
    cwd           TEXT,
    git_branch    TEXT
)
"""
_PROMPT_COLS = ("prompt_id", "agent", "session_id", "day", "ts", "source_kind",
                "text_len", "text_preview", "prompt_sha", "prefix_100",
                "cwd", "git_branch")

_ASK_DDL = """
CREATE TABLE ask (
    ask_id      TEXT PRIMARY KEY,
    agent       TEXT,
    session_id  TEXT,
    day         TEXT,
    ts          REAL,
    question    TEXT,
    options     TEXT,          -- JSON array of offered labels
    chosen      TEXT,          -- NULL when the question was never answered
    is_timeout  INTEGER        -- always 0 here; Hermes `clarify` uses 1
)
"""
_ASK_COLS = ("ask_id", "agent", "session_id", "day", "ts", "question",
             "options", "chosen", "is_timeout")


def _prompt_row(rec: dict[str, Any]) -> dict[str, Any] | None:
    text = rec.get("text")
    if not isinstance(text, str) or not text:
        return None
    uuid = rec.get("uuid")
    if not uuid:
        return None
    prefix = text[:_PREFIX_CHARS]
    return {
        "prompt_id": str(uuid),
        "agent": "claude",
        "session_id": rec.get("sessionId"),
        "day": _cst_day(rec.get("timestamp")),
        "ts": _iso_to_epoch(rec.get("timestamp")),
        "source_kind": _classify(text, rec.get("entrypoint"),
                                 bool(rec.get("isSidechain")),
                                 bool(rec.get("isMeta"))),
        "text_len": len(text),
        "text_preview": text[:_PREVIEW_CHARS],
        "prompt_sha": hashlib.sha256(prefix.encode("utf-8")).hexdigest()[:16],
        "prefix_100": prefix,
        "cwd": rec.get("cwd"),
        "git_branch": rec.get("gitBranch"),
    }


def normalize() -> int:
    """Rebuild both tables. Returns the prompt-row count (the headline number)."""
    prompts: dict[str, dict[str, Any]] = {}
    asks: dict[str, dict[str, Any]] = {}
    answers: dict[str, dict[str, Any]] = {}

    for rec in read_raw(SOURCE):
        kind = rec.get("kind")
        if kind == "prompt":
            row = _prompt_row(rec)
            if row:
                prompts[row["prompt_id"]] = row
        elif kind == "ask":
            tool_use_id = rec.get("tool_use_id")
            if tool_use_id:
                asks[str(tool_use_id)] = rec
        elif kind == "answer":
            tool_use_id = rec.get("tool_use_id")
            if tool_use_id:
                answers[str(tool_use_id)] = rec

    ask_rows: dict[str, dict[str, Any]] = {}
    for tool_use_id, rec in asks.items():
        answered = (answers.get(tool_use_id) or {}).get("answers") or {}
        for index, question in enumerate(rec.get("questions") or []):
            if not isinstance(question, dict):
                continue
            text = question.get("question")
            if not text:
                continue
            options = [
                opt.get("label")
                for opt in (question.get("options") or [])
                if isinstance(opt, dict) and opt.get("label")
            ]
            ask_id = f"{tool_use_id}#{index}"
            ask_rows[ask_id] = {
                "ask_id": ask_id,
                "agent": "claude",
                "session_id": rec.get("sessionId"),
                "day": _cst_day(rec.get("timestamp")),
                "ts": _iso_to_epoch(rec.get("timestamp")),
                "question": text,
                "options": json.dumps(options, ensure_ascii=False),
                # ~22% of answers are free text the user typed instead of
                # picking an option (sometimes a counter-question). Store
                # whatever was actually chosen; never assume it is in `options`.
                "chosen": answered.get(text),
                "is_timeout": 0,
            }

    write_clean(SOURCE, "ask", _ASK_DDL, list(ask_rows.values()), _ASK_COLS)
    return write_clean(SOURCE, "prompt", _PROMPT_DDL,
                       list(prompts.values()), _PROMPT_COLS)
