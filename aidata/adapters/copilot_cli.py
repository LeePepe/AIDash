"""Metadata-only Copilot CLI skill attribution from the local session store."""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import COPILOT_SESSION_DB
from rawio import read_raw, write_raw
from state import get_watermark, set_watermark
from timeutil import epoch_s_to_cst_day

SOURCE = "copilot_cli"
_PATH_RE = re.compile(
    r"(?:^|[\s/\\=:\"'])skills[/\\](?P<skill>[A-Za-z0-9][A-Za-z0-9._-]{0,127})"
    r"[/\\](?P<kind>references|scripts)[/\\](?P<rel>[^\s\"'`;|&()<>]+)"
)
_READ_TOOLS = frozenset({"view", "read", "read_file"})
_SHELL_TOOLS = frozenset({"bash", "shell", "terminal", "execute_code"})
_EXEC_SEGMENT_RE = re.compile(
    r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)*(?:sudo\s+|env\s+|nohup\s+|time\s+)*"
    r"(?:(?:python3?|/usr/bin/python3?|bash|sh|zsh|node|npx|ruby|perl|uv\s+run)"
    r"(?:\s+(?!-[cm]\b)-\S+)*\s+)?"
    r"(?P<target>[^\s\"'`;|&()<>]*skills[/\\][A-Za-z0-9][A-Za-z0-9._-]{0,127}"
    r"[/\\]scripts[/\\][^\s\"'`;|&()<>]+)"
)
_SHELL_READ_RE = re.compile(
    r"\b(?:cat|head|tail|sed|awk|less|more|bat|jq)\b[^\n;|&]*"
    r"(?P<target>[^\s\"'`;|&()<>]*skills[/\\][A-Za-z0-9][A-Za-z0-9._-]{0,127}"
    r"[/\\]references[/\\][^\s\"'`;|&()<>]+)"
)


def _reference_byte_len(canonical: str) -> int:
    byte_len = len(canonical.encode())
    for cand_root in (Path.home() / "Development" / "user-skills", Path.home() / ".agents", Path.home() / ".copilot"):
        cand_file = cand_root / canonical
        if cand_file.is_file():
            try:
                return cand_file.stat().st_size
            except OSError:
                pass
    return byte_len


def _canonical_copilot_target(raw_target: str, expected_kind: str) -> tuple[str, str] | None:
    match = _PATH_RE.search(raw_target)
    if not match or match.group("kind") != expected_kind:
        return None
    skill = match.group("skill")
    relative = match.group("rel").lstrip("/").lstrip(chr(92)).rstrip("/").rstrip(chr(92))
    if not relative:
        return None
    return skill, f"skills/{skill}/{expected_kind}/{relative}"


def _elapsed_ms(start: Any, end: Any) -> int | None:
    try:
        left = datetime.fromisoformat(str(start).replace("Z", "+00:00"))  # noqa: FURB162
        right = datetime.fromisoformat(str(end).replace("Z", "+00:00"))  # noqa: FURB162
        if left.tzinfo is None:
            left = left.replace(tzinfo=timezone.utc)  # noqa: UP017
        if right.tzinfo is None:
            right = right.replace(tzinfo=timezone.utc)  # noqa: UP017
        return int(max(0.0, (right - left).total_seconds() * 1000))
    except (TypeError, ValueError):
        return None


