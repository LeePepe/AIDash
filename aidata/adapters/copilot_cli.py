"""Metadata-only Copilot CLI skill attribution from the local session store."""

from __future__ import annotations

import re
import sqlite3
from collections import Counter
from typing import Any

from cleanio import write_clean
from config import COPILOT_SESSION_DB
from rawio import read_raw, write_raw
from state import get_watermark, set_watermark
from timeutil import epoch_s_to_cst_day

SOURCE = "copilot_cli"
_SKILL_RE = re.compile(r"(?:^|\s)/(?:skill|skills)\s+([A-Za-z0-9][A-Za-z0-9._/-]{0,127})", re.IGNORECASE)


def _metadata_skills(text: str | None) -> list[str]:
    if not isinstance(text, str):
        return []
    return sorted({match.group(1) for match in _SKILL_RE.finditer(text)})


def collect() -> int:
    if not COPILOT_SESSION_DB.exists():
        return 0
    last_id = int(get_watermark(SOURCE) or 0)
    rows: list[dict[str, Any]] = []
    try:
        with sqlite3.connect(f"file:{COPILOT_SESSION_DB}?mode=ro", uri=True) as db:
            for row in db.execute(
                "SELECT id, session_id, timestamp, assistant_response FROM turns WHERE id > ? ORDER BY id",
                (last_id,),
            ):
                turn_id, session_id, timestamp, assistant_response = row
                for skill in _metadata_skills(assistant_response):
                    rows.append({
                        "turn_id": int(turn_id),
                        "session_id": str(session_id),
                        "timestamp": str(timestamp or ""),
                        "skill": skill,
                    })
                last_id = int(turn_id)
    except sqlite3.Error:
        return 0
    if rows:
        write_raw(SOURCE, rows)
    if last_id > int(get_watermark(SOURCE) or 0):
        set_watermark(SOURCE, last_id)
    return len(rows)


_CLEAN_DDL = """
CREATE TABLE IF NOT EXISTS skill_day (
    day TEXT, skill TEXT, n INTEGER,
    PRIMARY KEY (day, skill)
)
"""
_CLEAN_COLS = ("day", "skill", "n")


def normalize() -> int:
    counts: Counter[tuple[str, str]] = Counter()
    for record in read_raw(SOURCE):
        day = epoch_s_to_cst_day(record.get("timestamp"))
        skill = record.get("skill")
        if day and isinstance(skill, str) and skill:
            counts[(day, skill)] += 1
    rows = [{"day": day, "skill": skill, "n": n} for (day, skill), n in counts.items()]
    return write_clean(SOURCE, "skill_day", _CLEAN_DDL, rows, _CLEAN_COLS)
