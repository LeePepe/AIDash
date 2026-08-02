"""memory_hermes_db adapter — Hermes holographic fact store (~/.hermes/memory_store.db).

L1 collect: read-only SELECT from `facts` (skip the hrr_vector BLOB — we only
record its presence). L2 normalize: one row per fact. Native key: category.

Verified caveat: retrieval_count / helpful_count / trust_score are ALL at their
defaults (0 / 0 / 0.5) — the runtime never writes them back. They are recorded
but flagged as non-functional; dead-asset detection must use created/updated age.
Stays at L2 — NOT merged.
"""

from __future__ import annotations

from typing import Any

from config import HERMES_MEMORY_DB
from rawio import write_raw, read_raw
from cleanio import write_clean
from sqlite_ro import query_ro
from state import get_watermark, set_watermark

SOURCE = "memory_hermes_db"


def collect() -> int:
    if not HERMES_MEMORY_DB.exists():
        return 0
    watermark = get_watermark(SOURCE) or ""
    records = query_ro(
        HERMES_MEMORY_DB,
        "SELECT fact_id, content, category, tags, trust_score, "
        "retrieval_count, helpful_count, created_at, updated_at, "
        "length(hrr_vector) AS hrr_bytes "
        "FROM facts WHERE updated_at > ? ORDER BY updated_at ASC",
        (watermark,),
    )
    if not records:
        return 0
    n = write_raw(SOURCE, records)
    set_watermark(SOURCE, max(r["updated_at"] or "" for r in records))
    return n


_CLEAN_DDL = """
CREATE TABLE fact (
    fact_id INTEGER PRIMARY KEY, content TEXT, category TEXT, tags TEXT,
    trust_score REAL, retrieval_count INTEGER, helpful_count INTEGER,
    created_at TEXT, updated_at TEXT, hrr_bytes INTEGER,
    counters_functional INTEGER  -- 0: verified non-functional in this runtime
)
"""
_CLEAN_COLS = ("fact_id", "content", "category", "tags", "trust_score",
               "retrieval_count", "helpful_count", "created_at", "updated_at",
               "hrr_bytes", "counters_functional")


def normalize() -> int:
    rows: dict[int, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        fid = rec.get("fact_id")
        if fid is None:
            continue
        rows[fid] = {
            "fact_id": fid,
            "content": rec.get("content"),
            "category": rec.get("category"),
            "tags": rec.get("tags"),
            "trust_score": rec.get("trust_score"),
            "retrieval_count": rec.get("retrieval_count"),
            "helpful_count": rec.get("helpful_count"),
            "created_at": rec.get("created_at"),
            "updated_at": rec.get("updated_at"),
            "hrr_bytes": rec.get("hrr_bytes"),
            "counters_functional": 0,  # counters are dead in this runtime
        }
    return write_clean(SOURCE, "fact", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
