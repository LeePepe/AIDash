"""Read-only local repository, worktree, and Herdr hygiene snapshots."""

from __future__ import annotations

import json
import shutil
import socket
import subprocess  # nosec B404 - fixed read-only git/herdr commands
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import HOME, WORKTREES_ROOT
from rawio import write_raw_snapshot
from timeutil import cst_today

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


def _git_row(path: Path, entity_type: str, panes: set[Path]) -> dict[str, Any] | None:
    if not (path / ".git").exists() and not _run(["rev-parse", "--git-dir"], path):
        return None
    branch = _run(["branch", "--show-current"], path) or "(detached)"
    head = _run(["rev-parse", "HEAD"], path)
    porcelain = _run(["status", "--porcelain"], path) or ""
    dirty = len(porcelain.splitlines())
    default = _run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], path)
    default_branch = default.removeprefix("origin/") if default else "main"
    merged = _is_ancestor(path, default_branch)
    resolved = path.resolve()
    active = any(pane == resolved or resolved in pane.parents for pane in panes)
    implicit = "AppleUITesting" in path.name or "AppleUITesting" in str(path)
    safe, reason = _safe_to_reclaim(entity_type, dirty, int(merged), int(active), int(implicit))
    return {
        "snapshot_date": cst_today(), "machine_id": socket.gethostname().split(".", 1)[0],
        "entity_type": entity_type, "canonical_path": str(path.resolve()),
        "repo_key": repo_for_path(path), "goal_id": None, "branch_name": branch,
        "head_sha": head, "is_dirty": int(dirty > 0), "dirty_count": dirty,
        "is_merged_to_default": int(merged), "has_active_pane": int(active),
        "has_implicit_dep": int(implicit), "safe_to_reclaim": safe,
        "reclaim_block_reason": reason,
        "repo_owner": (repo_for_path(path) or "").split("/", 1)[0] or None,
        "repo_name": (repo_for_path(path) or "").split("/", 1)[-1] or None,
        "domain_group": None,
        "local_main_path": str(resolved),
        "default_branch": default_branch,
        "has_agents_md": int((path / "AGENTS.md").exists()),
        "has_layer_map": int((path / "CONTEXT.md").exists()),
        "has_verify_script": int((path / "scripts" / "verify").exists()),
        "has_design_contract": int((path / "docs" / "design-contract.md").exists()),
        "shared_ci_pinned_sha": None,
        "ruleset_strict": None,
        "updated_at": cst_today(),
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


def _herdr_panes() -> set[Path]:
    herdr = shutil.which("herdr")
    if not herdr:
        return set()
    try:
        result = subprocess.run([herdr, "pane", "list", "--json"], check=True,
                                capture_output=True, text=True, timeout=5)
        payload = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return set()
    result = payload.get("result", {}) if isinstance(payload, dict) else {}
    panes = result.get("panes", []) if isinstance(result, dict) else []
    paths = {
        str(item.get(key))
        for item in panes
        if isinstance(item, dict)
        for key in ("cwd", "foreground_cwd")
        if item.get(key)
    }
    try:
        workspaces = subprocess.run([herdr, "workspace", "list", "--json"], check=True,
                                    capture_output=True, text=True, timeout=5)
        workspace_payload = json.loads(workspaces.stdout)
        workspace_result = workspace_payload.get("result", {})
        for item in workspace_result.get("workspaces", []):
            checkout = item.get("worktree", {}).get("checkout_path")
            if checkout:
                paths.add(str(checkout))
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        pass
    return {Path(path).expanduser().resolve() for path in paths}


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
        rows[key] = dict(row)
    snapshot_rows = list(rows.values())
    snapshot_result = write_clean(SOURCE, "hygiene_snapshot", _DDL, snapshot_rows, _COLS)
    repo_cols = ("repo_key", "owner", "repo_name", "domain_group", "local_main_path",
                 "default_branch", "head_sha", "is_dirty", "dirty_count", "has_agents_md",
                 "has_layer_map", "has_verify_script", "has_design_contract",
                 "shared_ci_pinned_sha", "ruleset_strict", "updated_at")
    repo_rows = []
    seen = set()
    for row in snapshot_rows:
        key = row.get("repo_key")
        if not key or key in seen:
            continue
        seen.add(key)
        repo_rows.append({
            "repo_key": key, "owner": row.get("repo_owner"), "repo_name": row.get("repo_name"),
            "domain_group": row.get("domain_group"), "local_main_path": row.get("local_main_path"),
            "default_branch": row.get("default_branch"), "head_sha": row.get("head_sha"),
            "is_dirty": row.get("is_dirty"), "dirty_count": row.get("dirty_count"),
            "has_agents_md": row.get("has_agents_md"), "has_layer_map": row.get("has_layer_map"),
            "has_verify_script": row.get("has_verify_script"),
            "has_design_contract": row.get("has_design_contract"),
            "shared_ci_pinned_sha": row.get("shared_ci_pinned_sha"),
            "ruleset_strict": row.get("ruleset_strict"), "updated_at": row.get("updated_at"),
        })
    repo_ddl = """
    CREATE TABLE repo (
        repo_key TEXT PRIMARY KEY, owner TEXT, repo_name TEXT, domain_group TEXT,
        local_main_path TEXT, default_branch TEXT, head_sha TEXT, is_dirty INTEGER,
        dirty_count INTEGER, has_agents_md INTEGER, has_layer_map INTEGER,
        has_verify_script INTEGER, has_design_contract INTEGER,
        shared_ci_pinned_sha TEXT, ruleset_strict INTEGER, updated_at TEXT
    )
    """
    write_clean(SOURCE, "repo", repo_ddl, repo_rows, repo_cols)
    return snapshot_result
