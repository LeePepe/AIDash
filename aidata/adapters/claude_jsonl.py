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
import re
import sqlite3
from pathlib import Path
from typing import Any

from cleanio import write_clean
from cleanio import write_clean as _DEFAULT_WRITE_CLEAN
from config import CLAUDE_PROJECTS_DIR, clean_path
from rawio import read_raw, write_raw
from state import get_watermark, set_watermark

SOURCE = "claude_jsonl"
_PATH_RE = re.compile(
    r"(?:^|[\s/\\])skills[/\\](?P<skill>[A-Za-z0-9][A-Za-z0-9._-]{0,127})"
    r"[/\\](?P<kind>references|scripts)[/\\](?P<rel>[^\s\"'`()<>]+)"
)


def _path_record(block: dict[str, Any], obj: dict[str, Any], session_id: Any) -> dict[str, Any] | None:
    tool_input = block.get("input")
    if not isinstance(tool_input, dict):
        return None
    haystack = " ".join(str(value) for value in tool_input.values() if isinstance(value, str))
    match = _PATH_RE.search(haystack)
    if not match:
        return None
    skill = match.group("skill")
    rel = match.group("rel").strip("/\\")
    canonical = f"skills/{skill}/{match.group('kind')}/{rel}"
    matched_path = match.group(0).strip(" \t\r\n\"'`()<>")
    candidates = [Path(matched_path).expanduser()]
    if not Path(matched_path).is_absolute():
        if obj.get("cwd"):
            candidates.append(Path(str(obj["cwd"])) / matched_path)
        candidates.extend(Path.home() / root / matched_path for root in (".agents", ".copilot", "Development/user-skills"))
    byte_len = len(canonical.encode("utf-8"))
    for candidate in candidates:
        try:
            if candidate.is_file():
                byte_len = candidate.stat().st_size
                break
        except OSError:
            continue
    base = {
        "sessionId": session_id, "turn_uuid": obj.get("uuid"),
        "skill": skill, "timestamp": obj.get("timestamp"),
    }
    if match.group("kind") == "references":
        return {"_kind": "reference_hit", "hit_uid": f"{obj.get('uuid')}:{block.get('id')}",
                "reference_path": canonical, "byte_len": byte_len, **base}
    return {"_kind": "script_call", "call_uid": f"{obj.get('uuid')}:{block.get('id')}",
            "tool_use_id": block.get("id"), "script_path": canonical,
            "exit_code": None, "duration_ms": None, **base}


def _exit_code(value: Any) -> int | None:
    text = json.dumps(value, ensure_ascii=False) if not isinstance(value, str) else value
    match = re.search(r"Process exited with code\s+(-?\d+)", text, re.IGNORECASE)
    return int(match.group(1)) if match else None


def _elapsed_ms(start: Any, end: Any) -> int | None:
    try:
        from datetime import datetime
        left = datetime.fromisoformat(str(start).replace("Z", "+00:00"))  # noqa: FURB162
        right = datetime.fromisoformat(str(end).replace("Z", "+00:00"))  # noqa: FURB162
        return int(max(0.0, (right - left).total_seconds() * 1000))
    except (TypeError, ValueError):
        return None


def collect() -> int:
    if not CLAUDE_PROJECTS_DIR.exists():
        return 0
    watermark = get_watermark(SOURCE) or {}
    offsets: dict[str, int] = {key: value for key, value in watermark.items() if key != "__pending_tools__"}
    pending: dict[str, dict[str, Any]] = dict(watermark.get("__pending_tools__") or {})
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
        with path.open("rb") as fh:
            fh.seek(start)
            for idx, raw_line in enumerate(iter(fh.readline, b""), start=1):
                # A writer may still be appending this record. Retry it next time.
                if not raw_line.endswith(b"\n"):
                    break
                new_offsets[key] = fh.tell()
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(obj, dict):
                    continue
                if obj.get("type") == "assistant":
                    turn = _slim(obj, fallback_uuid=f"{path.stem}:{start}:{idx}")
                    batch.append(turn)
                    for block in (obj.get("message") or {}).get("content") or []:
                        if isinstance(block, dict) and block.get("type") == "tool_use":
                            record = _path_record(block, obj, obj.get("sessionId"))
                            if record is not None:
                                batch.append(record)
                                if record.get("_kind") == "script_call" and record.get("tool_use_id"):
                                    pending[str(record["tool_use_id"])] = dict(record)
                elif obj.get("type") == "user":
                    for block in (obj.get("message") or {}).get("content") or []:
                        if not isinstance(block, dict) or block.get("type") != "tool_result":
                            continue
                        tool_id = block.get("tool_use_id")
                        if not tool_id:
                            continue
                        record = next(
                            (item for item in reversed(batch)
                             if item.get("_kind") == "script_call"
                             and item.get("tool_use_id") == tool_id),
                            None,
                        )
                        if record is None:
                            record = pending.pop(str(tool_id), None)
                            if record is not None:
                                batch.append(record)
                        else:
                            pending.pop(str(tool_id), None)
                        if record is not None:
                            record["exit_code"] = 1 if block.get("is_error") else _exit_code(block.get("content"))
                            record["duration_ms"] = _elapsed_ms(record.get("timestamp"), obj.get("timestamp"))
        if batch:
            total += write_raw(SOURCE, batch)

    if pending:
        new_offsets["__pending_tools__"] = pending
    if new_offsets != watermark:
        set_watermark(SOURCE, new_offsets)
    return total


