"""pr_cache adapter — GitHub PR status cache (~/.claude/gh-pr-status-cache.json).

L1 collect: snapshot the whole flat map (URL -> status). Always full snapshot
(it's small and mutated in place).
L2 normalize: one fact_pr row per PR URL.
"""

from __future__ import annotations

import json
from typing import Any

from config import CLAUDE_PR_CACHE
from rawio import write_raw_snapshot, read_raw
from cleanio import write_clean

SOURCE = "pr_cache"


def collect() -> int:
    if not CLAUDE_PR_CACHE.exists():
        return 0
    try:
        cache = json.loads(CLAUDE_PR_CACHE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return 0
    if not isinstance(cache, dict):
        return 0
    records = [{"pr_url": url, **(rec if isinstance(rec, dict) else {})}
               for url, rec in cache.items()]
    return write_raw_snapshot(SOURCE, records)


_CLEAN_DDL = """
CREATE TABLE pr (
    pr_url TEXT PRIMARY KEY, number INTEGER, title TEXT, state TEXT,
    checks_passed INTEGER, checks_failed INTEGER, checks_pending INTEGER,
    additions INTEGER, deletions INTEGER
)
"""
_CLEAN_COLS = ("pr_url", "number", "title", "state", "checks_passed",
               "checks_failed", "checks_pending", "additions", "deletions")


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        url = rec.get("pr_url")
        if not url:
            continue
        checks = rec.get("checks") or {}
        rows[url] = {  # last write wins = latest snapshot
            "pr_url": url,
            "number": rec.get("number"),
            "title": rec.get("title"),
            "state": rec.get("state"),
            "checks_passed": checks.get("passed"),
            "checks_failed": checks.get("failed"),
            "checks_pending": checks.get("pending"),
            "additions": rec.get("additions"),
            "deletions": rec.get("deletions"),
        }
    return write_clean(SOURCE, "pr", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
