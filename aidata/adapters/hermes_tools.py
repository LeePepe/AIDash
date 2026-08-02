"""hermes_tools adapter — per-tool usage from Hermes messages (~/.hermes/state.db).

L1 collect: read-only SELECT of only `tool_name` + `timestamp` from the
`messages` table. Deliberately NEVER reads `content` or `tool_calls` — those
carry prompt/command bodies. Only tool-invocation metadata leaves the source DB.
`timestamp` is the watermark (epoch SECONDS, float).

L2 normalize: rebuilds a per-CST-day x per-tool count table (`tool_day`) from the
full raw history. Day bucketing uses the fixed +8h offset (ADR-2 / ADR-22), the
same convention as `date(started_at,'unixepoch','+8 hours')` in the session SQL.
Stays at L2 clean — NOT merged into the warehouse (ADR-13); consumers query the
clean DB directly (like the memory_* and state_db sources).

Degrade-safe (ADR-23): a missing DB collects 0 and normalizes to 0 — never raises.
"""

from __future__ import annotations

from typing import Any

from config import HERMES_STATE_DB
from timeutil import epoch_s_to_cst_day
from timeutil import CST as _CST  # noqa: F401 (re-export seam)
from rawio import write_raw, read_raw
from cleanio import write_clean
from sqlite_ro import query_ro
from state import get_watermark, set_watermark

SOURCE = "hermes_tools"

# _CST re-exported from timeutil for any importer that referenced it (seam).

# SAFE columns only — tool_name + timestamp. NEVER content/tool_calls (prompt/
# command bodies). This is the enforced red line, not an optional filter.
_SELECT = (
    "SELECT tool_name, timestamp FROM messages "
    "WHERE tool_name IS NOT NULL AND timestamp > ? ORDER BY timestamp ASC"
)


def collect() -> int:
    """Collect new tool-call rows since the watermark. Returns count (0 on degrade)."""
    if not HERMES_STATE_DB.exists():
        return 0
    watermark = float(get_watermark(SOURCE) or 0)
    records = query_ro(HERMES_STATE_DB, _SELECT, (watermark,))
    if not records:
        return 0
    n = write_raw(SOURCE, records)
    set_watermark(SOURCE, max(float(r["timestamp"]) for r in records))
    return n


_CLEAN_DDL = """
CREATE TABLE tool_day (
    day TEXT, tool_name TEXT, n INTEGER,
    PRIMARY KEY (day, tool_name)
)
"""
_CLEAN_COLS = ("day", "tool_name", "n")


def _cst_day(ts: Any) -> str | None:
    """Epoch SECONDS (float) -> 'YYYY-MM-DD' in CST, or None (thin wrapper; seam)."""
    return epoch_s_to_cst_day(ts)


def normalize() -> int:
    """Rebuild the per-day x per-tool count table from the full raw history."""
    counts: dict[tuple[str, str], int] = {}
    for rec in read_raw(SOURCE):
        tool_name = rec.get("tool_name")
        if not tool_name:
            continue
        day = _cst_day(rec.get("timestamp"))
        if day is None:
            continue
        key = (day, tool_name)
        counts[key] = counts.get(key, 0) + 1
    rows = [{"day": day, "tool_name": tool_name, "n": n}
            for (day, tool_name), n in counts.items()]
    return write_clean(SOURCE, "tool_day", _CLEAN_DDL, rows, _CLEAN_COLS)
