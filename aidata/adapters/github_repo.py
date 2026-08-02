"""github_repo adapter — the GitHub tool-radar source (v1: curated watchlist).

The user stockpiles interesting tools as Markdown notes under
COLLECTED_TOOLS_DIR (the save-tool skill), each carrying a github.com/owner/repo
URL. This adapter turns that static list into a LIVING daily radar: every run it
fetches each repo's current stars / description / language / topics / pushed_at
and stamps a CST snapshot_date, so the warehouse accumulates one row per repo
per day and downstream queries can compute star deltas.

L1 collect: scan the stockpile for repos, then `gh api repos/<owner>/<name>` for
each (reusing the user's existing gh auth — no token/secret managed here). Mirror
ado_pr's shell-out shape. write_raw_snapshot dedups by content hash, so an
unchanged day (no star moved) writes nothing.

L2 normalize: one row per (repo, snapshot_date) — keyed by the COMPOSITE so the
day-by-day star history is preserved (keying by repo alone would collapse it).

Provenance is "curated" for v1 (the watchlist). A future v2 "discovered" bucket
(trending / star-graph recommendations) reuses this same table + column.

Degrade-not-crash (ADR-23): missing gh, a failed repo fetch, or a bad folder all
skip that unit and never raise — the digest still produces without this source.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess  # nosec B404 - used only via the injected _gh_repo runner

from config import COLLECTED_TOOLS_DIR
from timeutil import cst_today
from timeutil import CST as _CST  # noqa: F401 (re-export seam)
from rawio import write_raw_snapshot, read_raw
from cleanio import write_clean

SOURCE = "github_repo"

# _CST re-exported from timeutil (seam). The snapshot day is stamped at collect
# time so no downstream +8h bucketing is needed (ADR-2): already the CST day.

# github.com/owner/repo — captures owner and repo. A negative lookbehind for a
# word char or dot rejects subdomains (docs.github.com, api.github.com) that are
# NOT repo URLs. owner/repo segments exclude "/" so we never swallow a deeper
# path (…/releases, …/tree/main) into the repo name; a trailing ".git" is
# trimmed. The repo group stops at the first URL terminator — including prose
# punctuation (, ; ! " ' ] >) so a URL mid-sentence isn't dropped — and a
# sentence-final "." is stripped in code (repo names don't end in a dot).
_REPO_URL = re.compile(
    r"(?<![\w.])github\.com/([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)"
    r"/([A-Za-z0-9._-]+?)(?:\.git)?(?=[/\s)#?,;!\"'\]>]|$)"
)

# Provenance buckets (v1 = curated only; discovered reserved for v2).
PROVENANCE_CURATED = "curated"

_GH_TIMEOUT_S = 30


def _cst_today() -> str:
    """Current CST calendar day (thin wrapper over timeutil.cst_today; seam)."""
    return cst_today()


def watchlist_repos(tools_dir=COLLECTED_TOOLS_DIR) -> list[str]:
    """Scan the stockpile's *.md notes for github repos → sorted unique "owner/name".

    Degrades to [] when the folder is absent or unreadable (ADR-23). Skips the
    README index by content, not name — any note may legitimately link repos.
    """
    if not tools_dir.exists():
        return []
    found: set[str] = set()
    try:
        md_files = sorted(tools_dir.glob("*.md"))
    except OSError:
        return []
    for md in md_files:
        try:
            text = md.read_text(encoding="utf-8")
        except OSError:
            continue
        for owner, repo in _REPO_URL.findall(text):
            repo = repo.rstrip(".")  # drop a sentence-final period (repos don't end in .)
            if repo:
                found.add(f"{owner}/{repo}")
    return sorted(found)


def _gh_repo(full_name: str) -> dict | None:
    """`gh api repos/<owner>/<name>` for one repo, or None on any degrade path.

    Returns the trimmed field set we keep. A missing gh binary, non-zero exit
    (404 / rate-limit / auth), timeout, or unparseable JSON all yield None so the
    caller skips just that repo — never raises (ADR-23).
    """
    if not shutil.which("gh"):
        return None
    jq = ("{stars: .stargazers_count, forks: .forks_count, "
          "description: .description, language: .language, "
          "topics: .topics, pushed_at: .pushed_at, "
          "full_name: .full_name}")
    cmd = ["gh", "api", f"repos/{full_name}", "--jq", jq]
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
    return data if isinstance(data, dict) else None


def collect() -> int:
    """Snapshot each watchlist repo's stars/metadata for today (CST).

    Returns records written (0 on any degrade path: no gh, no repos, or an
    unchanged snapshot). Repos that fail to fetch are skipped, not fatal.
    """
    repos = watchlist_repos()
    if not repos:
        return 0
    if not shutil.which("gh"):
        return 0
    snapshot_date = _cst_today()
    records: list[dict] = []
    for full_name in repos:
        data = _gh_repo(full_name)
        if data is None:
            continue  # skip just this repo; keep going (degrade, not crash)
        records.append({
            "repo": data.get("full_name") or full_name,
            "snapshot_date": snapshot_date,
            "stars": data.get("stars"),
            "forks": data.get("forks"),
            "description": data.get("description"),
            "language": data.get("language"),
            "topics": json.dumps(data.get("topics") or [], ensure_ascii=False),
            "pushed_at": data.get("pushed_at"),
            "provenance": PROVENANCE_CURATED,
        })
    if not records:
        return 0
    return write_raw_snapshot(SOURCE, records)


_CLEAN_DDL = """
CREATE TABLE repo_snapshot (
    repo TEXT NOT NULL, snapshot_date TEXT NOT NULL,
    stars INTEGER, forks INTEGER, description TEXT, language TEXT,
    topics TEXT, pushed_at TEXT, provenance TEXT,
    PRIMARY KEY (repo, snapshot_date)
)
"""
_CLEAN_COLS = ("repo", "snapshot_date", "stars", "forks", "description",
               "language", "topics", "pushed_at", "provenance")


def normalize() -> int:
    """Reshape raw shards into one row per (repo, snapshot_date).

    Keyed by the COMPOSITE (repo, day) so every day's snapshot survives — this is
    what makes the star history (and thus the delta) computable. Last write wins
    within a single (repo, day), which is correct: a same-day re-collect just
    refreshes that day's row.
    """
    rows: dict[tuple[str, str], dict] = {}
    for rec in read_raw(SOURCE):
        repo = rec.get("repo")
        day = rec.get("snapshot_date")
        if not repo or not day:
            continue
        rows[(repo, day)] = {
            "repo": repo,
            "snapshot_date": day,
            "stars": rec.get("stars"),
            "forks": rec.get("forks"),
            "description": rec.get("description"),
            "language": rec.get("language"),
            "topics": rec.get("topics"),
            "pushed_at": rec.get("pushed_at"),
            "provenance": rec.get("provenance") or PROVENANCE_CURATED,
        }
    return write_clean(SOURCE, "repo_snapshot", _CLEAN_DDL,
                       list(rows.values()), _CLEAN_COLS)
