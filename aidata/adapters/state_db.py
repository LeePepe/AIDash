"""state_db adapter — Hermes per-session store (~/.hermes/state.db) (EXT-5, ADR-7/13).

L1 collect: read-only SELECT of SAFE columns from `sessions` (never system_prompt,
model_config, origin_json, or billing_* — those may embed prompts/credentials).
`started_at` is a watermark (epoch SECONDS, float).

L2 normalize: one row per session; derives `is_automated` from the `source`
dimension. Stays at L2 clean — NOT merged into the warehouse (ADR-13); the digest
queries the clean DB directly (like the memory_* sources).

Automation definition (ADR-7): AUTOMATED = {cron, subagent} — scheduled / agent-
spawned sessions with no human in the loop. Everything else (cli, acp, weixin,
unknown) is manual; `unknown` counts as manual (conservative — never overstates
automation). "Automation ratio" = automated / total per CST day.
"""

from __future__ import annotations

from typing import Any

from config import HERMES_STATE_DB
from rawio import write_raw, read_raw
from cleanio import write_clean
from sqlite_ro import query_ro
from state import get_watermark, set_watermark

SOURCE = "state_db"

# Sessions with no human in the loop. Everything else is treated as manual.
AUTOMATED_SOURCES = frozenset({"cron", "subagent"})

# SAFE columns only — deliberately excludes system_prompt/model_config/origin_json
# and all billing_* fields to keep prompts and credentials out of raw/.
# cache_read/cache_write/reasoning_tokens close a known token-accounting gap
# (cache reads dwarf plain input); end_reason is a coarse, non-sensitive enum.
_SELECT = (
    "SELECT id, started_at, ended_at, message_count, tool_call_count, "
    "input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, "
    "reasoning_tokens, end_reason, source, model "
    "FROM sessions WHERE started_at > ? ORDER BY started_at ASC"
)


def collect() -> int:
    """Collect new sessions since the watermark. Returns count (0 on degrade)."""
    if not HERMES_STATE_DB.exists():
        return 0
    watermark = float(get_watermark(SOURCE) or 0)
    records = query_ro(HERMES_STATE_DB, _SELECT, (watermark,))
    if not records:
        return 0
    n = write_raw(SOURCE, records)
    set_watermark(SOURCE, max(float(r["started_at"]) for r in records))
    return n


_CLEAN_DDL = """
CREATE TABLE session (
    session_id TEXT PRIMARY KEY, started_at REAL, ended_at REAL,
    message_count INTEGER, tool_call_count INTEGER,
    input_tokens INTEGER, output_tokens INTEGER,
    cache_read_tokens INTEGER, cache_write_tokens INTEGER,
    reasoning_tokens INTEGER, end_reason TEXT,
    source TEXT, model TEXT, is_automated INTEGER
)
"""
_CLEAN_COLS = ("session_id", "started_at", "ended_at", "message_count",
               "tool_call_count", "input_tokens", "output_tokens",
               "cache_read_tokens", "cache_write_tokens", "reasoning_tokens",
               "end_reason", "source", "model", "is_automated")


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        sid = rec.get("id")
        if not sid:
            continue
        source = rec.get("source")
        rows[sid] = {  # last write wins -> latest snapshot of each session
            "session_id": sid,
            "started_at": rec.get("started_at"),
            "ended_at": rec.get("ended_at"),
            "message_count": rec.get("message_count"),
            "tool_call_count": rec.get("tool_call_count"),
            "input_tokens": rec.get("input_tokens"),
            "output_tokens": rec.get("output_tokens"),
            "cache_read_tokens": rec.get("cache_read_tokens"),
            "cache_write_tokens": rec.get("cache_write_tokens"),
            "reasoning_tokens": rec.get("reasoning_tokens"),
            "end_reason": rec.get("end_reason"),
            "source": source,
            "model": rec.get("model"),
            "is_automated": 1 if source in AUTOMATED_SOURCES else 0,
        }
    return write_clean(SOURCE, "session", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
