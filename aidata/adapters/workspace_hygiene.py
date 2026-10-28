"""Read-only local repository, worktree, and Herdr hygiene snapshots."""

from __future__ import annotations

import json
import shutil
import socket
import subprocess  # nosec B404 - fixed read-only git/herdr commands
from datetime import date
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import HOME, WORKTREES_ROOT
from rawio import write_raw_snapshot

from adapters._repo import repo_for_path

SOURCE = "workspace_hygiene"
_SKIP = {".build", ".shared-ci", "DerivedData", "node_modules", "Pods"}


def _run(args: list[str], cwd: Path | None = None) -> str | None:
    try:
        result = subprocess.run(["git", "--no-optional-locks", *args], cwd=cwd,
                                check=True, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip()


def _is_ancestor(path: Path, default_branch: str) -> bool:
    try:
        subprocess.run(
            ["git", "--no-optional-locks", "merge-base", "--is-ancestor",
             "HEAD", f"origin/{default_branch}"],
            cwd=path, check=True, capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return True


def _git_row(path: Path, entity_type: str, panes: set[str]) -> dict[str, Any] | None:
    if not (path / ".git").exists() and not _run(["rev-parse", "--git-dir"], path):
        return None
    branch = _run(["branch", "--show-current"], path) or "(detached)"
    head = _run(["rev-parse", "HEAD"], path)
    porcelain = _run(["status", "--porcelain"], path) or ""
    dirty = len(porcelain.splitlines())
    default = _run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], path)
    default_branch = default.removeprefix("origin/") if default else "main"
    merged = _is_ancestor(path, default_branch)
    active = any(str(path) in pane for pane in panes)
    implicit = "AppleUITesting" in path.name or "AppleUITesting" in str(path)
    safe, reason = _safe_to_reclaim(entity_type, dirty, int(merged), int(active), int(implicit))
    return {
        "snapshot_date": date.today().isoformat(), "machine_id": socket.gethostname().split(".", 1)[0],
        "entity_type": entity_type, "canonical_path": str(path.resolve()),
        "repo_key": repo_for_path(path), "goal_id": None, "branch_name": branch,
        "head_sha": head, "is_dirty": int(dirty > 0), "dirty_count": dirty,
        "is_merged_to_default": int(merged), "has_active_pane": int(active),
        "has_implicit_dep": int(implicit), "safe_to_reclaim": safe,
        "reclaim_block_reason": reason,
    }


def _safe_to_reclaim(entity_type: str, dirty_count: int, merged: int,
                     active_pane: int, implicit_dep: int) -> tuple[int, str | None]:
    if entity_type != "worktree":
        return 0, "primary_clone"
    if dirty_count:
        return 0, "has_dirty_changes"
    if not merged:
        return 0, "unmerged_branch"
    if active_pane:
        return 0, "active_herdr_pane"
    if implicit_dep:
        return 0, "implicit_dependency"
    return 1, None


def _herdr_panes() -> set[str]:
    herdr = shutil.which("herdr")
    if not herdr:
        return set()
    try:
        result = subprocess.run([herdr, "pane", "list", "--json"], check=True,
                                capture_output=True, text=True, timeout=5)
        payload = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return set()
    if not isinstance(payload, list):
        return set()
    return {
        str(item.get("path"))
        for item in payload
        if isinstance(item, dict) and item.get("path")
    }


def _paths() -> list[tuple[Path, str]]:
    output: list[tuple[Path, str]] = []
    try:
        for path in sorted((HOME / "Development").iterdir()):
            if path.name == "worktrees" or path.name in _SKIP:
                continue
            if path.is_dir():
                output.append((path, "repo"))
    except OSError:
        pass
    try:
        for path in sorted(WORKTREES_ROOT.iterdir()):
            if path.name in _SKIP or not path.is_dir():
                continue
            output.append((path, "worktree"))
    except OSError:
        pass
    return output


_DDL = """
CREATE TABLE hygiene_snapshot (
    snapshot_date TEXT NOT NULL, machine_id TEXT NOT NULL, entity_type TEXT NOT NULL,
    canonical_path TEXT NOT NULL, repo_key TEXT, goal_id TEXT, branch_name TEXT,
    head_sha TEXT, is_dirty INTEGER, dirty_count INTEGER, is_merged_to_default INTEGER,
    has_active_pane INTEGER, has_implicit_dep INTEGER, safe_to_reclaim INTEGER NOT NULL,
    reclaim_block_reason TEXT, PRIMARY KEY (snapshot_date, machine_id, entity_type, canonical_path)
)
"""
_COLS = ("snapshot_date", "machine_id", "entity_type", "canonical_path", "repo_key", "goal_id",
         "branch_name", "head_sha", "is_dirty", "dirty_count", "is_merged_to_default",
         "has_active_pane", "has_implicit_dep", "safe_to_reclaim", "reclaim_block_reason")


def collect() -> int:
    panes = _herdr_panes()
    rows = [row for path, kind in _paths() if (row := _git_row(path, "worktree" if kind == "worktree" else "repo", panes))]
    return write_raw_snapshot(SOURCE, rows)


def normalize() -> int:
    # Snapshot records are already normalized and redacted by rawio.
    from rawio import read_raw
    rows: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    for row in read_raw(SOURCE):
        key = tuple(str(row.get(name, "")) for name in _COLS[:4])
        rows[key] = {name: row.get(name) for name in _COLS}
    return write_clean(SOURCE, "hygiene_snapshot", _DDL, list(rows.values()), _COLS)
