"""local_git adapter — MY own commit activity across every local git repo.

GitHub / ADO PRs capture the *result* of coding; they miss the *process* — the
raw daily commit stream on this machine. This source fills that gap: it walks a
few configured roots (LOCAL_GIT_SCAN_ROOTS, scoped to ~/Development, not all of
~) for `.git` repos, then for each repo runs `git log … --numstat` filtered to
MY commits and extracts one record per commit: hash, ISO time, repo name,
insertions / deletions / files-changed, and the (redacted) subject.

Author filter: read live from `git config --global user.email` — never
hard-coded. If that can't be resolved we fall back to collecting ALL commits and
tag them with author_all=True so downstream can tell filtered from unfiltered.

Incremental: a per-source watermark holds the newest commit ISO timestamp seen;
each run only asks git for commits `--since` that instant. `git log --since` is
deliberately fuzzy, so idempotency is enforced on the commit HASH (PK) — a
re-seen commit simply overwrites its own clean row, never duplicates.

L2 normalize: one row per commit, keyed by commit_hash (last-write-wins). ts is
the raw commit ISO time; downstream buckets by +8h (CST) like every other source
(ADR-2) — we store the original instant, not a pre-bucketed day.

Degrade-not-crash (ADR-23): missing git → 0; an absent root → skip it; a repo
that isn't a valid git dir or whose `git log` errors → skip that repo and keep
going. Nothing here ever raises. Privacy: only MY commits by default, subjects
run through the redact red line (rawio.write_raw), and we NEVER read diff bodies
— only numstat counts.
"""

from __future__ import annotations

import os
import shutil
import subprocess  # nosec B404 - only shell-out to the local git CLI
from typing import Any, Iterator

from config import LOCAL_GIT_SCAN_ROOTS
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark

SOURCE = "local_git"

# Depth-bound the `.git` search so we never descend into deep vendored trees
# (node_modules, Pods, .build). Repos live near the top of a project, so 4 dir
# levels below a scan root is plenty and keeps the walk fast.
_MAX_DEPTH = 4

# First-run floor when there's no watermark yet: last 30 days of commits.
_DEFAULT_SINCE = "30 days ago"

_GIT_TIMEOUT_S = 60

# git log field layout. \x1e (record separator) prefixes each commit header so we
# can split commits apart even when numstat lines sit between them; \x1f (unit
# separator) delimits fields inside the header — both are bytes that never appear
# in a commit subject, so no escaping is needed.
_REC_SEP = "\x1e"
_FIELD_SEP = "\x1f"
_PRETTY = f"format:{_REC_SEP}%H{_FIELD_SEP}%cI{_FIELD_SEP}%ae{_FIELD_SEP}%s"


def _git_bin() -> str | None:
    """Absolute path to git, or None when git isn't on PATH (degrade → 0)."""
    return shutil.which("git")