def _metric_events(
    session_id: str, turn_id: Any, timestamp: str, text: str, *, tool_name: str = "view"
) -> list[dict[str, Any]]:
    tool = tool_name.strip().lower()
    events: list[dict[str, Any]] = []
    base_common = {"session_id": session_id, "turn_id": turn_id, "timestamp": timestamp}
    if tool in _READ_TOOLS:
        parsed = _canonical_copilot_target(text, "references")
        if parsed is not None:
            skill, canonical = parsed
            identity = f"{session_id}\0{turn_id}\0{canonical}\00"
            events.append({
                "kind": "reference_hit",
                "hit_uid": hashlib.sha256(identity.encode()).hexdigest(),
                "skill": skill,
                "reference_path": canonical,
                "byte_len": _reference_byte_len(canonical),
                **base_common,
            })
        return events
    if tool in _SHELL_TOOLS:
        seen_refs: set[str] = set()
        for idx, ref_match in enumerate(_SHELL_READ_RE.finditer(text)):
            parsed = _canonical_copilot_target(ref_match.group("target"), "references")
            if parsed is None or parsed[1] in seen_refs:
                continue
            skill, canonical = parsed
            seen_refs.add(canonical)
            identity = f"{session_id}\0{turn_id}\0{canonical}\0ref:{idx}"
            events.append({
                "kind": "reference_hit",
                "hit_uid": hashlib.sha256(identity.encode()).hexdigest(),
                "skill": skill,
                "reference_path": canonical,
                "byte_len": _reference_byte_len(canonical),
                **base_common,
            })
        seen_scripts: set[str] = set()
        for idx, seg in enumerate(re.split(r"(?:&&|\|\||;|\n)", text)):
            exec_match = _EXEC_SEGMENT_RE.match(seg)
            if not exec_match:
                continue
            parsed = _canonical_copilot_target(exec_match.group("target"), "scripts")
            if parsed is None or parsed[1] in seen_scripts:
                continue
            skill, canonical = parsed
            seen_scripts.add(canonical)
            identity = f"{session_id}\0{turn_id}\0{canonical}\0{idx}"
            events.append({
                "kind": "script_call",
                "call_uid": hashlib.sha256(identity.encode()).hexdigest(),
                "skill": skill,
                "script_path": canonical,
                "exit_code": None,
                "duration_ms": None,
                **base_common,
            })
    return events


