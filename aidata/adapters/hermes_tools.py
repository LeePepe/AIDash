"""Hermes tool and skill-view usage from ``~/.hermes/state.db``.

The legacy tool stream remains a per-tool daily rollup in ``tool_day``.  The
skill stream is collected alongside it with its own watermark and produces
``skill_day``.  Only tool metadata, or a skill name plus call id and timestamp,
leaves Hermes; message bodies and arguments do not.
"""

from __future__ import annotations

import json
from typing import Any

from cleanio import write_clean
from config import HERMES_STATE_DB
from rawio import read_raw, write_raw
from sqlite_ro import query_ro
from state import get_watermark, set_watermark
from timeutil import CST as _CST  # noqa: F401 (re-export seam)
from timeutil import epoch_s_to_cst_day

SOURCE = "hermes_tools"
SKILL_SOURCE = "hermes_tools_skill"

_TOOL_SELECT = (
    "SELECT tool_name, timestamp FROM messages "
    "WHERE tool_name IS NOT NULL AND timestamp > ? ORDER BY timestamp ASC"
)
_SKILL_SELECT = (
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
    """Collect legacy tools and named skills with independent watermarks."""
    if not HERMES_STATE_DB.exists():
        return 0

    tool_watermark = float(get_watermark(SOURCE) or 0)
    tool_rows = query_ro(HERMES_STATE_DB, _TOOL_SELECT, (tool_watermark,))
    if tool_rows:
        tool_written = write_raw(SOURCE, tool_rows)
        set_watermark(SOURCE, max(float(row["timestamp"]) for row in tool_rows))
    else:
        tool_written = 0

    skill_watermark = float(get_watermark(SKILL_SOURCE) or 0)
    skill_rows = query_ro(HERMES_STATE_DB, _SKILL_SELECT, (skill_watermark,))
    records: list[dict[str, Any]] = []
    for row in skill_rows:
        records.extend(_skill_calls(row.get("tool_calls"), row.get("timestamp")))
    if records:
        skill_written = write_raw(SOURCE, records)
    else:
        skill_written = 0
    timestamps = [row.get("timestamp") for row in skill_rows
                  if row.get("timestamp") is not None]
    if timestamps:
        set_watermark(SKILL_SOURCE, max(float(ts) for ts in timestamps))
    return tool_written + skill_written


_CLEAN_DDL = """
CREATE TABLE skill_day (
    day TEXT,
    skill TEXT,
    n INTEGER,
    PRIMARY KEY (day, skill)
)
"""
_CLEAN_COLS = ("day", "skill", "n")

_TOOL_CLEAN_DDL = """
CREATE TABLE tool_day (
    day TEXT, tool_name TEXT, n INTEGER,
    PRIMARY KEY (day, tool_name)
)
"""
_TOOL_CLEAN_COLS = ("day", "tool_name", "n")


def _cst_day(ts: Any) -> str | None:
    """Compatibility seam for the adapter's fixed-CST conversion."""
    return epoch_s_to_cst_day(ts)


def normalize() -> int:
    """Rebuild both legacy tool counts and deduplicated skill counts."""
    tool_counts: dict[tuple[str, str], int] = {}
    calls: dict[str, dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        tool_name = record.get("tool_name")
        if isinstance(tool_name, str) and tool_name:
            day = _cst_day(record.get("timestamp"))
            if day is not None:
                key = (day, tool_name)
                tool_counts[key] = tool_counts.get(key, 0) + 1
        call_id = record.get("call_id")
        skill = record.get("skill")
        if isinstance(call_id, str) and call_id and isinstance(skill, str) and skill:
            calls[call_id] = record
    counts: dict[tuple[str, str], int] = {}
    for record in calls.values():
        day = _cst_day(record.get("timestamp"))
        if day is None:
            continue
        key = (day, record["skill"])
        counts[key] = counts.get(key, 0) + 1
    rows = [{"day": day, "skill": skill, "n": n}
            for (day, skill), n in counts.items()]
    tool_rows = [{"day": day, "tool_name": tool_name, "n": n}
                 for (day, tool_name), n in tool_counts.items()]
    write_clean(SOURCE, "tool_day", _TOOL_CLEAN_DDL, tool_rows, _TOOL_CLEAN_COLS)
    return write_clean(SOURCE, "skill_day", _CLEAN_DDL, rows, _CLEAN_COLS)
