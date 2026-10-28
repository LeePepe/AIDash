"""Read-only TestFlight/04 delivery snapshots from Actions and local markers."""

from __future__ import annotations

import json
import shutil
import subprocess  # nosec B404 - fixed read-only commands
from datetime import datetime
from typing import Any

from cleanio import write_clean
from config import GITHUB_CI_REPOS, HOME
from rawio import read_raw, write_raw_snapshot

SOURCE = "release_tf"
_REPOS = tuple(repo for repo in GITHUB_CI_REPOS
               if repo.split("/", 1)[-1] in {"VitalStride", "VoxPocket", "AIDash", "demoUI"}
               or repo.split("/", 1)[-1].startswith("shared-"))


def _gh_api(path: str) -> Any:
    if not shutil.which("gh"):
        return None
    try:
        proc = subprocess.run(["gh", "api", path], capture_output=True, text=True,
                              timeout=60, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def _seconds(start: str | None, end: str | None) -> int | None:
    if not start or not end:
        return None
    try:
        return max(0, int((datetime.fromisoformat(end)
                            - datetime.fromisoformat(start)).total_seconds()))
    except (TypeError, ValueError):
        return None


def _marker(repo: str) -> tuple[str | None, str | None]:
    path = HOME / "Development" / repo.split("/", 1)[-1]
    if not path.is_dir():
        return None, None
    for prefix in ("testflight/macos-last-released", "testflight/last-released"):
        try:
            proc = subprocess.run(
                ["git", "--no-optional-locks", "rev-parse", f"refs/tags/{prefix}"],
                cwd=path, capture_output=True, text=True, timeout=10, check=False,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if proc.returncode == 0:
            return prefix, proc.stdout.strip()
    return None, None


def collect() -> int:
    records: list[dict[str, Any]] = []
    for repo in _REPOS:
        payload = _gh_api(f"repos/{repo}/actions/runs?per_page=100")
        runs = payload.get("workflow_runs", []) if isinstance(payload, dict) else []
        for run in runs:
            name = str(run.get("name") or "")
            path = str(run.get("path") or "")
            if not any(token in f"{name} {path}".lower() for token in ("testflight", "release", "04")):
                continue
            marker_name, marker_sha = _marker(repo)
            conclusion = run.get("conclusion")
            duration = _seconds(run.get("run_started_at"), run.get("updated_at"))
            outcome = "noop_skipped" if conclusion == "success" and duration is not None and duration <= 30 else (
                "uploaded_unverified_asc" if conclusion == "success" else (
                "cancelled_timeout" if conclusion == "cancelled" else "failed_config"
                if conclusion in {"failure", "timed_out"} else "noop_skipped"
                )
            )
            records.append({
                "delivery_uid": f"{repo}:{run.get('id')}",
                "repo_key": repo,
                "run_id": run.get("id"),
                "workflow_name": name or "unknown",
                "trigger_event": run.get("event"),
                "target_platform": "macos" if "macos" in f"{name} {path}".lower() else "ios",
                "head_sha": run.get("head_sha") or "",
                "marketing_version": None,
                "build_number": None,
                "gate_step_conclusion": None,
                "archive_step_conclusion": None,
                "upload_step_conclusion": conclusion,
                "tag_step_conclusion": None,
                "marker_tag_name": marker_name,
                "marker_sha_before": marker_sha,
                "marker_sha_after": marker_sha,
                "is_marker_advanced": 0,
                "asc_build_verified": 0,
                "delivery_outcome": outcome,
                "total_duration_sec": duration,
                "started_at": run.get("run_started_at") or run.get("created_at") or "",
                "completed_at": run.get("updated_at"),
                "failure_stage": "upload" if conclusion in {"failure", "timed_out"} else None,
            })
    return write_raw_snapshot(SOURCE, records) if records else 0


_DDL = """CREATE TABLE delivery (
    delivery_uid TEXT PRIMARY KEY, repo_key TEXT NOT NULL, run_id INTEGER,
    workflow_name TEXT NOT NULL, trigger_event TEXT, target_platform TEXT,
    head_sha TEXT NOT NULL, marketing_version TEXT, build_number TEXT,
    gate_step_conclusion TEXT, archive_step_conclusion TEXT,
    upload_step_conclusion TEXT, tag_step_conclusion TEXT, marker_tag_name TEXT,
    marker_sha_before TEXT, marker_sha_after TEXT, is_marker_advanced INTEGER,
    asc_build_verified INTEGER DEFAULT 0, delivery_outcome TEXT NOT NULL,
    total_duration_sec INTEGER, started_at TEXT NOT NULL, completed_at TEXT,
    failure_stage TEXT
)"""
_COLS = ("delivery_uid", "repo_key", "run_id", "workflow_name", "trigger_event",
         "target_platform", "head_sha", "marketing_version", "build_number",
         "gate_step_conclusion", "archive_step_conclusion", "upload_step_conclusion",
         "tag_step_conclusion", "marker_tag_name", "marker_sha_before",
         "marker_sha_after", "is_marker_advanced", "asc_build_verified",
         "delivery_outcome", "total_duration_sec", "started_at", "completed_at",
         "failure_stage")


def normalize() -> int:
    rows = {record.get("delivery_uid"): record for record in read_raw(SOURCE)
            if record.get("delivery_uid")}
    return write_clean(SOURCE, "delivery", _DDL, list(rows.values()), _COLS)
