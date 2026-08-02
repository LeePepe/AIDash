"""Hermetic unit tests for adapters/github_pr — no live gh auth required.

subprocess/gh and the raw/clean IO are monkeypatched, so these prove the
collect/normalize logic and the degrade-not-crash paths deterministically.
Mirrors tests/test_ado_pr_adapter.py.
"""

import json

import pytest

import adapters.github_pr as ghpr


@pytest.fixture(autouse=True)
def _configured(monkeypatch):
    """Pin the repo list so tests never depend on this machine's config.

    GITHUB_PR_REPOS defaults to () (real values live in the git-ignored
    config_local.py), so without this the collect tests would pass locally and
    fail on a fresh clone / CI. test_collect_degrades_when_unconfigured covers
    the empty case deliberately.
    """
    monkeypatch.setattr(ghpr, "GITHUB_PR_REPOS", ("owner/repo",))


# One PR as `gh pr list --json ...` returns it (camelCase fields).
_PR_OPEN = {
    "number": 122,
    "title": "feat(AIDashUI): star affordance for trending",
    "state": "OPEN",
    "createdAt": "2026-07-20T10:00:00Z",
    "mergedAt": None,
    "closedAt": None,
    "url": "https://github.com/owner/repo/pull/122",
    "isDraft": False,
}
_PR_MERGED = {
    "number": 121,
    "title": "feat(core): UserEvent 加可选 itemRef",
    "state": "MERGED",
    "createdAt": "2026-07-20T08:00:00Z",
    "mergedAt": "2026-07-20T12:00:00Z",
    "closedAt": "2026-07-20T12:00:00Z",
    "url": "https://github.com/owner/repo/pull/121",
    "isDraft": False,
}


class _Proc:
    def __init__(self, rc: int, out: str):
        self.returncode = rc
        self.stdout = out
        self.stderr = ""


# --- collect: degrade-not-crash paths -------------------------------------
@pytest.mark.unit
def test_collect_returns_0_when_gh_missing(monkeypatch):
    monkeypatch.setattr(ghpr.shutil, "which", lambda _: None)
    assert ghpr.collect() == 0


@pytest.mark.unit
def test_collect_returns_0_on_gh_error(monkeypatch):
    monkeypatch.setattr(ghpr.shutil, "which", lambda _: "/usr/bin/gh")
    monkeypatch.setattr(ghpr.subprocess, "run",
                        lambda *a, **k: _Proc(1, ""))
    assert ghpr.collect() == 0


@pytest.mark.unit
def test_collect_returns_0_on_bad_json(monkeypatch):
    monkeypatch.setattr(ghpr.shutil, "which", lambda _: "/usr/bin/gh")
    monkeypatch.setattr(ghpr.subprocess, "run",
                        lambda *a, **k: _Proc(0, "not json"))
    assert ghpr.collect() == 0


@pytest.mark.unit
def test_collect_degrades_when_unconfigured(monkeypatch):
    # ADR-23: on a machine with no config_local.py, GITHUB_PR_REPOS is () —
    # collect must return 0 without writing anything.
    monkeypatch.setattr(ghpr, "GITHUB_PR_REPOS", ())
    monkeypatch.setattr(ghpr.shutil, "which", lambda _: "/usr/bin/gh")
    monkeypatch.setattr(ghpr, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("should not write"))
    assert ghpr.collect() == 0


@pytest.mark.unit
def test_collect_writes_prs_across_repos(monkeypatch):
    monkeypatch.setattr(ghpr.shutil, "which", lambda _: "/usr/bin/gh")

    # gh is called once per configured repo; return the two PRs for the first
    # repo, empty for any others.
    calls = {"n": 0}

    def fake_run(cmd, **kw):
        calls["n"] += 1
        if calls["n"] == 1:
            return _Proc(0, json.dumps([_PR_OPEN, _PR_MERGED]))
        return _Proc(0, json.dumps([]))

    monkeypatch.setattr(ghpr.subprocess, "run", fake_run)
    written = {}

    def fake_write(src, recs):
        written[src] = recs
        return len(recs)

    monkeypatch.setattr(ghpr, "write_raw_snapshot", fake_write)
    n = ghpr.collect()
    assert n == 2
    # the repo is stamped onto each record so multi-repo PRs stay attributable
    assert all("repo" in r for r in written["github_pr"])


# --- normalize: shape + last-write-wins -----------------------------------
@pytest.mark.unit
def test_normalize_one_row_per_pr(monkeypatch):
    raw = [
        {**_PR_OPEN, "repo": "owner/repo"},
        # a later snapshot of the same PR now merged -> last write wins
        {**_PR_OPEN, "repo": "owner/repo",
         "state": "MERGED", "mergedAt": "2026-07-21T09:00:00Z"},
        {**_PR_MERGED, "repo": "owner/repo"},
    ]
    monkeypatch.setattr(ghpr, "read_raw", lambda src: raw)
    captured = {}
    monkeypatch.setattr(ghpr, "write_clean",
                        lambda src, tbl, ddl, rows, cols: captured.update(
                            rows={r["pr_number"]: r for r in rows}) or len(rows))
    n = ghpr.normalize()
    assert n == 2  # two distinct PR numbers (122 deduped)
    rows = captured["rows"]
    assert rows[122]["merged_date"] == "2026-07-21T09:00:00Z"  # latest snapshot
    assert rows[122]["repo"] == "owner/repo"
    assert rows[121]["state"] == "MERGED"