def _slim(obj: dict[str, Any], fallback_uuid: str | None = None) -> dict[str, Any]:
    """Keep only fields we need — drop bulky message content bodies."""
    msg = obj.get("message") or {}
    usage = msg.get("usage") or {}
    tool_names = [
        b.get("name") for b in (msg.get("content") or [])
        if isinstance(b, dict) and b.get("type") == "tool_use"
    ]
    skill_names = []
    for block in msg.get("content") or []:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        if block.get("name") not in {"Skill", "skill"}:
            continue
        tool_input = block.get("input")
        if not isinstance(tool_input, dict):
            continue
        skill = tool_input.get("skill") or tool_input.get("name")
        if not isinstance(skill, str):
            continue
        # Keep the named skill only; discard all other tool-input fields and
        # bound/control-normalize the value before it reaches raw storage.
        skill = " ".join(skill.split())[:128]
        if skill:
            skill_names.append(skill)
    # snake_case session_id (resume/fork parent) may sit at top level or in
    # message; it is rare in practice. Capture wherever present, but never
    # confuse it with camelCase sessionId (the current session / join key).
    lineage = obj.get("session_id") or msg.get("session_id")
    attr_skill = obj.get("attributionSkill") or (skill_names[0] if skill_names else None)
    return {
        "uuid": obj.get("uuid") or msg.get("id") or fallback_uuid,
        "sessionId": obj.get("sessionId"),          # current session (join key)
        "session_id_lineage": lineage,               # parent (do NOT join on this)
        "timestamp": obj.get("timestamp"),
        "cwd": obj.get("cwd"),
        "gitBranch": obj.get("gitBranch"),
        "role": msg.get("role"),
        "model": msg.get("model"),
        "stop_reason": msg.get("stop_reason"),       # finish_reason: end_turn/tool_use/max_tokens
        "attributionSkill": attr_skill,
        "usage": {
            "input_tokens": usage.get("input_tokens"),
            "output_tokens": usage.get("output_tokens"),
            "cache_read_input_tokens": usage.get("cache_read_input_tokens"),
            "cache_creation_input_tokens": usage.get("cache_creation_input_tokens"),
        },
        "tool_calls": tool_names,
        "skill_names": skill_names or None,
    }


_CLEAN_DDL = """
CREATE TABLE turn (
    turn_uuid TEXT PRIMARY KEY, session_id TEXT, parent_session_id TEXT,
    ts TEXT, project TEXT, git_branch TEXT, role TEXT, model TEXT,
    attribution_skill TEXT, input_tokens INTEGER, output_tokens INTEGER,
    cache_read INTEGER, cache_creation INTEGER, tool_calls TEXT,
    finish_reason TEXT, skill_names TEXT
)
"""
_CLEAN_COLS = (
    "turn_uuid", "session_id", "parent_session_id", "ts", "project",
    "git_branch", "role", "model", "attribution_skill", "input_tokens",
    "output_tokens", "cache_read", "cache_creation", "tool_calls",
    "finish_reason", "skill_names",
)
_REF_DDL = """
CREATE TABLE reference_hit (
    hit_uid TEXT PRIMARY KEY, session_id TEXT, turn_uuid TEXT, skill TEXT,
    reference_path TEXT, byte_len INTEGER, ts TEXT
)
"""
_REF_COLS = ("hit_uid", "session_id", "turn_uuid", "skill", "reference_path", "byte_len", "ts")
_SCRIPT_DDL = """
CREATE TABLE script_call (
    call_uid TEXT PRIMARY KEY, session_id TEXT, turn_uuid TEXT, skill TEXT,
    script_path TEXT, exit_code INTEGER, duration_ms INTEGER, ts TEXT
)
"""
_SCRIPT_COLS = ("call_uid", "session_id", "turn_uuid", "skill", "script_path", "exit_code", "duration_ms", "ts")


