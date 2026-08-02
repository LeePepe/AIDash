"""Hermetic unit tests for adapters/github_repo — no live gh auth required.

subprocess/gh, the watchlist scan, and the raw/clean IO are monkeypatched, so
these prove the scan/collect/normalize logic and the degrade-not-crash paths
deterministically.
"""

import json

import pytest

import adapters.github_repo as gh


_GH_OK = {
    "full_name": "TauricResearch/TradingAgents",
    "stars": 93459,
    "forks": 18056,
    "description": "Multi-Agents LLM Financial Trading Framework",
    "language": "Python",
    "topics": ["agent", "finance", "llm"],
    "pushed_at": "2026-07-05T14:32:24Z",
}


class _Proc:
    def __init__(self, rc: int, out: str):
        self.returncode = rc
        self.stdout = out
        self.stderr = ""


# ---- watchlist scan --------------------------------------------------------
@pytest.mark.unit
def test_watchlist_extracts_repos_from_md(tmp_path):
    (tmp_path / "a.md").write_text(
        "- リポジトリ: https://github.com/TauricResearch/TradingAgents\n"
        "see also https://github.com/tw93/Kami for design\n",
        encoding="utf-8")
    (tmp_path / "b.md").write_text(
        "Releases: https://github.com/HKUDS/OpenHarness/releases\n"
        "clone https://github.com/HKUDS/OpenHarness.git\n",  # dedups with above
        encoding="utf-8")
    repos = gh.watchlist_repos(tmp_path)
    assert repos == [
        "HKUDS/OpenHarness",          # deeper path + .git both normalize to this
        "TauricResearch/TradingAgents",
        "tw93/Kami",
    ]


@pytest.mark.unit
def test_watchlist_missing_dir_degrades(tmp_path):
    assert gh.watchlist_repos(tmp_path / "nope") == []


@pytest.mark.unit
def test_watchlist_ignores_non_repo_github_paths(tmp_path):
    # A bare github.com URL with no repo segment must not yield a match.
    (tmp_path / "c.md").write_text("visit https://github.com/ for more\n",
                                   encoding="utf-8")
    assert gh.watchlist_repos(tmp_path) == []


@pytest.mark.unit
def test_watchlist_rejects_subdomains(tmp_path):
    # docs./api. github.com are NOT repo URLs — must not be scraped.
    (tmp_path / "d.md").write_text(
        "docs at https://docs.github.com/en/actions\n"
        "api https://api.github.com/repos/cli/cli\n",
        encoding="utf-8")
    assert gh.watchlist_repos(tmp_path) == []


@pytest.mark.unit
def test_watchlist_handles_prose_punctuation(tmp_path):
    # URLs mid-sentence (trailing , ; . ! ") must still be captured, cleanly.
    (tmp_path / "e.md").write_text(
        "see github.com/a/one, and github.com/b/two; also "
        "[link](https://github.com/c/three). done github.com/d/four!\n",
        encoding="utf-8")
    assert gh.watchlist_repos(tmp_path) == [
        "a/one", "b/two", "c/three", "d/four"]


# ---- collect ---------------------------------------------------------------
@pytest.mark.unit
def test_collect_snapshots_each_repo(monkeypatch):
    monkeypatch.setattr(gh, "watchlist_repos", lambda: ["TauricResearch/TradingAgents"])
    monkeypatch.setattr(gh.shutil, "which", lambda _: "/usr/bin/gh")
    monkeypatch.setattr(gh.subprocess, "run",
                        lambda *a, **k: _Proc(0, json.dumps(_GH_OK)))
    monkeypatch.setattr(gh, "_cst_today", lambda: "2026-07-18")
    captured = {}

    def _cap(source, records):
        captured["recs"] = records
        return len(records)

    monkeypatch.setattr(gh, "write_raw_snapshot", _cap)
    n = gh.collect()
    assert n == 1
    rec = captured["recs"][0]
    assert rec["repo"] == "TauricResearch/TradingAgents"
    assert rec["snapshot_date"] == "2026-07-18"
    assert rec["stars"] == 93459
    assert rec["provenance"] == "curated"
    assert json.loads(rec["topics"]) == ["agent", "finance", "llm"]


