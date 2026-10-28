"""GitHub Actions workflow and job telemetry.

The adapter deliberately keeps Run and Job as separate grains.  GitHub CLI
failures, missing authentication, and malformed individual records degrade to
an empty snapshot rather than interrupting the daily pipeline.
"""

from __future__ import annotations

import json
import shutil
import subprocess  # nosec B404 - fixed read-only gh api calls
from datetime import datetime
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import GITHUB_CI_REPOS
from rawio import read_raw, write_raw_snapshot

SOURCE = "github_ci"
_TIMEOUT_S = 60
_EVIDENCE_PATHS = (
    Path("/Users/lee/Development/handoff/retro1027/data/03-ci-runs-evidence.md"),
    Path("/Users/lee/Development/handoff/retro1027/data/04-tf-release-evidence.md"),
)


def _gh_api(path: str) -> Any:
    if not shutil.which("gh"):
        return None
    try:
        proc = subprocess.run(
            ["gh", "api", path], capture_output=True, text=True,
            timeout=_TIMEOUT_S, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
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


def _category(name: str, event: str | None, path: str | None = None) -> str:
    text = " ".join((name, event or "", path or "")).lower()
    if any(token in text for token in ("review", "codex-review", "kimi-review")):
        return "ai_review_gate"
    if "testflight" in text or "release" in text:
        return "release_tf"
    if "stuck-pr" in text or "cron" in text or event == "schedule":
        return "cron_bot"
    return "ci_build"


def _failure_category(job_name: str, conclusion: str | None, step_name: str | None) -> str | None:
    if conclusion not in {"failure", "timed_out", "action_required"}:
        return None
    text = " ".join((job_name, step_name or "")).lower()
    if "secret" in text:
        return "config_drift_missing_secret"
    if "var" in text or "environment" in text or "config" in text:
        return "config_drift_missing_var"
    if any(token in text for token in ("simulator boot", "simulator timeout", "runner capacity",
                                       "runner unavailable", "no space left")):
        return "runner_capacity_or_sim"
    if any(token in text for token in ("app target runner", "swift test", "xcodebuild",
                                       "unit test", "ui test", "build + test", "test failure")):
        return "build_or_test_failure"
    if any(token in text for token in ("review", "lint", "policy", "frontmatter",
                                       "require-tests", "gate")):
        return "true_positive_gate"
    return "build_or_test_failure"


def _evidence_runs() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for path in _EVIDENCE_PATHS:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        header: list[str] | None = None
        for line in lines:
            if not line.startswith("|"):
                continue
            cells = [cell.strip() for cell in line.strip("|").split("|")]
            if header is None and any("run id" in cell.lower() for cell in cells):
                header = [cell.lower() for cell in cells]
                continue
            if header is None or not cells or set(cells) <= {"---", ":---"}:
                continue
            if len(cells) != len(header):
                continue
            row = dict(zip(header, cells))
            raw_id = row.get("run id")
            try:
                run_id = int(raw_id or "")
            except ValueError:
                continue
            repo = row.get("repo", "")
            workflow = row.get("workflow", "")
            if not repo or not workflow:
                continue
            conclusion = (row.get("conclusion") or row.get("result") or "").lower() or None
            records.append({
                "record_type": "workflow_run",
                "run_id": run_id,
                "repo_key": repo if "/" in repo else f"LeePepe/{repo}",
                "workflow_name": workflow,
                "workflow_category": _category(workflow, None),
                "event_trigger": None,
                "head_branch": row.get("branch"),
                "head_sha": row.get("sha") or "evidence",
                "status": "completed",
                "conclusion": conclusion,
                "run_attempt": 1,
                "created_at": row.get("timestamp") or row.get("time") or "",
                "updated_at": row.get("timestamp") or row.get("time"),
                "duration_sec": None,
                "html_url": None,
            })
    return records


def collect() -> int:
    records: list[dict[str, Any]] = []
    live_run_ids: set[int] = set()
    for repo in GITHUB_CI_REPOS:
        payload = _gh_api(f"repos/{repo}/actions/runs?per_page=100")
        runs = payload.get("workflow_runs", []) if isinstance(payload, dict) else []
        for run in runs:
            if not isinstance(run, dict) or run.get("id") is None:
                continue
            run_id = int(run["id"])
            live_run_ids.add(run_id)
            run_record = {
                "record_type": "workflow_run",
                "run_id": run_id,
                "repo_key": repo,
                "workflow_name": run.get("name") or run.get("workflow_id") or "unknown",
                "workflow_category": _category(
                    str(run.get("name") or ""), run.get("event"), run.get("path")
                ),
                "event_trigger": run.get("event"),
                "head_branch": run.get("head_branch"),
                "head_sha": run.get("head_sha") or "",
                "status": run.get("status") or "unknown",
                "conclusion": run.get("conclusion"),
                "run_attempt": run.get("run_attempt") or 1,
                "created_at": run.get("created_at") or "",
                "updated_at": run.get("updated_at"),
                "duration_sec": _seconds(run.get("run_started_at"), run.get("updated_at")),
                "html_url": run.get("html_url"),
            }
            records.append(run_record)
            should_sample = (
                run.get("conclusion") not in {"success", "skipped"}
                or run_record["workflow_category"] in {"ci_build", "release_tf"}
            )
            if not should_sample:
                continue
            jobs = _gh_api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")
            for job in (jobs or {}).get("jobs", []) if isinstance(jobs, dict) else []:
                if not isinstance(job, dict) or job.get("id") is None:
                    continue
                steps = job.get("steps") or []
                failed_step = next(
                    (step.get("name") for step in steps
                     if isinstance(step, dict) and step.get("conclusion") not in {None, "success", "skipped"}),
                    None,
                )
                records.append({
                    "record_type": "job_run",
                    "job_id": int(job["id"]),
                    "run_id": run_id,
                    "repo_key": repo,
                    "job_name": job.get("name") or "unknown",
                    "status": job.get("status") or "unknown",
                    "conclusion": job.get("conclusion"),
                    "runner_labels": json.dumps(job.get("labels") or []),
                    "is_self_hosted": int(any("self-hosted" in str(label).lower()
                                              for label in job.get("labels") or [])),
                    "created_at": job.get("created_at"),
                    "started_at": job.get("started_at"),
                    "completed_at": job.get("completed_at"),
                    "queue_wait_sec": _seconds(job.get("created_at"), job.get("started_at")),
                    "exec_sec": _seconds(job.get("started_at"), job.get("completed_at")),
                    "failed_step_name": failed_step,
                    "failure_category": _failure_category(
                        str(job.get("name") or ""), job.get("conclusion"), failed_step
                    ),
                    "error_excerpt": None,
                })
    if not records:
        records = _evidence_runs()
    else:
        records.extend(record for record in _evidence_runs()
                       if record["run_id"] not in live_run_ids)
    return write_raw_snapshot(SOURCE, records) if records else 0


_RUN_DDL = """CREATE TABLE workflow_run (
    run_id INTEGER PRIMARY KEY, repo_key TEXT NOT NULL, workflow_name TEXT NOT NULL,
    workflow_category TEXT NOT NULL, event_trigger TEXT, head_branch TEXT,
    head_sha TEXT NOT NULL, status TEXT NOT NULL, conclusion TEXT,
    run_attempt INTEGER DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT,
    duration_sec INTEGER, html_url TEXT
)"""
_JOB_DDL = """CREATE TABLE job_run (
    job_id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL, repo_key TEXT NOT NULL,
    job_name TEXT NOT NULL, status TEXT NOT NULL, conclusion TEXT,
    runner_labels TEXT, is_self_hosted INTEGER, created_at TEXT, started_at TEXT,
    completed_at TEXT, queue_wait_sec INTEGER, exec_sec INTEGER,
    failed_step_name TEXT, failure_category TEXT, error_excerpt TEXT
)"""


def normalize() -> int:
    runs: dict[int, dict[str, Any]] = {}
    jobs: dict[int, dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        if record.get("record_type") == "workflow_run" and record.get("run_id") is not None:
            runs[int(record["run_id"])] = record
        elif record.get("record_type") == "job_run" and record.get("job_id") is not None:
            jobs[int(record["job_id"])] = record
    run_cols = ("run_id", "repo_key", "workflow_name", "workflow_category", "event_trigger",
                "head_branch", "head_sha", "status", "conclusion", "run_attempt",
                "created_at", "updated_at", "duration_sec", "html_url")
    job_cols = ("job_id", "run_id", "repo_key", "job_name", "status", "conclusion",
                "runner_labels", "is_self_hosted", "created_at", "started_at",
                "completed_at", "queue_wait_sec", "exec_sec", "failed_step_name",
                "failure_category", "error_excerpt")
    count = write_clean(SOURCE, "workflow_run", _RUN_DDL, list(runs.values()), run_cols)
    count += write_clean(SOURCE, "job_run", _JOB_DDL, list(jobs.values()), job_cols)
    return count