def _project_of(cwd: str | None) -> str | None:
    if not cwd:
        return None
    return cwd.rstrip("/").rsplit("/", 1)[-1] or cwd


def _write_aux_clean(table: str, ddl: str, rows: list[dict[str, Any]], columns: tuple[str, ...]) -> None:
    db_path = clean_path(SOURCE)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        conn.execute(f"DROP TABLE IF EXISTS {table}")
        conn.execute(ddl)
        if rows:
            placeholders = ", ".join("?" for _ in columns)
            conn.executemany(
                f"INSERT OR REPLACE INTO {table} ({', '.join(columns)}) VALUES ({placeholders})",
                [tuple(row.get(column) for column in columns) for row in rows],
            )
        conn.commit()


def normalize() -> int:
    # Last-write-wins by uuid: read_raw yields shards in ascending date order,
    # so a newer shard's record for the same turn overwrites an older one. This
    # matters when a full re-collect (watermark reset) re-emits historical turns
    # with fields the old parser dropped (e.g. stop_reason) — the newer, richer
    # record must win, not the first (older, sparser) one seen.
    rows: dict[str, dict[str, Any]] = {}
    reference_rows: dict[str, dict[str, Any]] = {}
    script_rows: dict[str, dict[str, Any]] = {}
    for idx, rec in enumerate(read_raw(SOURCE), start=1):
        kind = rec.get("_kind")
        if kind == "reference_hit":
            row = {"hit_uid": rec.get("hit_uid"), "session_id": rec.get("sessionId"),
                   "turn_uuid": rec.get("turn_uuid"), "skill": rec.get("skill"),
                   "reference_path": rec.get("reference_path"), "byte_len": rec.get("byte_len"),
                   "ts": rec.get("timestamp")}
            if row["hit_uid"]:
                reference_rows[str(row["hit_uid"])] = row
            continue
        if kind == "script_call":
            row = {"call_uid": rec.get("call_uid"), "session_id": rec.get("sessionId"),
                   "turn_uuid": rec.get("turn_uuid"), "skill": rec.get("skill"),
                   "script_path": rec.get("script_path"), "exit_code": rec.get("exit_code"),
                   "duration_ms": rec.get("duration_ms"), "ts": rec.get("timestamp")}
            call_uid = row["call_uid"]
            if call_uid:
                previous = script_rows.get(str(call_uid))
                if previous is None or any(row[field] is not None and previous[field] is None
                                           for field in ("exit_code", "duration_ms")):
                    script_rows[str(call_uid)] = row
            continue
        uuid = rec.get("uuid") or f"{rec.get('sessionId') or 'turn'}:{rec.get('timestamp') or idx}:{idx}"
        u = rec.get("usage") or {}
        tc = rec.get("tool_calls") or []
        skills = rec.get("skill_names") or []
        attr_skill = rec.get("attributionSkill") or (skills[0] if skills else None)
        rows[str(uuid)] = {
            "turn_uuid": str(uuid),
            "session_id": rec.get("sessionId"),
            "parent_session_id": rec.get("session_id_lineage"),
            "ts": rec.get("timestamp"),
            "project": _project_of(rec.get("cwd")),
            "git_branch": rec.get("gitBranch"),
            "role": rec.get("role"),
            "model": rec.get("model"),
            "attribution_skill": attr_skill,
            "input_tokens": u.get("input_tokens"),
            "output_tokens": u.get("output_tokens"),
            "cache_read": u.get("cache_read_input_tokens"),
            "cache_creation": u.get("cache_creation_input_tokens"),
            "tool_calls": json.dumps(tc, ensure_ascii=False),
            "finish_reason": rec.get("stop_reason"),
            "skill_names": json.dumps(skills, ensure_ascii=False) if skills else None,
        }
    turn_count = write_clean(SOURCE, "turn", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
    if write_clean is _DEFAULT_WRITE_CLEAN:
        _write_aux_clean("reference_hit", _REF_DDL, list(reference_rows.values()), _REF_COLS)
        _write_aux_clean("script_call", _SCRIPT_DDL, list(script_rows.values()), _SCRIPT_COLS)
    return turn_count
