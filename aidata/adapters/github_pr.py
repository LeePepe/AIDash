"""github_pr adapter — my GitHub pull requests (the counterpart to ado_pr).

Why this exists: the digest's "开了 N 个 PR（合并 N 个）" line was fed ONLY by
ado_pr (Azure DevOps). All of my personal-project PRs live on
GitHub and were never collected, so the line read 0 even
on days with many merged PRs. This source closes that gap.

L1 collect: `gh pr list --author @me --json …` for each configured GitHub repo,
reusing the user's existing gh auth (no token/secret managed here). Mirrors
ado_pr's shell-out shape; the repo is stamped onto each record so PRs across
several repos stay attributable.

L2 normalize: one row per (repo, pr_number) — last-write-wins by that composite
so the latest snapshot of each PR survives — into a clean `github_pr` table that
feeds the SEPARATE `fact_github_pr` warehouse table (never fact_pr / fact_ado_pr,
mirroring ADR-13's "one table per PR provenance").

Degrade-not-crash (ADR-23): missing gh, a non-zero exit, a timeout, or bad JSON
all yield 0 rather than raising — the digest still produces without this source.
"""

from __future__ import annotations

import json
import shutil
import subprocess  # nosec B404 - used only via the injected gh runner

from config import GITHUB_PR_REPOS
from rawio import write_raw_snapshot, read_raw
from cleanio import write_clean

SOURCE = "github_pr"

# Fields pulled per PR. `gh pr list --json` returns camelCase keys.
_GH_FIELDS = "number,title,state,createdAt,mergedAt,closedAt,url,isDraft"
_GH_TIMEOUT_S = 60


def _gh_list_prs(repo: str) -> list[dict] | None:
    """`gh pr list` for one repo (my PRs, all states), or None on any degrade.

    A missing gh binary, non-zero exit (auth / rate-limit), timeout, or
    unparseable JSON all yield None so the caller skips just that repo.
    """
    if not shutil.which("gh"):
        return None
    cmd = [
        "gh", "pr", "list",
        "--repo", repo,
        "--author", "@me",
        "--state", "all",
        "--limit", "200",
        "--json", _GH_FIELDS,
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,  # nosec B603
                              timeout=_GH_TIMEOUT_S)
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
    """Snapshot my PRs across the configured GitHub repos.

    Returns records written (0 on any degrade path: no gh, no repos, or an
    unchanged snapshot). Repos that fail to fetch are skipped, not fatal.
    """
    if not shutil.which("gh"):
        return 0
    records: list[dict] = []
    for repo in GITHUB_PR_REPOS:
        prs = _gh_list_prs(repo)
        if not prs:
            continue  # skip just this repo; keep going (degrade, not crash)
        for pr in prs:
            records.append({**pr, "repo": repo})
    if not records:
        return 0
    return write_raw_snapshot(SOURCE, records)


_CLEAN_DDL = """
CREATE TABLE github_pr (
    repo TEXT NOT NULL, pr_number INTEGER NOT NULL,
    title TEXT, state TEXT,
    created_date TEXT, merged_date TEXT, closed_date TEXT,
    url TEXT, is_draft INTEGER,
    PRIMARY KEY (repo, pr_number)
)
"""
_CLEAN_COLS = ("repo", "pr_number", "title", "state",
               "created_date", "merged_date", "closed_date",
               "url", "is_draft")


def normalize() -> int:
    """Reshape raw shards into one row per (repo, pr_number).

    Keyed by the COMPOSITE (repo, pr_number) so a PR number that repeats across
    repos never collapses; last write wins within a single key, which is correct
    (a later snapshot just refreshes that PR's state/merged_date).
    """
    rows: dict[tuple[str, int], dict] = {}
    for rec in read_raw(SOURCE):
        repo = rec.get("repo")
        num = rec.get("number")
        if repo is None or num is None:
            continue
        rows[(repo, num)] = {  # last write wins -> latest snapshot of each PR
            "repo": repo,
            "pr_number": num,
            "title": rec.get("title"),
            "state": rec.get("state"),
            "created_date": rec.get("createdAt"),
            "merged_date": rec.get("mergedAt"),
            "closed_date": rec.get("closedAt"),
            "url": rec.get("url"),
            "is_draft": 1 if rec.get("isDraft") else 0,
        }
    return write_clean(SOURCE, "github_pr", _CLEAN_DDL,
                       list(rows.values()), _CLEAN_COLS)
