"""claude_jsonl adapter — Claude Code transcripts (per-turn token + tool facts).

L1 collect: scan ~/.claude/projects/**/*.jsonl, resume from per-file byte offset.
L2 normalize: keep assistant lines, extract usage + model + attribution_skill +
tool_use sequence + stop_reason (= OTel finish_reason).

Verified caveats:
  - NO `summary` line type exists. Real types: assistant/user/system/attachment/
    file-history-snapshot/progress + lightweight control lines.
  - Join on camelCase `sessionId` (= filename, current session). snake_case
    `session_id` is the resume/fork PARENT pointer — different value.
  - No cost field; derive downstream.
  - `message.stop_reason` carries the finish reason (end_turn / tool_use /
    max_tokens). max_tokens = the turn was truncated → a quality signal. It is
    NULL on some lines (streaming/control frames), preserved as-is.
  - NO reasoning/thinking token field is present in `message.usage` for these
    transcripts (verified: usage keys are input_tokens / output_tokens /
    cache_read_input_tokens / cache_creation_input_tokens plus non-token
    metadata like service_tier / speed). So reasoning_tokens is NOT added here;
    the Hermes state_db source is where reasoning_tokens lives.
"""

from __future__ import annotations

import json
from typing import Any

from config import CLAUDE_PROJECTS_DIR
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark

SOURCE = "claude_jsonl"


def collect() -> int:
    if not CLAUDE_PROJECTS_DIR.exists():
        return 0
    # Watermark = {filepath: byte_offset_last_read}. Resume mid-file so growing
    # session files only yield their new lines.
    offsets: dict[str, int] = dict(get_watermark(SOURCE) or {})
    total = 0
    new_offsets = dict(offsets)

    for path in CLAUDE_PROJECTS_DIR.glob("**/*.jsonl"):
        key = str(path)
        start = offsets.get(key, 0)
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size <= start:
            continue  # unchanged
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
                # Only keep assistant lines (the ones carrying usage) — keeps raw lean.
                if obj.get("type") == "assistant":
                    batch.append(_slim(obj))
            new_offsets[key] = fh.tell()
        if batch:
            total += write_raw(SOURCE, batch)

    if new_offsets != offsets:
        set_watermark(SOURCE, new_offsets)
    return total


def _slim(obj: dict[str, Any]) -> dict[str, Any]:
    """Keep only fields we need — drop bulky message content bodies."""
    msg = obj.get("message") or {}
    usage = msg.get("usage") or {}
    tool_names = [
        b.get("name") for b in (msg.get("content") or [])
        if isinstance(b, dict) and b.get("type") == "tool_use"
    ]
    # snake_case session_id (resume/fork parent) may sit at top level or in
    # message; it is rare in practice. Capture wherever present, but never
    # confuse it with camelCase sessionId (the current session / join key).
    lineage = obj.get("session_id") or msg.get("session_id")
    return {
        "uuid": obj.get("uuid"),
        "sessionId": obj.get("sessionId"),          # current session (join key)
        "session_id_lineage": lineage,               # parent (do NOT join on this)
        "timestamp": obj.get("timestamp"),
        "cwd": obj.get("cwd"),
        "gitBranch": obj.get("gitBranch"),
        "role": msg.get("role"),
        "model": msg.get("model"),
        "stop_reason": msg.get("stop_reason"),       # finish_reason: end_turn/tool_use/max_tokens
        "attributionSkill": obj.get("attributionSkill"),
        "usage": {
            "input_tokens": usage.get("input_tokens"),
            "output_tokens": usage.get("output_tokens"),
            "cache_read_input_tokens": usage.get("cache_read_input_tokens"),
            "cache_creation_input_tokens": usage.get("cache_creation_input_tokens"),
        },
        "tool_calls": tool_names,
    }


_CLEAN_DDL = """
CREATE TABLE turn (
    turn_uuid TEXT PRIMARY KEY, session_id TEXT, parent_session_id TEXT,
    ts TEXT, project TEXT, git_branch TEXT, role TEXT, model TEXT,
    attribution_skill TEXT, input_tokens INTEGER, output_tokens INTEGER,
    cache_read INTEGER, cache_creation INTEGER, tool_calls TEXT,
    finish_reason TEXT
)
"""
_CLEAN_COLS = (
    "turn_uuid", "session_id", "parent_session_id", "ts", "project",
    "git_branch", "role", "model", "attribution_skill", "input_tokens",
    "output_tokens", "cache_read", "cache_creation", "tool_calls",
    "finish_reason",
)


def _project_of(cwd: str | None) -> str | None:
    if not cwd:
        return None
    return cwd.rstrip("/").rsplit("/", 1)[-1] or cwd


def normalize() -> int:
    # Last-write-wins by uuid: read_raw yields shards in ascending date order,
    # so a newer shard's record for the same turn overwrites an older one. This
    # matters when a full re-collect (watermark reset) re-emits historical turns
    # with fields the old parser dropped (e.g. stop_reason) — the newer, richer
    # record must win, not the first (older, sparser) one seen.
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        uuid = rec.get("uuid")
        if not uuid:
            continue
        u = rec.get("usage") or {}
        tc = rec.get("tool_calls") or []
        rows[uuid] = {
            "turn_uuid": uuid,
            "session_id": rec.get("sessionId"),
            "parent_session_id": rec.get("session_id_lineage"),
            "ts": rec.get("timestamp"),
            "project": _project_of(rec.get("cwd")),
            "git_branch": rec.get("gitBranch"),
            "role": rec.get("role"),
            "model": rec.get("model"),
            "attribution_skill": rec.get("attributionSkill"),
            "input_tokens": u.get("input_tokens"),
            "output_tokens": u.get("output_tokens"),
            "cache_read": u.get("cache_read_input_tokens"),
            "cache_creation": u.get("cache_creation_input_tokens"),
            "tool_calls": json.dumps(tc, ensure_ascii=False),
            "finish_reason": rec.get("stop_reason"),
        }
    return write_clean(SOURCE, "turn", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
