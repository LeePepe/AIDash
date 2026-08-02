"""ado_pr adapter — my Azure DevOps pull requests (EXT-4, ADR-6/13/22).

L1 collect: `az repos pr list` for the configured repo, filtered to PRs I
created. The repo lives on ADO *Server*, whose createdBy.id is a different
namespace from the AAD object id; we query by email (`--creator`) then
double-filter on the immutable ADO-native `createdBy.id` (config.ADO_CREATOR_ID)
— the ADR-22 rule "filter on an immutable id, never a display name", adapted to
ADO Server.

L2 normalize: one row per PR (last-write-wins by pullRequestId) into a clean `pr`
table that feeds the SEPARATE `fact_ado_pr` warehouse table (never fact_pr, ADR-13).

Degrade-not-crash (ADR-23): unconfigured ADO_* constants (the default — real
values live in the git-ignored config_local.py), missing/unauthed az, non-zero
rc, or bad JSON all return 0 rather than raising — the digest still produces
without this source.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from datetime import datetime, timezone
from typing import Any

from config import (
    ADO_ORG, ADO_PROJECT, ADO_REPO, ADO_CREATOR_EMAIL, ADO_CREATOR_ID,
)
from rawio import write_raw_snapshot, read_raw
from cleanio import write_clean

SOURCE = "ado_pr"


def _az_list_prs() -> list[dict[str, Any]] | None:
    """Return the raw PR list from az, or None if unconfigured/unavailable."""
    # ADO_* default to "" in config.py (real values come from the git-ignored
    # config_local.py). Unconfigured → skip cleanly rather than shelling out to
    # az with empty args, which would error anyway (ADR-23).
    if not (ADO_ORG and ADO_PROJECT and ADO_REPO
            and ADO_CREATOR_EMAIL and ADO_CREATOR_ID):
        return None
    if not shutil.which("az"):
        return None
    cmd = [
        "az", "repos", "pr", "list",
        "--repository", ADO_REPO,
        "--project", ADO_PROJECT,
        "--org", ADO_ORG,
        "--creator", ADO_CREATOR_EMAIL,
        "--status", "all",
        "--top", "500",
        "--output", "json",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, list) else None


def collect() -> int:
    """Collect my ADO PRs. Returns count written (0 on any degrade path)."""
    prs = _az_list_prs()
    if not prs:
        return 0
    mine = [p for p in prs
            if (p.get("createdBy") or {}).get("id") == ADO_CREATOR_ID]
    if not mine:
        return 0
    return write_raw_snapshot(SOURCE, mine)


_CLEAN_DDL = """
CREATE TABLE pr (
    pr_id INTEGER PRIMARY KEY, title TEXT, status TEXT,
    created_date TEXT, closed_date TEXT, creator_id TEXT,
    source_branch TEXT, target_branch TEXT, is_draft INTEGER,
    reviewers TEXT, age_hours REAL, repo TEXT
)
"""
_CLEAN_COLS = ("pr_id", "title", "status", "created_date", "closed_date",
               "creator_id", "source_branch", "target_branch", "is_draft",
               "reviewers", "age_hours", "repo")


def _strip_ref(ref: str | None) -> str | None:
    return ref.replace("refs/heads/", "") if ref else ref


def _age_hours(created: str | None) -> float | None:
    """Hours between the PR creation ISO timestamp and now (UTC)."""
    if not created:
        return None
    try:
        dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None
    return round((datetime.now(timezone.utc) - dt).total_seconds() / 3600, 1)


def _reviewers_json(pr: dict[str, Any]) -> str:
    revs = [{"name": r.get("displayName"), "vote": r.get("vote", 0)}
            for r in (pr.get("reviewers") or [])]
    return json.dumps(revs, ensure_ascii=False)


def normalize() -> int:
    rows: dict[int, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        pid = rec.get("pullRequestId")
        if pid is None:
            continue
        rows[pid] = {  # last write wins -> latest snapshot of each PR
            "pr_id": pid,
            "title": rec.get("title"),
            "status": rec.get("status"),
            "created_date": rec.get("creationDate"),
            "closed_date": rec.get("closedDate"),
            "creator_id": (rec.get("createdBy") or {}).get("id"),
            "source_branch": _strip_ref(rec.get("sourceRefName")),
            "target_branch": _strip_ref(rec.get("targetRefName")),
            "is_draft": 1 if rec.get("isDraft") else 0,
            "reviewers": _reviewers_json(rec),
            "age_hours": _age_hours(rec.get("creationDate")),
            "repo": (rec.get("repository") or {}).get("name"),
        }
    return write_clean(SOURCE, "pr", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
