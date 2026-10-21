"""Resolve working directories to the common project key."""

from __future__ import annotations

import os
import subprocess
from functools import lru_cache
from pathlib import Path


def _run_git(args: list[str], cwd: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", *args], cwd=cwd, check=True, capture_output=True,
            text=True, timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    value = result.stdout.strip()
    return value or None


def _remote_project(remote: str) -> str | None:
    value = remote.removesuffix("/")
    if value.endswith(".git"):
        value = value[:-4]
    if ":" in value and "/" not in value.split(":", 1)[0]:
        value = value.rsplit(":", 1)[-1]
    parts = value.rstrip("/").split("/")
    return "/".join(parts[-2:]) if len(parts) >= 2 and all(parts[-2:]) else None


@lru_cache(maxsize=4096)
def repo_for_path(path: str | os.PathLike[str] | None) -> str:
    """Return owner/name, local:<basename>, or (unresolved) for ``path``."""
    if not path:
        return "(unresolved)"
    normalized = os.path.abspath(os.path.expanduser(os.fspath(path)))
    root = _run_git(["rev-parse", "--show-toplevel"], normalized)
    if root is None:
        return "(unresolved)"
    remote = _run_git(["remote", "get-url", "origin"], root)
    project = _remote_project(remote) if remote else None
    return project or f"local:{Path(root).name}" if Path(root).name else "(unresolved)"