def _scan_session_state_events(
    state_dir: Path, cutoff_date: str, today_date: str, events: dict[str, dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    completed_scripts: dict[str, dict[str, Any]] = {}
    if not state_dir.is_dir():
        return completed_scripts
    cutoff_epoch = (
        datetime.fromisoformat(cutoff_date).replace(tzinfo=timezone.utc).timestamp() - 86400  # noqa: UP017
    )
    for session_dir in state_dir.iterdir():
        if not session_dir.is_dir():
            continue
        ev_file = session_dir / "events.jsonl"
        try:
            if not ev_file.is_file() or ev_file.stat().st_mtime < cutoff_epoch:
                continue
        except OSError:
            continue
        session_id = session_dir.name
        pending_calls: dict[str, list[dict[str, Any]]] = {}
        try:
            with ev_file.open("r", encoding="utf-8", errors="replace") as fh:
                for raw_line in fh:
                    line = raw_line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    ev_type = obj.get("type")
                    ts = str(obj.get("timestamp") or "")
                    day = _cst_day(ts)
                    data = obj.get("data") or {}
                    if ev_type == "tool.execution_start" and day and cutoff_date <= day <= today_date:
                        tool_name = str(data.get("toolName") or "")
                        call_id = str(data.get("toolCallId") or "")
                        turn_id = data.get("turnId") or call_id or 0
                        args = data.get("arguments") or {}
                        if isinstance(args, str):
                            try:
                                args = json.loads(args)
                            except json.JSONDecodeError:
                                args = {}
                        target_text = ""
                        if tool_name.lower() in _READ_TOOLS and isinstance(args, dict):
                            target_text = str(args.get("path") or args.get("file_path") or "")
                        elif tool_name.lower() in _SHELL_TOOLS and isinstance(args, dict):
                            target_text = str(args.get("command") or args.get("cmd") or "")
                        if not target_text:
                            continue
                        extracted = _metric_events(
                            session_id, call_id or turn_id, ts, target_text, tool_name=tool_name
                        )
                        for item in extracted:
                            uid = item.get("hit_uid") or item.get("call_uid")
                            if uid:
                                events[str(uid)] = item
                            if item.get("kind") == "script_call" and call_id:
                                pending_calls.setdefault(call_id, []).append(item)
                    elif ev_type == "tool.execution_complete":
                        call_id = str(data.get("toolCallId") or "")
                        matched = pending_calls.pop(call_id, None)
                        if not matched:
                            continue
                        success = data.get("success")
                        res_text = json.dumps(data.get("result") or "", ensure_ascii=False)
                        code_m = re.search(r"exit code\s+(-?\d+)", res_text, re.IGNORECASE)
                        exit_code = (
                            int(code_m.group(1))
                            if code_m
                            else (0 if success is True else 1 if success is False else None)
                        )
                        for item in matched:
                            item["exit_code"] = exit_code
                            item["duration_ms"] = _elapsed_ms(item.get("timestamp"), ts)
                            if item.get("call_uid"):
                                completed_scripts[str(item["call_uid"])] = item
        except OSError:
            continue
    return completed_scripts


_SKILL_PATTERNS = (
    re.compile(r"(?:^|\n)\s*/skill\s+([A-Za-z0-9][A-Za-z0-9._-]{0,127})(?=\s|$)", re.IGNORECASE),
    re.compile(r'''<skill-context\s+name=["']([A-Za-z0-9][A-Za-z0-9._-]{0,127})["']''', re.IGNORECASE),
    re.compile(r"(?:^|[/\\])skills[/\\]([A-Za-z0-9][A-Za-z0-9._-]{0,127})[/\\]SKILL\.md\b", re.IGNORECASE),
)


def _metadata_skills(text: str | None) -> list[str]:
    if not isinstance(text, str):
        return []
    return sorted({match.group(1) for pattern in _SKILL_PATTERNS for match in pattern.finditer(text)})


def _skill_event(session_id: str, turn_id: int, timestamp: str, skill: str) -> dict[str, Any]:
    identity = f"{session_id}\0{turn_id}\0{skill}"
    return {
        "event_id": hashlib.sha256(identity.encode("utf-8")).hexdigest(),
        "turn_id": turn_id, "session_id": session_id, "timestamp": timestamp, "skill": skill,
    }


def _cst_day(timestamp: Any) -> str | None:
    try:
        stamp = datetime.fromisoformat(str(timestamp).replace("Z", "+00:00"))  # noqa: FURB162 - Python 3.9 cannot parse Z
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=timezone.utc)  # noqa: UP017 - hook Python 3.9
        return stamp.astimezone(timezone(timedelta(hours=8))).date().isoformat()
    except ValueError:
        return epoch_s_to_cst_day(timestamp)


def collect(*, now: datetime | None = None) -> int:
    """Scan a bounded 30-day window, persisting identities and metadata only.

    Turns and session_files can describe the same invocation: count one skill
    per session/turn, not one count per repeated marker or body/file population.
    Re-scan mutable rows so later skill-context/file metadata is not missed.
    """
    from adapters import cloud_sync

    cloud_sync.pull_icloud_telemetry_shards()
    if not COPILOT_SESSION_DB.exists():
        return 0
    today = (now or datetime.now(timezone.utc)).date()  # noqa: UP017 - hook Python 3.9
    cutoff = (today - timedelta(days=30)).isoformat()
    watermark = get_watermark(SOURCE)
    previous = watermark.get("seen", {}) if isinstance(watermark, dict) else {}
    seen = {key: day for key, day in previous.items() if isinstance(day, str) and day >= cutoff}
    events: dict[str, dict[str, Any]] = {}
    try:
        with sqlite3.connect(COPILOT_SESSION_DB.resolve().as_uri() + "?mode=ro", uri=True) as db:
            db.execute("PRAGMA query_only=ON")
            for table, stamp in (("turns", "timestamp"), ("session_files", "first_seen_at")):
                columns = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
                if not {"session_id", stamp}.issubset(columns):
                    continue
                turn_col = "turn_index" if "turn_index" in columns else "id" if "id" in columns else None
                if turn_col is None:
                    continue  # No stable event identity: do not manufacture one.
                text_columns = (
                    [name for name in ("user_message", "assistant_response") if name in columns]
                    if table == "turns"
                    else ["file_path", *(["tool_name"] if "tool_name" in columns else [])]
                    if "file_path" in columns
                    else []
                )
                if not text_columns:
                    continue
                selected = ", ".join(["session_id", turn_col, stamp, *text_columns])
                try:
                    rows = list(db.execute(
                        f"SELECT {selected} FROM {table} WHERE substr({stamp}, 1, 10) BETWEEN ? AND ? ORDER BY {stamp} LIMIT 100000",
                        (cutoff, today.isoformat()),
                    ))
                    for session_id, turn_id, timestamp, *rest in rows:
                        if not session_id or turn_id is None or not _cst_day(timestamp):
                            continue
                        if table == "session_files":
                            file_path = rest[0] if rest else None
                            tool_name = str(rest[1]) if len(rest) > 1 and rest[1] else ""
                            text_values = [file_path] if isinstance(file_path, str) else []
                            for skill in sorted({skill for text in text_values for skill in _metadata_skills(text)}):
                                event = _skill_event(str(session_id), int(turn_id), str(timestamp), skill)
                                events.setdefault(event["event_id"], event)
                            if isinstance(file_path, str) and tool_name.lower() in _READ_TOOLS:
                                for metric_event in _metric_events(
                                    str(session_id), int(turn_id), str(timestamp), file_path, tool_name=tool_name
                                ):
                                    events.setdefault(metric_event.get("hit_uid") or metric_event.get("call_uid"), metric_event)
                        else:
                            text_values = [text for text in rest if isinstance(text, str)]
                            for skill in sorted({skill for text in text_values for skill in _metadata_skills(text)}):
                                event = _skill_event(str(session_id), int(turn_id), str(timestamp), skill)
                                events.setdefault(event["event_id"], event)
                except sqlite3.Error:
                    continue  # One missing/legacy table must not hide another.
    except sqlite3.Error:
        return 0
    completed_scripts = _scan_session_state_events(
        COPILOT_SESSION_DB.parent / "session-state", cutoff, today.isoformat(), events
    )
    fresh = [
        event
        for key, event in events.items()
        if key not in seen or (key in completed_scripts and f"{key}:done" not in seen)
    ]
    if fresh:
        write_raw(SOURCE, fresh)
    seen.update({key: event["timestamp"][:10] for key, event in events.items()})
    seen.update({f"{key}:done": event["timestamp"][:10] for key, event in completed_scripts.items()})
    set_watermark(SOURCE, {"schema_version": 2, "seen": seen})
    return len(fresh)


_CLEAN_DDL = """
CREATE TABLE IF NOT EXISTS skill_day (
    day TEXT, skill TEXT, n INTEGER,
    PRIMARY KEY (day, skill)
)
"""
_CLEAN_COLS = ("day", "skill", "n")
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


def normalize() -> int:
    counts: Counter[tuple[str, str]] = Counter()
    seen: set[str] = set()
    for record in read_raw(SOURCE):
        if record.get("kind") in {"reference_hit", "script_call"}:
            continue
        day = _cst_day(record.get("timestamp"))
        skill = record.get("skill")
        identity = str(record.get("event_id") or f"{record.get('session_id')}:{record.get('turn_id')}:{skill}")
        if day and isinstance(skill, str) and skill and identity not in seen:
            seen.add(identity)
            counts[(day, skill)] += 1
    rows = [{"day": day, "skill": skill, "n": n} for (day, skill), n in counts.items()]
    skill_count = write_clean(SOURCE, "skill_day", _CLEAN_DDL, rows, _CLEAN_COLS)
    references: dict[str, dict[str, Any]] = {}
    scripts: dict[str, dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        if record.get("kind") == "reference_hit":
            row = {"hit_uid": record.get("hit_uid"), "session_id": record.get("session_id"),
                   "turn_uuid": record.get("turn_id"), "skill": record.get("skill"),
                   "reference_path": record.get("reference_path"), "byte_len": record.get("byte_len"),
                   "ts": record.get("timestamp")}
            if row["hit_uid"]:
                references[str(row["hit_uid"])] = row
        elif record.get("kind") == "script_call":
            row = {"call_uid": record.get("call_uid"), "session_id": record.get("session_id"),
                   "turn_uuid": record.get("turn_id"), "skill": record.get("skill"),
                   "script_path": record.get("script_path"), "exit_code": record.get("exit_code"),
                   "duration_ms": record.get("duration_ms"), "ts": record.get("timestamp")}
            call_uid = row["call_uid"]
            if call_uid:
                previous = scripts.get(str(call_uid))
                if previous is None or any(row[field] is not None and previous[field] is None
                                           for field in ("exit_code", "duration_ms")):
                    scripts[str(call_uid)] = row
    write_clean(SOURCE, "reference_hit", _REF_DDL, list(references.values()), _REF_COLS)
    write_clean(SOURCE, "script_call", _SCRIPT_DDL, list(scripts.values()), _SCRIPT_COLS)
    return skill_count
