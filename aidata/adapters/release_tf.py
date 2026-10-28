"""Read-only TestFlight/04 delivery snapshots from Actions and local markers."""

from __future__ import annotations

import json
import shutil
import subprocess  # nosec B404 - fixed read-only commands
from datetime import datetime
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import GITHUB_CI_REPOS, HOME
from rawio import read_raw, write_raw_snapshot

SOURCE = "release_tf"
_REPOS = tuple(repo for repo in GITHUB_CI_REPOS
               if repo.split("/", 1)[-1] in {"VitalStride", "VoxPocket", "AIDash", "demoUI"}
               or repo.split("/", 1)[-1].startswith("shared-"))
_EVIDENCE_PATH = Path("/Users/lee/Development/handoff/retro1027/data/04-tf-release-evidence.md")


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


def _job_steps(repo: str, run_id: int) -> list[dict[str, Any]]:
    payload = _gh_api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")
    steps: list[dict[str, Any]] = []
    for job in payload.get("jobs", []) if isinstance(payload, dict) else []:
        steps.extend(step for step in job.get("steps", []) if isinstance(step, dict))
    return steps


def _step_conclusion(steps: list[dict[str, Any]], *tokens: str) -> str | None:
    for step in steps:
        name = str(step.get("name") or "").lower()
        if any(token in name for token in tokens):
            return step.get("conclusion")
    return None


def _release_classification(steps: list[dict[str, Any]], run: dict[str, Any],
                                marker_sha: str | None) -> tuple[str, str | None, int, str | None]:
    gate = _step_conclusion(steps, "secret", "keychain", "marker", "preflight", "gate")
    archive = _step_conclusion(steps, "archive", "build_app", "xcodebuild")
    upload = _step_conclusion(steps, "upload", "testflight", "app store connect")
    tag = _step_conclusion(steps, "move last-released", "tag")
    conclusion = run.get("conclusion")
    failed_name = next(
        (str(step.get("name") or "").lower() for step in steps
         if step.get("conclusion") in {"failure", "timed_out", "action_required"}),
        "",
    )
    if conclusion in {"cancelled", "timed_out"}:
        return "cancelled_timeout", ("cancelled" if conclusion == "cancelled" else "timeout"), 0, "upload"
    if gate in {"failure", "timed_out", "action_required"} or any(
        token in failed_name for token in ("secret", "keychain", "marker", "preflight")
    ):
        return "failed_config", "gate", 0, "gate"
    if any(value in {"failure", "timed_out", "action_required"} for value in (archive, upload)):
        return "failed_signing_or_upload", "failure", 0, "archive" if archive in {
            "failure", "timed_out", "action_required"} else "upload"
    advanced = int(tag == "success" or (
        marker_sha is not None and run.get("head_sha") == marker_sha
    ))
    if conclusion == "success" and advanced:
        return "uploaded_verified", "success", 1, None
    if conclusion == "success":
        return "uploaded_unverified_asc", "success", advanced, None
    return "failed_signing_or_upload", conclusion, advanced, "upload"


def _evidence_runs() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    try:
        lines = _EVIDENCE_PATH.read_text(encoding="utf-8").splitlines()
    except OSError:
        return records
    header: list[str] | None = None
    for line in lines:
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if header is None and any("run id" in cell.lower() for cell in cells):
            header = [cell.lower() for cell in cells]
            continue
        if header is None or len(cells) != len(header) or set(cells) <= {"---", ":---"}:
            continue
        row = dict(zip(header, cells))
        try:
            run_id = int(row.get("run id") or "")
        except ValueError:
            continue
        repo = row.get("repo", "")
        workflow = row.get("workflow", "")
        if not repo or not workflow:
            continue
        conclusion = (row.get("conclusion") or row.get("result") or "").lower() or None
        records.append({
                "delivery_uid": f"{repo}:{run_id}",
                "repo_key": repo if "/" in repo else f"LeePepe/{repo}",
                "run_id": run_id,
                "workflow_name": workflow,
                "trigger_event": None,
                "target_platform": "macos" if repo.endswith("VoxPocket") else "ios",
                "head_sha": row.get("sha") or "evidence",
                "marketing_version": None,
                "build_number": None,
                "gate_step_conclusion": None,
                "archive_step_conclusion": None,
                "upload_step_conclusion": conclusion,
                "tag_step_conclusion": None,
                "marker_tag_name": None,
                "marker_sha_before": None,
                "marker_sha_after": None,
                "is_marker_advanced": 0,
                "asc_build_verified": 0,
                "delivery_outcome": "uploaded_unverified_asc" if conclusion == "success"
                else "cancelled_timeout" if conclusion in {"cancelled", "timed_out"}
                else "failed_signing_or_upload",
                "total_duration_sec": None,
                "started_at": row.get("timestamp") or row.get("time") or "",
                "completed_at": row.get("timestamp") or row.get("time"),
                "failure_stage": None if conclusion == "success" else "upload",
        })
    return records


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
            steps = _job_steps(repo, int(run["id"]))
            outcome, upload_conclusion, advanced, failure_stage = _release_classification(
                steps, run, marker_sha
            )
            if conclusion == "success" and duration is not None and duration <= 30:
                outcome = "noop_skipped"
                advanced = 0
                failure_stage = None
            records.append({
                "delivery_uid": f"{repo}:{run.get('id')}",
                "repo_key": repo,
                "run_id": run.get("id"),
                "workflow_name": name or "unknown",
                "trigger_event": run.get("event"),
                "target_platform": "macos" if (
                    "macos" in f"{name} {path}".lower()
                    or repo.endswith("VoxPocket")
                ) else "multi_sdk" if repo.split("/", 1)[-1].startswith("shared-") else "ios",
                "head_sha": run.get("head_sha") or "",
                "marketing_version": None,
                "build_number": None,
                "gate_step_conclusion": _step_conclusion(
                    steps, "secret", "keychain", "marker", "preflight", "gate"
                ),
                "archive_step_conclusion": _step_conclusion(
                    steps, "archive", "build_app", "xcodebuild"
                ),
                "upload_step_conclusion": upload_conclusion,
                "tag_step_conclusion": _step_conclusion(steps, "move last-released", "tag"),
                "marker_tag_name": marker_name,
                "marker_sha_before": marker_sha,
                "marker_sha_after": run.get("head_sha") if advanced else marker_sha,
                "is_marker_advanced": advanced,
                "asc_build_verified": int(outcome == "uploaded_verified"),
                "delivery_outcome": outcome,
                "total_duration_sec": duration,
                "started_at": run.get("run_started_at") or run.get("created_at") or "",
                "completed_at": run.get("updated_at"),
                "failure_stage": failure_stage,
            })
    if not records:
        records = _evidence_runs()
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