def _global_email() -> str | None:
    """MY author email from `git config --global user.email`, or None.

    Read live (never hard-coded). Any failure — no git, unset config, timeout —
    degrades to None, in which case the caller collects ALL authors instead.
    """
    binp = _git_bin()
    if not binp:
        return None
    try:
        proc = subprocess.run(  # nosec B603
            [binp, "config", "--global", "user.email"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    email = proc.stdout.strip()
    return email or None


def find_repos(roots=LOCAL_GIT_SCAN_ROOTS, max_depth: int = _MAX_DEPTH) -> list[str]:
    """Walk each root for `.git` dirs → sorted unique repo working-tree paths.

    Depth-limited (relative to each root) and prunes into `.git` internals plus
    the usual heavy vendor dirs so the scan stays bounded. A missing/unreadable
    root is skipped (degrade, not crash). Returns the repo directories (the
    parent of each `.git`), deduped across roots.
    """
    found: set[str] = set()
    for root in roots:
        root_path = os.fspath(root)
        if not os.path.isdir(root_path):
            continue  # absent root → skip (degrade)
        base_depth = root_path.rstrip(os.sep).count(os.sep)
        for dirpath, dirnames, _files in os.walk(root_path):
            depth = dirpath.count(os.sep) - base_depth
            if ".git" in dirnames:
                found.add(dirpath)
            # Prune: don't descend past max_depth, and never walk into .git
            # internals or big vendored trees (keeps the walk fast + bounded).
            if depth >= max_depth:
                dirnames[:] = []
                continue
            dirnames[:] = [
                d for d in dirnames
                if d not in (".git", "node_modules", "Pods", ".build",
                             "DerivedData", "venv", ".venv", "__pycache__")
            ]
    return sorted(found)


def _parse_numstat(lines: list[str]) -> tuple[int, int, int]:
    """Sum insertions/deletions and count changed files from numstat lines.

    numstat rows are `<ins>\\t<del>\\t<path>`; binary files show `-` for both
    counts (treated as 0 added/removed but still a changed file). Returns
    (insertions, deletions, files_changed).
    """
    insertions = deletions = files = 0
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        add, rem, _path = parts[0], parts[1], parts[2]
        files += 1
        if add.isdigit():
            insertions += int(add)
        if rem.isdigit():
            deletions += int(rem)
    return insertions, deletions, files


def _parse_log(stdout: str, repo: str) -> Iterator[dict[str, Any]]:
    """Yield one record per commit from a `git log --numstat` block.

    Splits on the record separator, then reads the header fields and the
    numstat lines that follow it up to the next commit. Malformed chunks are
    skipped rather than raising.
    """
    for chunk in stdout.split(_REC_SEP):
        chunk = chunk.strip("\n")
        if not chunk:
            continue
        header, _, rest = chunk.partition("\n")
        fields = header.split(_FIELD_SEP)
        if len(fields) < 4:
            continue  # malformed header → skip this commit
        commit_hash, iso_ts, author_email, subject = fields[0], fields[1], fields[2], fields[3]
        if not commit_hash:
            continue
        numstat_lines = [ln for ln in rest.split("\n") if "\t" in ln]
        insertions, deletions, files_changed = _parse_numstat(numstat_lines)
        yield {
            "commit_hash": commit_hash,
            "ts": iso_ts,
            "repo": repo,
            "author_email": author_email,
            "insertions": insertions,
            "deletions": deletions,
            "files_changed": files_changed,
            "subject": subject,
        }


def _git_log(repo: str, since: str, email: str | None) -> str | None:
    """Run `git log … --numstat` for one repo, or None on any degrade path.

    Filters to MY commits via --author when an email is known; otherwise
    collects all authors. Not a valid git repo, a non-zero exit, or a timeout
    all yield None so the caller skips just this repo (never raises).
    """
    binp = _git_bin()
    if not binp:
        return None
    cmd = [binp, "-C", repo, "log", f"--since={since}",
           f"--pretty={_PRETTY}", "--numstat"]
    if email:
        cmd.append(f"--author={email}")
    try:
        proc = subprocess.run(  # nosec B603
            cmd, capture_output=True, text=True, timeout=_GIT_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None  # not a git repo / git error → skip this repo
    return proc.stdout


def _repo_name(repo_path: str) -> str:
    """Human repo label = the working-tree directory's basename."""
    return os.path.basename(repo_path.rstrip(os.sep)) or repo_path


def collect() -> int:
    """Aggregate MY recent commits across every local repo. Returns count written.

    Incremental on a single ISO-timestamp watermark (newest commit seen); each
    run only asks git for commits since then, and idempotency is enforced on the
    commit hash at normalize time. Returns 0 on every degrade path (no git, no
    roots, no new commits) and skips any repo that fails — never raises.
    """
    if not _git_bin():
        return 0

    repos = find_repos()
    if not repos:
        return 0

    email = _global_email()  # None → collect all authors (fallback)
    watermark = get_watermark(SOURCE)
    since = watermark or _DEFAULT_SINCE
    author_all = email is None

    records: list[dict[str, Any]] = []
    max_ts = watermark or ""
    for repo_path in repos:
        stdout = _git_log(repo_path, since, email)
        if stdout is None:
            continue  # skip just this repo (degrade)
        name = _repo_name(repo_path)
        for rec in _parse_log(stdout, name):
            rec["author_all"] = author_all
            records.append(rec)
            ts = rec.get("ts") or ""
            if ts > max_ts:
                max_ts = ts

    if not records:
        return 0

    written = write_raw(SOURCE, records)
    # Advance the watermark to the newest commit instant (ISO-8601 strings sort
    # chronologically). Fuzzy `--since` may re-list boundary commits; the hash PK
    # dedups them at normalize, so a small overlap is harmless.
    if max_ts and (not watermark or max_ts > watermark):
        set_watermark(SOURCE, max_ts)
    return written


_CLEAN_DDL = """
CREATE TABLE commit_log (
    commit_hash TEXT PRIMARY KEY,
    ts TEXT,
    repo TEXT,
    author_email TEXT,
    insertions INTEGER,
    deletions INTEGER,
    files_changed INTEGER,
    subject TEXT
)
"""
_CLEAN_COLS = ("commit_hash", "ts", "repo", "author_email",
               "insertions", "deletions", "files_changed", "subject")


def normalize() -> int:
    """Reshape raw shards into one row per commit (PK = commit_hash).

    Last-write-wins by hash, which makes the fuzzy `--since` overlap idempotent:
    a commit re-collected on a later run just refreshes its own row. Rows without
    a hash are skipped.
    """
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        commit_hash = rec.get("commit_hash")
        if not commit_hash:
            continue
        rows[commit_hash] = {
            "commit_hash": commit_hash,
            "ts": rec.get("ts"),
            "repo": rec.get("repo"),
            "author_email": rec.get("author_email"),
            "insertions": rec.get("insertions"),
            "deletions": rec.get("deletions"),
            "files_changed": rec.get("files_changed"),
            "subject": rec.get("subject"),
        }
    return write_clean(SOURCE, "commit_log", _CLEAN_DDL,
                       list(rows.values()), _CLEAN_COLS)
