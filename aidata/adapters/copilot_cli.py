"""Metadata-only Copilot CLI skill attribution from the local session store."""

from __future__ import annotations

import hashlib
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
    r"(?:^|[\s/\\])skills[/\\](?P<skill>[A-Za-z0-9][A-Za-z0-9._-]{0,127})"
    r"[/\\](?P<kind>references|scripts)[/\\](?P<rel>[^\s\"'`()<>]+)"
)


def _metric_events(session_id: str, turn_id: int, timestamp: str, text: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for index, match in enumerate(_PATH_RE.finditer(text)):
        skill = match.group("skill")
        relative = match.group("rel").lstrip("/").lstrip(chr(92)).rstrip("/").rstrip(chr(92))
        canonical = f"skills/{skill}/{match.group('kind')}/{relative}"
        identity = f"{session_id}\0{turn_id}\0{canonical}\0{index}"
        base = {"session_id": session_id, "turn_id": turn_id, "timestamp": timestamp, "skill": skill}
        if match.group("kind") == "references":
            byte_len = len(canonical.encode())
            for cand_root in (Path.home() / "Development" / "user-skills", Path.home() / ".agents", Path.home() / ".copilot"):
                cand_file = cand_root / canonical
                if cand_file.is_file():
                    try:
                        byte_len = cand_file.stat().st_size
                        break
                    except OSError:
                        pass
            events.append({"kind": "reference_hit", "hit_uid": hashlib.sha256(identity.encode()).hexdigest(),
                           "reference_path": canonical, "byte_len": byte_len, **base})
        else:
            events.append({"kind": "script_call", "call_uid": hashlib.sha256(identity.encode()).hexdigest(),
                           "script_path": canonical, "exit_code": None, "duration_ms": None, **base})
    return events


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
                text_columns = [name for name in ("user_message", "assistant_response") if name in columns] if table == "turns" else ["file_path"] if "file_path" in columns else []
                if not text_columns:
                    continue
                selected = ", ".join(["session_id", turn_col, stamp, *text_columns])
                try:
                    rows = list(db.execute(
                        f"SELECT {selected} FROM {table} WHERE substr({stamp}, 1, 10) BETWEEN ? AND ? ORDER BY {stamp} LIMIT 100000",
                        (cutoff, today.isoformat()),
                    ))
                    turn_stamps: dict[tuple[str, int], datetime] = {}
                    if table == "turns":
                        for session_id, turn_id, timestamp, *_ in rows:
                            if session_id and turn_id is not None:
                                try:
                                    parsed_ts = datetime.fromisoformat(str(timestamp).replace("Z", "+00:00"))  # noqa: FURB162
                                    if parsed_ts.tzinfo is None:
                                        parsed_ts = parsed_ts.replace(tzinfo=timezone.utc)  # noqa: UP017
                                    turn_stamps[(str(session_id), int(turn_id))] = parsed_ts
                                except ValueError:
                                    pass
                    for session_id, turn_id, timestamp, *texts in rows:
                        if not session_id or turn_id is None or not _cst_day(timestamp):
                            continue
                        text_values = [text for text in texts if isinstance(text, str)]
                        for skill in sorted({skill for text in text_values for skill in _metadata_skills(text)}):
                            event = _skill_event(str(session_id), int(turn_id), str(timestamp), skill)
                            events.setdefault(event["event_id"], event)
                        cur_ts = turn_stamps.get((str(session_id), int(turn_id)))
                        nxt_ts = turn_stamps.get((str(session_id), int(turn_id) + 1))
                        est_ms = int(max(0.0, min(600000.0, (nxt_ts - cur_ts).total_seconds() * 1000))) if (cur_ts and nxt_ts and nxt_ts > cur_ts) else None
                        for metric_event in (event for text in text_values for event in _metric_events(str(session_id), int(turn_id), str(timestamp), text)):
                            if metric_event.get("kind") == "script_call" and est_ms is not None:
                                metric_event["duration_ms"] = est_ms
                            events.setdefault(metric_event.get("hit_uid") or metric_event.get("call_uid"), metric_event)
                except sqlite3.Error:
                    continue  # One missing/legacy table must not hide another.
    except sqlite3.Error:
        return 0
    fresh = [event for key, event in events.items() if key not in seen]
    if fresh:
        write_raw(SOURCE, fresh)
    seen.update({key: event["timestamp"][:10] for key, event in events.items()})
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
