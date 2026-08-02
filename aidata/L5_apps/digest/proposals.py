"""Agent-proposal inbox (§M3, goal ② 需要处理什么 — 待决策 bucket).

An append-only JSONL file (`config.PROPOSALS_PATH`) that autonomous agents
write proposals into for the user to approve. The digest READS pending ones
into the action-inbox card; it never writes here — agents do. This keeps the
"human ↔ agent" decision loop out of the telemetry warehouse (proposals are
state, not measurements).

Record schema (one JSON object per line):
    {
      "id":        "uuid or agent-chosen stable id",   # required
      "ts":        "2026-07-18T04:00:00Z",              # ISO-8601, required
      "agent":     "pm-agent",                          # who proposed, required
      "title":     "立项：把 digest 拆成独立 pane",       # required, one line
      "detail":    "…longer rationale…",                # optional
      "priority":  "high" | "medium" | "low",           # optional, default medium
      "status":    "pending" | "approved" | "dismissed" # optional, default pending
    }

Only `status == "pending"` records surface in the digest. Approval/dismissal
is written back by whatever consumes AIDash's react events (out of scope here);
this module only reads. Malformed lines are skipped, never fatal — a bad
proposal must not break the digest.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from config import PROPOSALS_PATH

_VALID_PRIORITY = {"high", "medium", "low"}


@dataclass(frozen=True)
class Proposal:
    id: str
    ts: str
    agent: str
    title: str
    detail: str
    priority: str
    status: str


def _coerce(obj: dict) -> Proposal | None:
    """Validate one raw record → Proposal, or None if it can't be trusted.

    Requires id/ts/agent/title (non-empty strings). Normalizes priority/status
    to their valid sets with sane defaults. Never raises.
    """
    try:
        pid = str(obj["id"]).strip()
        ts = str(obj["ts"]).strip()
        agent = str(obj["agent"]).strip()
        title = str(obj["title"]).strip()
    except (KeyError, TypeError, AttributeError):
        return None
    if not (pid and ts and agent and title):
        return None
    priority = str(obj.get("priority", "medium")).strip().lower()
    if priority not in _VALID_PRIORITY:
        priority = "medium"
    status = str(obj.get("status", "pending")).strip().lower()
    detail = str(obj.get("detail", "")).strip()
    return Proposal(pid, ts, agent, title, detail, priority, status)


def read_pending(path: Path | None = None) -> list[Proposal]:
    """Return pending proposals (append-only JSONL), newest last.

    Missing file → []. Malformed lines are skipped. De-dupes by id keeping the
    LAST occurrence, so an agent re-appending the same id with an updated status
    (e.g. pending → approved) correctly drops it from the pending set.
    """
    p = path or PROPOSALS_PATH
    if not p.exists():
        return []
    by_id: dict[str, Proposal] = {}
    try:
        text = p.read_text(encoding="utf-8")
    except OSError:
        return []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(obj, dict):
            continue
        prop = _coerce(obj)
        if prop is not None:
            by_id[prop.id] = prop   # last occurrence wins
    return [p for p in by_id.values() if p.status == "pending"]
