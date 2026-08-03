"""kimi_prompts adapter — what I typed into Kimi Code.

Grain: one submitted prompt.

**The cleanest discriminator of the four sources.** Kimi tags every prompt with
its own provenance, so nothing has to be inferred from wrappers or heuristics:

    turn.prompt  origin.kind == "user"              me
                 origin.kind == "system_trigger"    subagent dispatch
    turn.steer   origin.kind == "background_task"   background work

Contrast with the other three: Claude needs four structural fields plus wrapper
regexes, Codex needs session-level `originator` plus wrapper regexes, and Hermes
needs a source allowlist plus a `[`-prefix rule. Here it is one field.

**Read `wire.jsonl`, not `user-history/`.** Two candidate sources exist:

  sessions/<wd>/<session>/agents/<agent>/wire.jsonl
      the real event log: turn.prompt records with origin.kind, epoch-ms
      timestamps, and a session id from the path. This is what we read.

  user-history/<md5(workdir)>.jsonl
      a shell-history-style recall buffer: `{"content": ...}` per line, with
      NO timestamp and NO session id. Its one advantage is that it preserves
      slash commands as typed (`/new`, `/login`) — Kimi expands them everywhere
      else. Not read here; noted so the tradeoff is not rediscovered later.

Volume is small (~21 prompts): Kimi is barely used on this machine. It is
collected anyway so "what did I send" spans every agent rather than silently
omitting one.

L1 collect: snapshot-hash (`write_raw_snapshot`) rather than a watermark. The
whole corpus is a few files totalling ~4 MB, so a full re-read each run is
cheap, and the content hash makes it idempotent — no cursor to drift.

L2 normalize: one row per prompt in `clean/kimi_prompts.db`, matching the
`prompt` shape used by claude_prompts / codex_prompts.

Degrade-safe (ADR-23): a missing sessions dir collects 0 and normalizes to 0.
"""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Any

from config import KIMI_SESSIONS_DIR
from rawio import write_raw_snapshot, read_raw
from cleanio import write_clean
from timeutil import CST

SOURCE = "kimi_prompts"

_PREVIEW_CHARS = 500
_PREFIX_CHARS = 100

# origin.kind values, mapped to the shared source_kind vocabulary. Anything not
# listed falls to `unknown` rather than being assumed human.
_ORIGIN_KINDS: dict[str, str] = {
    "user": "typed",
    "system_trigger": "agent_authored",
    "background_task": "agent_authored",
    "injection": "injected",
    "skill_activation": "injected",
    "shell_command": "bash_io",
}


def _cst_day(ts_ms: Any) -> str | None:
    """Epoch MILLISECONDS -> 'YYYY-MM-DD' in CST (ADR-22: fixed +8h).

    Note the unit: Kimi records milliseconds, while the Hermes sources record
    seconds. Passing one to the other's helper silently yields a date ~55 years
    off, so the conversion is done here rather than reusing epoch_s_to_cst_day.
    """
    if not isinstance(ts_ms, (int, float)) or ts_ms <= 0:
        return None
    return datetime.fromtimestamp(ts_ms / 1000.0, timezone.utc).astimezone(
        CST).strftime("%Y-%m-%d")


def _text_of(input_blocks: Any) -> str | None:
    """Concatenated text of a turn.prompt's input blocks, or None."""
    if not isinstance(input_blocks, list):
        return None
    parts = [
        block.get("text") for block in input_blocks
        if isinstance(block, dict) and block.get("type") == "text"
        and isinstance(block.get("text"), str) and block.get("text")
    ]
    return "\n".join(parts) if parts else None


def collect() -> int:
    """Read every wire.jsonl and snapshot the prompts. Returns records written."""
    if not KIMI_SESSIONS_DIR.exists():
        return 0
    import json

    records: list[dict[str, Any]] = []
    for path in KIMI_SESSIONS_DIR.glob("**/wire.jsonl"):
        # .../sessions/<workdir_slug>/<session_id>/agents/<agent>/wire.jsonl
        parts = path.parts
        try:
            session_id = parts[-3] if parts[-2] == "agents" else parts[-4]
        except IndexError:
            session_id = None
        try:
            with path.open("r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if obj.get("type") != "turn.prompt":
                        continue
                    text = _text_of(obj.get("input"))
                    if not text:
                        continue
                    origin = obj.get("origin") or {}
                    records.append({
                        "id": f"{session_id}:{obj.get('time')}",
                        "session_id": session_id,
                        "time": obj.get("time"),
                        "origin_kind": origin.get("kind"),
                        "text": text,
                    })
        except OSError:
            continue

    if not records:
        return 0
    return write_raw_snapshot(SOURCE, records)


_CLEAN_DDL = """
CREATE TABLE prompt (
    prompt_id     TEXT PRIMARY KEY,
    agent         TEXT,
    session_id    TEXT,
    origin_kind   TEXT,          -- Kimi's own provenance tag; kept verbatim
    day           TEXT,
    ts            REAL,          -- epoch SECONDS (converted from Kimi's ms)
    source_kind   TEXT,
    text_len      INTEGER,
    text_preview  TEXT,          -- typed only; NULL for machine-issued prompts
    prompt_sha    TEXT,
    prefix_100    TEXT
)
"""
_CLEAN_COLS = ("prompt_id", "agent", "session_id", "origin_kind", "day", "ts",
               "source_kind", "text_len", "text_preview", "prompt_sha",
               "prefix_100")


def _row(rec: dict[str, Any]) -> dict[str, Any] | None:
    text = rec.get("text")
    prompt_id = rec.get("id")
    if not isinstance(text, str) or not text or not prompt_id:
        return None
    source_kind = _ORIGIN_KINDS.get(rec.get("origin_kind"), "unknown")
    prefix = text[:_PREFIX_CHARS]
    ts_ms = rec.get("time")
    return {
        "prompt_id": str(prompt_id),
        "agent": "kimi",
        "session_id": rec.get("session_id"),
        "origin_kind": rec.get("origin_kind"),
        "day": _cst_day(ts_ms),
        # Stored in SECONDS to match every other prompt source; a mixed-unit
        # ts column would break any cross-agent ordering.
        "ts": ts_ms / 1000.0 if isinstance(ts_ms, (int, float)) else None,
        "source_kind": source_kind,
        "text_len": len(text),
        "text_preview": text[:_PREVIEW_CHARS] if source_kind == "typed" else None,
        "prompt_sha": hashlib.sha256(prefix.encode("utf-8")).hexdigest()[:16],
        "prefix_100": prefix,
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
