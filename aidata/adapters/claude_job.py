"""claude_job adapter — background agent jobs (~/.claude/jobs/*/).

L1 collect: read each job dir's state.json (mutated) + timeline.jsonl (append).
L2 normalize: one fact_task row per job, with cumulative `tokens`, sessionId,
and child PR links flattened out.
"""

from __future__ import annotations

import json
from typing import Any

from config import CLAUDE_JOBS_DIR
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark

SOURCE = "claude_job"


def collect() -> int:
    if not CLAUDE_JOBS_DIR.exists():
        return 0
    # Watermark = {job_dir: updatedAt} so we only re-emit changed jobs.
    seen: dict[str, str] = dict(get_watermark(SOURCE) or {})
    new_seen = dict(seen)
    batch: list[dict[str, Any]] = []

    for job_dir in CLAUDE_JOBS_DIR.iterdir():
        if not job_dir.is_dir():
            continue
        state_file = job_dir / "state.json"
        if not state_file.exists():
            continue
        try:
            state = json.loads(state_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        updated = state.get("updatedAt") or ""
        key = job_dir.name
        if seen.get(key) == updated:
            continue  # unchanged since last collect
        # Keep only the fields we need (drop respawnFlags/providerEnv etc.)
        batch.append({
            "job": key,
            "state": state.get("state"),
            "tokens": state.get("tokens"),
            "sessionId": state.get("sessionId"),
            "name": state.get("name"),
            "intent": state.get("intent"),
            "cwd": state.get("cwd"),
            "createdAt": state.get("createdAt"),
            "updatedAt": updated,
            "firstTerminalAt": state.get("firstTerminalAt"),
            "children": state.get("children") or [],
        })
        new_seen[key] = updated

    if batch:
        write_raw(SOURCE, batch)
    if new_seen != seen:
        set_watermark(SOURCE, new_seen)
    return len(batch)


_CLEAN_DDL = """
CREATE TABLE job (
    task_id TEXT PRIMARY KEY, state TEXT, tokens INTEGER, session_id TEXT,
    name TEXT, cwd TEXT, ts_start TEXT, ts_end TEXT, pr_url TEXT
)
"""
_CLEAN_COLS = ("task_id", "state", "tokens", "session_id", "name", "cwd",
               "ts_start", "ts_end", "pr_url")


def _first_pr(children: list) -> str | None:
    for c in children or []:
        if isinstance(c, dict) and c.get("kind") == "pr":
            return c.get("href")
    return None


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        job = rec.get("job")
        if not job:
            continue
        rows[job] = {  # last write wins = latest state
            "task_id": f"job:{job}",
            "state": rec.get("state"),
            "tokens": rec.get("tokens"),
            "session_id": rec.get("sessionId"),
            "name": rec.get("name"),
            "cwd": rec.get("cwd"),
            "ts_start": rec.get("createdAt"),
            "ts_end": rec.get("firstTerminalAt"),
            "pr_url": _first_pr(rec.get("children")),
        }
    return write_clean(SOURCE, "job", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
