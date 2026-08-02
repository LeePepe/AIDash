#!/usr/bin/env python3
"""Prepared (NOT executed) installer for the aidata-digest Hermes cron job.

ADR-12: create a NEW `aidata-digest` cron job that runs the full digest chain at
04:00 CST, and DISABLE (not delete) the old `unified-daily-digest` job
(id 78d2b35a5693) so it can be rolled back. This script only PLANS the change
by default and PRINTS what it would do (`--dry-run`); `--apply` is provided for
the human to run manually after review. The unit suite exercises it against a
temp jobs.json — the real registry is never touched by tests.

Usage (human, after review):
    python3 scripts/aidata_digest_cron.py --dry-run          # print, change nothing
    python3 scripts/aidata_digest_cron.py --apply            # actually rewrite jobs.json

The runner the job invokes is scripts/aidata_digest_run.sh (collect → normalize
→ merge → digest --llm --aidash). A separate collect must precede digest; the
runner chains them so a single job is self-contained.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
import uuid
from pathlib import Path

OLD_JOB_ID = "78d2b35a5693"  # unified-daily-digest — disabled, not deleted
DEFAULT_JOBS_FILE = str(Path.home() / ".hermes" / "cron" / "jobs.json")
RUNNER_SCRIPT = "aidata_digest_run.sh"
NEW_JOB_NAME = "aidata-digest"
SCHEDULE_EXPR = "0 4 * * *"  # 04:00 CST (ADR-12)


def _new_job_id() -> str:
    return uuid.uuid4().hex[:12]


def build_new_job(job_id: str | None = None) -> dict:
    """The NEW aidata-digest job entry, matching the old job's JSON shape.

    Modeled on the `unified-daily-digest` / `aidash-snapshot` entries: a
    no_agent script job on a cron schedule, delivering locally.
    """
    return {
        "id": job_id or _new_job_id(),
        "name": NEW_JOB_NAME,
        "prompt": "",
        "skills": [],
        "skill": None,
        "model": None,
        "provider": None,
        "base_url": None,
        "script": RUNNER_SCRIPT,
        "no_agent": True,
        "context_from": None,
        "schedule": {"kind": "cron", "expr": SCHEDULE_EXPR,
                     "display": SCHEDULE_EXPR},
        "schedule_display": SCHEDULE_EXPR,
        "repeat": {"times": None, "completed": 0},
        "enabled": True,
        "state": "scheduled",
        "paused_at": None,
        "paused_reason": None,
        "deliver": "local",
        "origin": None,
        "enabled_toolsets": None,
        "workdir": None,
        "fire_claim": None,
    }


def plan_changes(data: dict, job_id: str | None = None) -> dict:
    """Return a NEW registry dict with the old job disabled + the new job added.

    Pure: the input `data` is deep-copied, never mutated in place (immutability).
    """
    new_data = copy.deepcopy(data)
    for job in new_data.get("jobs", []):
        if job.get("id") == OLD_JOB_ID:
            job["enabled"] = False
            job["state"] = "paused"
            job["paused_reason"] = ("superseded by aidata-digest (ADR-12); "
                                    "kept disabled for rollback")
    new_data.setdefault("jobs", []).append(build_new_job(job_id))
    return new_data


def _print_plan(data: dict, new_data: dict, jobs_file: str) -> None:
    new_job = new_data["jobs"][-1]
    old_present = any(j.get("id") == OLD_JOB_ID for j in data.get("jobs", []))
    print("=== aidata-digest cron install plan (DRY-RUN) ===")
    print(f"jobs file: {jobs_file}")
    print(f"\n1) ADD new job '{NEW_JOB_NAME}' (id {new_job['id']}):")
    print(json.dumps(new_job, ensure_ascii=False, indent=2))
    print(f"\n2) DISABLE old job {OLD_JOB_ID} (unified-daily-digest): "
          f"{'enabled→false, state→paused' if old_present else 'NOT FOUND (skip)'}")
    print(f"\n3) Runner invoked by the job: scripts/{RUNNER_SCRIPT}")
    print("\nNothing was written. Re-run with --apply to commit these changes.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs-file", default=DEFAULT_JOBS_FILE)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--dry-run", action="store_true", default=True,
                       help="print the plan, change nothing (default)")
    group.add_argument("--apply", action="store_true",
                       help="rewrite jobs.json with the planned change")
    args = parser.parse_args(argv)

    path = Path(args.jobs_file)
    if not path.exists():
        print(f"jobs file not found: {path}", file=sys.stderr)
        return 1
    data = json.loads(path.read_text(encoding="utf-8"))
    new_data = plan_changes(data)

    if args.apply:
        backup = path.with_suffix(path.suffix + ".bak")
        backup.write_text(json.dumps(data, ensure_ascii=False, indent=2),
                          encoding="utf-8")
        path.write_text(json.dumps(new_data, ensure_ascii=False, indent=2),
                        encoding="utf-8")
        print(f"applied: backup at {backup}, new registry written to {path}")
        return 0

    _print_plan(data, new_data, str(path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
