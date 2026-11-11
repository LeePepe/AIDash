"""linear_issue adapter — Linear Team TIA issues via linear-sync.py (pluggable SSOT).

L1 collect (ADR-19 / ADR-23): invokes `linear-sync.py list-issues --team TIA --limit 250`.
If `linear-sync.py` is absent, credentials are not configured, or the subprocess
fails/times out, `collect()` degrades gracefully to 0 and never raises. Uses a
windowed `updatedAt` watermark (`linear_issue:TIA`) matching `multica_issue`.

L2 normalize: last-write-wins by issue id, mapped into the canonical `fact_issue`
shape per TodoSyncProvider v1 (`spec.md` §2.2).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import (
    LINEAR_SYNC_SCRIPT,
    LINEAR_TEAM_KEY,
    LINEAR_UPDATED_WINDOW_DAYS,
    TODO_SYNC_CONFIG_PATH,
    TODO_SYNC_PROVIDER,
)
from rawio import read_raw, write_raw
from state import get_watermark, set_watermark

SOURCE = "linear_issue"
_LIMIT = 250
_BLOCKED_LABELS = {"blocked", "needs decision", "need_go"}
_NUMBER_RE = re.compile(r"-(\d+)$")
_LOCAL_DISABLED_MODES = {"local", "none", "off", "disabled", "local_only", "local-only"}


def _is_linear_sync_enabled(config_path: Path | None = None) -> tuple[bool, str]:
    """Return `(enabled, team_key)` based on env, todo-sync.json, and config defaults."""
    env_mode = os.environ.get("AIDASH_TODO_SYNC_PROVIDER", "").strip().lower()
    env_team = os.environ.get("AIDASH_TODO_SYNC_TEAM_KEY", "").strip().upper()

    file_mode = ""
    file_team = ""
    path = Path(config_path or TODO_SYNC_CONFIG_PATH)
    if path.is_file():
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(payload, dict):
                file_mode = str(payload.get("provider") or "").strip().lower()
                file_team = str(payload.get("teamKey") or "").strip().upper()
        except (OSError, json.JSONDecodeError):
            pass

    mode = env_mode or file_mode or str(TODO_SYNC_PROVIDER or "auto").strip().lower()
    team_key = env_team or file_team or str(LINEAR_TEAM_KEY or "").strip().upper()
    if mode in _LOCAL_DISABLED_MODES or not team_key:
        return False, team_key
    return True, team_key


def _linear_sync_script() -> Path | None:
    """Resolve linear-sync.py if it exists on disk (kept as a monkeypatch seam)."""
    path = Path(LINEAR_SYNC_SCRIPT)
    return path if path.is_file() else None


def _list_team_issues(team_key: str) -> list[dict[str, Any]]:
    """Fetch recent issues for `team_key` via `linear-sync.py list-issues`."""
    script = _linear_sync_script()
    if script is None:
        return []
    try:
        proc = subprocess.run(
            [
                sys.executable,
                str(script),
                "list-issues",
                "--team",
                team_key,
                "--limit",
                str(_LIMIT),
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if proc.returncode != 0 or not proc.stdout.strip():
        return []
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []
    if not isinstance(payload, dict) or not payload.get("ok"):
        return []
    issues = payload.get("issues", [])
    return [i for i in issues if isinstance(i, dict)]


def _updated_at(issue: dict[str, Any]) -> str:
    return str(
        issue.get("updatedAt")
        or issue.get("updated_at")
        or issue.get("createdAt")
        or issue.get("created_at")
        or ""
    )


def _fresh_for_team(
    issues: list[dict[str, Any]], watermark: str | None, cutoff: str
) -> list[dict[str, Any]]:
    if watermark is None:
        return list(issues)
    return [
        i
        for i in issues
        if _updated_at(i) >= cutoff and _updated_at(i) > watermark
    ]


def collect(now: datetime | None = None) -> int:
    """Window-read Linear team issues; append fresh edits; advance watermark."""
    enabled, team_key = _is_linear_sync_enabled()
    if not enabled or _linear_sync_script() is None:
        return 0
    now = now or datetime.now(timezone.utc)  # noqa: UP017
    cutoff = (now - timedelta(days=LINEAR_UPDATED_WINDOW_DAYS)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    key = f"{SOURCE}:{team_key}"
    watermark = get_watermark(key)
    issues = _list_team_issues(team_key)
    fresh = _fresh_for_team(issues, watermark, cutoff)
    if not fresh:
        return 0
    total = write_raw(SOURCE, fresh)
    newest = max(_updated_at(i) for i in fresh)
    if newest:
        set_watermark(key, max(watermark, newest) if watermark else newest)
    return total


def _parse_issue_number(identifier: str, fallback: Any = None) -> int:
    if isinstance(fallback, int):
        return fallback
    match = _NUMBER_RE.search(identifier or "")
    return int(match.group(1)) if match else 0


def _normalize_labels(raw_labels: Any) -> list[str]:
    if isinstance(raw_labels, list):
        out: list[str] = []
        for item in raw_labels:
            if isinstance(item, str) and item.strip():
                out.append(item.strip())
            elif isinstance(item, dict) and item.get("name"):
                out.append(str(item["name"]).strip())
        return out
    if isinstance(raw_labels, dict):
        nodes = raw_labels.get("nodes", [])
        return [
            str(n["name"]).strip()
            for n in nodes
            if isinstance(n, dict) and n.get("name")
        ]
    return []


def _normalize_status(rec: dict[str, Any]) -> str:
    raw_state = rec.get("state")
    state_type = str(rec.get("stateType") or "").strip().casefold()
    if isinstance(raw_state, dict):
        state_name = str(raw_state.get("name") or "").strip().casefold()
        if not state_type:
            state_type = str(raw_state.get("type") or "").strip().casefold()
    else:
        state_name = str(raw_state or rec.get("status") or "").strip().casefold()

    if state_name == "done" or state_type == "completed":
        return "done"
    if state_name in {"canceled", "cancelled"} or state_type in {
        "canceled",
        "cancelled",
    }:
        return "cancelled"

    labels = {lbl.casefold() for lbl in _normalize_labels(rec.get("labels"))}
    if labels & _BLOCKED_LABELS or state_name == "blocked":
        return "blocked"

    if state_name in {"in review", "in_review"}:
        return "in_review"
    if state_name in {"in progress", "in_progress"} or state_type == "started":
        return "in_progress"
    if state_name == "todo" or state_type == "unstarted":
        return "todo"
    if state_name == "triage" or state_type == "triage":
        return "triage"
    if state_name == "backlog" or state_type == "backlog":
        return "backlog"
    return "todo"


def _normalize_priority(raw_priority: Any) -> str:
    if isinstance(raw_priority, str):
        lowered = raw_priority.strip().casefold()
        if lowered in {"high", "medium", "low"}:
            return lowered
        if lowered == "urgent":
            return "high"
        if lowered == "none":
            return "medium"
        try:
            raw_priority = int(lowered)
        except ValueError:
            return "medium"
    if isinstance(raw_priority, (int, float)):
        val = int(raw_priority)
        if val in (1, 2):
            return "high"
        if val == 4:
            return "low"
        return "medium"
    return "medium"


_CLEAN_DDL = """
CREATE TABLE issue (
    issue_id TEXT PRIMARY KEY, issue_number INTEGER, identifier TEXT,
    title TEXT, status TEXT, priority TEXT, created_at TEXT, workspace_id TEXT,
    updated_at TEXT, project_id TEXT
)
"""
_CLEAN_COLS = (
    "issue_id",
    "issue_number",
    "identifier",
    "title",
    "status",
    "priority",
    "created_at",
    "workspace_id",
    "updated_at",
    "project_id",
)


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        identifier = str(rec.get("identifier") or "").strip()
        iid = str(rec.get("id") or rec.get("issue_id") or "").strip()
        if not iid and identifier:
            iid = f"linear:{identifier}"
        if not iid:
            continue
        updated_at = (
            rec.get("updatedAt")
            or rec.get("updated_at")
            or rec.get("createdAt")
            or rec.get("created_at")
        )
        created_at = (
            rec.get("createdAt")
            or rec.get("created_at")
            or updated_at
        )
        raw_project = rec.get("project")
        if isinstance(raw_project, dict):
            project_id = raw_project.get("name")
        else:
            project_id = raw_project or rec.get("project_id")
        rows[iid] = {
            "issue_id": iid,
            "issue_number": _parse_issue_number(identifier, rec.get("number")),
            "identifier": identifier or iid,
            "title": rec.get("title") or "",
            "status": _normalize_status(rec),
            "priority": _normalize_priority(rec.get("priority")),
            "created_at": created_at,
            "workspace_id": rec.get("workspace_id") or f"linear:{LINEAR_TEAM_KEY}",
            "updated_at": updated_at,
            "project_id": project_id,
        }
    return write_clean(
        SOURCE, "issue", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS
    )