@pytest.mark.unit
def test_collect_no_watchlist_is_zero(monkeypatch):
    monkeypatch.setattr(gh, "watchlist_repos", lambda: [])
    monkeypatch.setattr(gh, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("should not write"))
    assert gh.collect() == 0


@pytest.mark.unit
def test_collect_degrades_when_gh_missing(monkeypatch):
    monkeypatch.setattr(gh, "watchlist_repos", lambda: ["owner/repo"])
    monkeypatch.setattr(gh.shutil, "which", lambda _: None)
    monkeypatch.setattr(gh, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("should not write"))
    assert gh.collect() == 0


@pytest.mark.unit
def test_collect_skips_failed_repo_keeps_others(monkeypatch):
    monkeypatch.setattr(gh, "watchlist_repos",
                        lambda: ["good/one", "bad/two"])
    monkeypatch.setattr(gh.shutil, "which", lambda _: "/usr/bin/gh")
    monkeypatch.setattr(gh, "_cst_today", lambda: "2026-07-18")

    def _fake(full_name):
        return dict(_GH_OK, full_name="good/one") if full_name == "good/one" else None

    monkeypatch.setattr(gh, "_gh_repo", _fake)
    captured = {}

    def _cap(source, records):
        captured["recs"] = records
        return len(records)

    monkeypatch.setattr(gh, "write_raw_snapshot", _cap)
    n = gh.collect()
    assert n == 1
    assert [r["repo"] for r in captured["recs"]] == ["good/one"]


@pytest.mark.unit
def test_gh_repo_degrades_on_error(monkeypatch):
    monkeypatch.setattr(gh.shutil, "which", lambda _: "/usr/bin/gh")
    monkeypatch.setattr(gh.subprocess, "run", lambda *a, **k: _Proc(1, ""))
    assert gh._gh_repo("owner/repo") is None


@pytest.mark.unit
def test_gh_repo_degrades_on_bad_json(monkeypatch):
    monkeypatch.setattr(gh.shutil, "which", lambda _: "/usr/bin/gh")
    monkeypatch.setattr(gh.subprocess, "run", lambda *a, **k: _Proc(0, "not json"))
    assert gh._gh_repo("owner/repo") is None


# ---- normalize -------------------------------------------------------------
@pytest.mark.unit
def test_normalize_keys_by_repo_and_date(monkeypatch):
    day1 = {"repo": "a/b", "snapshot_date": "2026-07-17", "stars": 100,
            "provenance": "curated"}
    day2 = {"repo": "a/b", "snapshot_date": "2026-07-18", "stars": 130,
            "provenance": "curated"}
    # Same repo, two days → BOTH rows kept (composite key preserves history).
    monkeypatch.setattr(gh, "read_raw", lambda source: [day1, day2])
    captured = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = rows
        return len(rows)

    monkeypatch.setattr(gh, "write_clean", _cap)
    n = gh.normalize()
    assert n == 2
    by_date = {r["snapshot_date"]: r["stars"] for r in captured["rows"]}
    assert by_date == {"2026-07-17": 100, "2026-07-18": 130}


@pytest.mark.unit
def test_normalize_same_day_last_write_wins(monkeypatch):
    a = {"repo": "a/b", "snapshot_date": "2026-07-18", "stars": 100}
    b = {"repo": "a/b", "snapshot_date": "2026-07-18", "stars": 105}
    monkeypatch.setattr(gh, "read_raw", lambda source: [a, b])
    captured = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = rows
        return len(rows)

    monkeypatch.setattr(gh, "write_clean", _cap)
    assert gh.normalize() == 1
    assert captured["rows"][0]["stars"] == 105  # latest same-day snapshot wins


@pytest.mark.unit
def test_normalize_skips_rows_missing_key(monkeypatch):
    monkeypatch.setattr(gh, "read_raw",
                        lambda source: [{"stars": 1}, {"repo": "a/b"}])
    monkeypatch.setattr(gh, "write_clean",
                        lambda s, t, ddl, rows, cols: len(rows))
    assert gh.normalize() == 0  # neither row has both repo + snapshot_date
