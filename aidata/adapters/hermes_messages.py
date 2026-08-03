"""hermes_messages adapter — full Hermes message history (~/.hermes/state.db).

**Grain: one message.** Distinct from `hermes_tools`, which is a per-CST-day x
per-tool COUNT built from the same table. That one is not widened in place for
three reasons, all of which would corrupt it:
  1. Different grain — `tool_day` is an aggregate; this is the raw event.
  2. Its watermark has already advanced past most history, so changing its
     SELECT would not backfill anything.
  3. Resetting that watermark to backfill would re-count already-collected tool
     messages, double-counting `tool_day`.
`hermes_tools` also sees only the 68.6k messages with a non-NULL `tool_name`;
this source covers all ~274k.

L1 collect: read-only `SELECT *` from `messages`, INCLUDING `content`,
`tool_calls`, and the reasoning columns — the prompt/response bodies. This is a
deliberate reversal of the previous "metadata only" stance (2026-08-03),
alongside making the repository private. The bodies are the point: nothing else
answers "what was actually asked, and what came back".

`SELECT *` rather than an allowlist so that columns Hermes adds later are not
silently dropped — an invisible failure mode.

Safety posture (same as state_db):
  - Repository is **private**.
  - `rawio.write_raw` -> `redact_obj` still strips API keys, bearer tokens and
    email local parts from every string. It matches credential SHAPES; it does
    NOT and cannot redact sensitive prose inside message bodies.
  - `L1_collect/raw/` and `L2_normalize/clean/` are gitignored and have never
    been committed. Do not weaken those rules.

Size: message `content` totals ~506 MB across ~274k rows, so this is by far the
heaviest source. L2 therefore stores metadata + a bounded preview, NOT the full
body; the full text stays in raw/.

L2 normalize: one row per message. Stays at L2 clean — NOT merged into the
warehouse (ADR-13), like state_db and the memory_* sources.

Degrade-safe (ADR-23): a missing DB collects 0 and normalizes to 0 — never raises.
"""

from __future__ import annotations

from typing import Any

from config import HERMES_STATE_DB
from timeutil import epoch_s_to_cst_day
from rawio import write_raw, read_raw
from cleanio import write_clean
from sqlite_ro import query_ro
from state import get_watermark, set_watermark

SOURCE = "hermes_messages"

# Full-column read; `timestamp` (epoch SECONDS, float) is the watermark.
_SELECT = "SELECT * FROM messages WHERE timestamp > ? ORDER BY timestamp ASC"

# Bounded preview kept in the clean DB. Long enough to recognise a message,
# short enough that ~274k rows stay queryable.
_PREVIEW_CHARS = 500


def collect() -> int:
    """Collect new messages since the watermark. Returns count (0 on degrade)."""
    if not HERMES_STATE_DB.exists():
        return 0
    watermark = float(get_watermark(SOURCE) or 0)
    records = query_ro(HERMES_STATE_DB, _SELECT, (watermark,))
    if not records:
        return 0
    n = write_raw(SOURCE, records)
    stamps = [r.get("timestamp") for r in records if r.get("timestamp") is not None]
    if stamps:
        set_watermark(SOURCE, max(float(t) for t in stamps))
    return n


_CLEAN_DDL = """
CREATE TABLE message (
    message_id TEXT PRIMARY KEY,
    session_id TEXT,
    day TEXT,                    -- CST calendar day (ADR-22: fixed +8h)
    ts REAL,
    role TEXT,
    tool_name TEXT,
    finish_reason TEXT,
    token_count INTEGER,
    -- Body kept as length + bounded preview, never the full text: `content`
    -- totals ~506 MB across the table. Full bodies remain in raw/.
    content_len INTEGER,
    content_preview TEXT,
    has_tool_calls INTEGER,
    has_reasoning INTEGER
)
"""
_CLEAN_COLS = ("message_id", "session_id", "day", "ts", "role", "tool_name",
               "finish_reason", "token_count", "content_len", "content_preview",
               "has_tool_calls", "has_reasoning")


def _preview(text: Any) -> tuple[int | None, str | None]:
    """(length, bounded preview) for a body field. (None, None) when absent."""
    if not isinstance(text, str) or not text:
        return None, None
    return len(text), text[:_PREVIEW_CHARS]


def _truthy(value: Any) -> int:
    """1 when a field carries content, else 0 — for cheap presence filters."""
    return 1 if value not in (None, "", [], {}) else 0


def normalize() -> int:
    """One row per message, keyed by message id (last write wins)."""
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        mid = rec.get("id")
        if not mid:
            continue
        clen, preview = _preview(rec.get("content"))
        rows[str(mid)] = {
            "message_id": str(mid),
            "session_id": rec.get("session_id"),
            "day": epoch_s_to_cst_day(rec.get("timestamp")),
            "ts": rec.get("timestamp"),
            "role": rec.get("role"),
            "tool_name": rec.get("tool_name"),
            "finish_reason": rec.get("finish_reason"),
            "token_count": rec.get("token_count"),
            "content_len": clen,
            "content_preview": preview,
            "has_tool_calls": _truthy(rec.get("tool_calls")),
            "has_reasoning": _truthy(
                rec.get("reasoning") or rec.get("reasoning_content")),
        }
    return write_clean(SOURCE, "message", _CLEAN_DDL, list(rows.values()),
                       _CLEAN_COLS)
