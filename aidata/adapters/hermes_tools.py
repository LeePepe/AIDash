"""Hermes skill-view usage from ``~/.hermes/state.db``.

Only assistant ``tool_calls`` for the ``skill_view`` function are collected.
The raw record deliberately keeps the call id, timestamp, and skill name only;
tool arguments and message bodies never leave Hermes.  Normalization produces
one row per fixed-CST day and skill, and deduplicates repeated observations by
tool-call id.
"""

from __future__ import annotations

import json
from typing import Any

from cleanio import write_clean
from config import HERMES_STATE_DB
from rawio import read_raw, write_raw
from sqlite_ro import query_ro
from state import get_watermark, set_watermark
from timeutil import epoch_s_to_cst_day

SOURCE = "hermes_tools"

_SELECT = (
    "SELECT timestamp, tool_calls FROM messages "
    "WHERE role = 'assistant' AND tool_calls IS NOT NULL AND timestamp > ? "
    "ORDER BY timestamp ASC"
)


def _skill_calls(tool_calls: Any, timestamp: Any) -> list[dict[str, Any]]:
    """Extract named ``skill_view`` calls without retaining prompt text."""
    if not isinstance(tool_calls, str):
        return []
    try:
        calls = json.loads(tool_calls)
    except (TypeError, ValueError):
        return []
    if not isinstance(calls, list):
        return []
    out: list[dict[str, Any]] = []
    for call in calls:
        if not isinstance(call, dict):
            continue
        function = call.get("function")
        if not isinstance(function, dict) or function.get("name") != "skill_view":
            continue
        arguments = function.get("arguments")
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except (TypeError, ValueError):
                continue
        if not isinstance(arguments, dict):
            continue
        skill = arguments.get("name")
        if not isinstance(skill, str) or not skill:
            continue
        call_id = call.get("call_id") or call.get("id")
        if not isinstance(call_id, str) or not call_id:
            continue
        out.append({"call_id": call_id, "timestamp": timestamp, "skill": skill})
    return out


def collect() -> int:
    """Collect newly observed skill calls; missing Hermes degrades to zero."""
    if not HERMES_STATE_DB.exists():
        return 0
    watermark = float(get_watermark(SOURCE) or 0)
    rows = query_ro(HERMES_STATE_DB, _SELECT, (watermark,))
    records: list[dict[str, Any]] = []
    for row in rows:
        records.extend(_skill_calls(row.get("tool_calls"), row.get("timestamp")))
    if records:
        written = write_raw(SOURCE, records)
    else:
        written = 0
    timestamps = [r.get("timestamp") for r in rows if r.get("timestamp") is not None]
    if timestamps:
        set_watermark(SOURCE, max(float(ts) for ts in timestamps))
    return written


_CLEAN_DDL = """
CREATE TABLE skill_day (
    day TEXT,
    skill TEXT,
    n INTEGER,
    PRIMARY KEY (day, skill)
)
"""
_CLEAN_COLS = ("day", "skill", "n")


def normalize() -> int:
    """Rebuild daily skill counts from raw history, deduping call ids."""
    calls: dict[str, dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        call_id = record.get("call_id")
        skill = record.get("skill")
        if isinstance(call_id, str) and call_id and isinstance(skill, str) and skill:
            calls[call_id] = record
    counts: dict[tuple[str, str], int] = {}
    for record in calls.values():
        day = epoch_s_to_cst_day(record.get("timestamp"))
        if day is None:
            continue
        key = (day, record["skill"])
        counts[key] = counts.get(key, 0) + 1
    rows = [{"day": day, "skill": skill, "n": n}
            for (day, skill), n in counts.items()]
    return write_clean(SOURCE, "skill_day", _CLEAN_DDL, rows, _CLEAN_COLS)
