"""multica_issue adapter — Multica issues via CLI (hosted backend).

L1 collect (ADR-19 / EXT-1/2/3): `multica issue list --workspace-id <ws>` across
EVERY configured workspace. Instead of the old monotonic
`number > watermark` cursor — which missed OLD issues that got completed
recently, forever — this does an `updated_since` **window read**: it re-fetches
issues whose `updated_at` falls inside the last N days and appends any whose
edit is newer than that workspace's watermark. Watermarks are PER-WORKSPACE
(never a shared global cursor), so adding a workspace full-backfills it
independently of the others' already-advanced cursors.

L2 normalize: last-write-wins by issue id; carries `updated_at` (for "今日完成")
and `project_id` (often NULL → downstream degrades to per-workspace).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from config import MULTICA_WORKSPACES, MULTICA_UPDATED_WINDOW_DAYS
from adapters._multica import multica_bin, run_json
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark

SOURCE = "multica_issue"
_PAGE = 100  # server hard-caps --limit at 100


def _multica_bin() -> str | None:
    """Thin wrapper over the shared resolver (kept as a monkeypatch seam)."""
    return multica_bin()


def _run_json(args: list[str]) -> Any:
    """Thin wrapper over shared run_json; passes LOCAL _multica_bin() so that
    patching this module's _multica_bin still drives the CLI resolution."""
    return run_json(args, binp=_multica_bin())


def _list_workspace_issues(ws_id: str) -> list[dict[str, Any]]:
    """Fetch ALL issues in a workspace, paginating (limit capped at 100).

    Server exposes no updated_since filter / updated_at sort, so we page the
    whole list and filter client-side. Read-only.
    """
    out: list[dict[str, Any]] = []
    offset = 0
    while True:
        payload = _run_json([
            "issue", "list", "--workspace-id", ws_id,
            "--limit", str(_PAGE), "--offset", str(offset), "--output", "json",
        ])
        if isinstance(payload, dict):
            issues = payload.get("issues", [])
            has_more = bool(payload.get("has_more"))
        else:
            issues, has_more = list(payload), False
        out.extend(issues)
        if not has_more or not issues:
            break
        offset += _PAGE
    return out


def _updated_at(issue: dict[str, Any]) -> str:
    return issue.get("updated_at") or issue.get("created_at") or ""


def _fresh_for_workspace(issues: list[dict[str, Any]], watermark: str | None,
                         cutoff: str) -> list[dict[str, Any]]:
    """Issues to append for one workspace.

    First run (no watermark) → full backfill. Otherwise keep issues whose
    updated_at is inside the window (>= cutoff) AND newer than the watermark.
    """
    if watermark is None:
        return list(issues)  # backfill everything on first collect
    return [i for i in issues
            if _updated_at(i) >= cutoff and _updated_at(i) > watermark]


def collect(now: datetime | None = None) -> int:
    """Window-read both workspaces; append fresh edits; advance per-ws watermark."""
    if not _multica_bin():
        return 0  # degrade (ADR-23): no CLI → nothing to collect, never raise
    now = now or datetime.now(timezone.utc)
    cutoff = (now - timedelta(days=MULTICA_UPDATED_WINDOW_DAYS)).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    total = 0
    for ws_id, _name in MULTICA_WORKSPACES:
        key = f"{SOURCE}:{ws_id}"
        watermark = get_watermark(key)
        issues = _list_workspace_issues(ws_id)
        fresh = _fresh_for_workspace(issues, watermark, cutoff)
        if not fresh:
            continue
        total += write_raw(SOURCE, fresh)
        newest = max(_updated_at(i) for i in fresh)
        set_watermark(key, max(watermark, newest) if watermark else newest)
    return total


_CLEAN_DDL = """
CREATE TABLE issue (
    issue_id TEXT PRIMARY KEY, issue_number INTEGER, identifier TEXT,
    title TEXT, status TEXT, priority TEXT, created_at TEXT, workspace_id TEXT,
    updated_at TEXT, project_id TEXT
)
"""
_CLEAN_COLS = ("issue_id", "issue_number", "identifier", "title", "status",
               "priority", "created_at", "workspace_id", "updated_at",
               "project_id")


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        iid = rec.get("id")
        if not iid:
            continue
        rows[iid] = {  # last write wins -> latest snapshot of each issue
            "issue_id": iid,
            "issue_number": rec.get("number"),
            "identifier": rec.get("identifier"),
            "title": rec.get("title"),
            "status": rec.get("status"),
            "priority": rec.get("priority"),
            "created_at": rec.get("created_at"),
            "workspace_id": rec.get("workspace_id"),
            "updated_at": rec.get("updated_at"),
            "project_id": rec.get("project_id"),
        }
    return write_clean(SOURCE, "issue", _CLEAN_DDL, list(rows.values()),
                       _CLEAN_COLS)
