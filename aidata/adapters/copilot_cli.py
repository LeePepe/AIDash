"""Metadata-only Copilot CLI skill attribution from the local session store."""

from __future__ import annotations

import hashlib
import re
import sqlite3
from collections import Counter
from datetime import datetime, timedelta, timezone
from typing import Any

from cleanio import write_clean
from config import COPILOT_SESSION_DB
from rawio import read_raw, write_raw
from state import get_watermark, set_watermark
from timeutil import epoch_s_to_cst_day

SOURCE = "copilot_cli"
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
                    rows = db.execute(
                        f"SELECT {selected} FROM {table} WHERE substr({stamp}, 1, 10) BETWEEN ? AND ? ORDER BY {stamp} LIMIT 100000",
                        (cutoff, today.isoformat()),
                    )
                    for session_id, turn_id, timestamp, *texts in rows:
                        if not session_id or turn_id is None or not _cst_day(timestamp):
                            continue
                        for skill in sorted({skill for text in texts for skill in _metadata_skills(text)}):
                            event = _skill_event(str(session_id), int(turn_id), str(timestamp), skill)
                            events.setdefault(event["event_id"], event)
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
    return write_clean(SOURCE, "skill_day", _CLEAN_DDL, rows, _CLEAN_COLS)
