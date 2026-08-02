"""Hermetic unit tests for adapters/local_git — no live git repos required.

subprocess/git, the repo walk, the watermark, and raw/clean IO are
monkeypatched, so these prove the log parsing, numstat math, incremental
watermark advance, hash-idempotent normalize, and every degrade-not-crash path
deterministically — without touching the machine's real repos. One test drives
the REAL write_raw to prove the subject/redaction red line runs.
"""

import pytest

import adapters.local_git as lg


# A two-commit `git log --numstat` block in the adapter's own field layout:
# \x1e prefixes each commit header, \x1f delimits header fields, numstat rows
# (`ins\tdel\tpath`) follow. Commit c1 has a binary file (`-\t-`) too.
def _log(commits):
    """Build a fake `git log --pretty --numstat` stdout from a spec list.

    Each commit spec: (hash, iso, email, subject, [(ins, del, path), ...]).
    """
    out = []
    for h, iso, email, subj, files in commits:
        header = lg._REC_SEP + lg._FIELD_SEP.join([h, iso, email, subj])
        out.append(header)
        for ins, dele, path in files:
            out.append(f"{ins}\t{dele}\t{path}")
    return "\n".join(out)


_COMMITS = [
    ("hash1", "2026-07-25T10:00:00+08:00", "me@qq.com", "feat: add thing",
     [("10", "2", "a.py"), ("5", "0", "b.py")]),
    ("hash2", "2026-07-26T12:00:00+08:00", "me@qq.com", "fix: a bug",
     [("3", "1", "c.py"), ("-", "-", "logo.png")]),  # binary file → 0/0, +1 file
]


class _Proc:
    def __init__(self, rc, out):
        self.returncode = rc
        self.stdout = out
        self.stderr = ""


# ---- email resolution ------------------------------------------------------
@pytest.mark.unit
def test_global_email_reads_git_config(monkeypatch):
    monkeypatch.setattr(lg.shutil, "which", lambda _: "/usr/bin/git")
    monkeypatch.setattr(lg.subprocess, "run",
                        lambda *a, **k: _Proc(0, "me@qq.com\n"))
    assert lg._global_email() == "me@qq.com"


@pytest.mark.unit
def test_global_email_none_when_unset(monkeypatch):
    monkeypatch.setattr(lg.shutil, "which", lambda _: "/usr/bin/git")
    monkeypatch.setattr(lg.subprocess, "run", lambda *a, **k: _Proc(0, "\n"))
    assert lg._global_email() is None


@pytest.mark.unit
def test_global_email_none_when_git_missing(monkeypatch):
    monkeypatch.setattr(lg.shutil, "which", lambda _: None)
    assert lg._global_email() is None


@pytest.mark.unit
def test_global_email_none_on_error(monkeypatch):
    monkeypatch.setattr(lg.shutil, "which", lambda _: "/usr/bin/git")
    monkeypatch.setattr(lg.subprocess, "run", lambda *a, **k: _Proc(1, ""))
    assert lg._global_email() is None


# ---- repo walk -------------------------------------------------------------
@pytest.mark.unit
def test_find_repos_discovers_git_dirs(tmp_path):
    (tmp_path / "proj_a" / ".git").mkdir(parents=True)
    (tmp_path / "proj_b" / ".git").mkdir(parents=True)
    (tmp_path / "not_a_repo").mkdir()
    repos = lg.find_repos([tmp_path])
    names = sorted(lg._repo_name(r) for r in repos)
    assert names == ["proj_a", "proj_b"]


@pytest.mark.unit
def test_find_repos_missing_root_degrades(tmp_path):
    assert lg.find_repos([tmp_path / "nope"]) == []


@pytest.mark.unit
def test_find_repos_respects_max_depth(tmp_path):
    # A repo buried below max_depth must not be found.
    deep = tmp_path / "a" / "b" / "c" / "d" / "e" / "deep_repo"
    (deep / ".git").mkdir(parents=True)
    shallow = tmp_path / "top_repo"
    (shallow / ".git").mkdir(parents=True)
    repos = lg.find_repos([tmp_path], max_depth=2)
    names = [lg._repo_name(r) for r in repos]
    assert "top_repo" in names
    assert "deep_repo" not in names


@pytest.mark.unit
def test_find_repos_prunes_vendor_dirs(tmp_path):
    # A `.git` nested inside node_modules must be pruned (not scanned).
    vendor = tmp_path / "proj" / "node_modules" / "dep"
    (vendor / ".git").mkdir(parents=True)
    (tmp_path / "proj" / ".git").mkdir(parents=True)
    repos = lg.find_repos([tmp_path])
    names = [lg._repo_name(r) for r in repos]
    assert names == ["proj"]  # dep under node_modules pruned


# ---- numstat parsing -------------------------------------------------------
@pytest.mark.unit
def test_parse_numstat_sums_and_counts():
    ins, dele, files = lg._parse_numstat(
        ["10\t2\ta.py", "5\t0\tb.py", "-\t-\tlogo.png"])
    assert (ins, dele, files) == (15, 2, 3)  # binary counts 0/0 but is a file


@pytest.mark.unit
def test_parse_numstat_ignores_malformed_lines():
    ins, dele, files = lg._parse_numstat(["garbage", "1\t1\tx"])
    assert (ins, dele, files) == (1, 1, 1)


# ---- log parsing -----------------------------------------------------------
@pytest.mark.unit
def test_parse_log_extracts_commits():
    recs = list(lg._parse_log(_log(_COMMITS), "AIDash"))
    assert len(recs) == 2
    r1, r2 = recs
    assert r1["commit_hash"] == "hash1"
    assert r1["ts"] == "2026-07-25T10:00:00+08:00"
    assert r1["repo"] == "AIDash"
    assert r1["author_email"] == "me@qq.com"
    assert r1["insertions"] == 15
    assert r1["deletions"] == 2
    assert r1["files_changed"] == 2
    assert r1["subject"] == "feat: add thing"
    # binary file in c2 still counts as a changed file, 0 ins/del
    assert r2["insertions"] == 3
    assert r2["deletions"] == 1
    assert r2["files_changed"] == 2


@pytest.mark.unit
def test_parse_log_handles_empty_output():
    assert list(lg._parse_log("", "repo")) == []


@pytest.mark.unit
def test_parse_log_skips_malformed_header():
    # A chunk with too few fields is skipped, a valid one kept.
    bad = lg._REC_SEP + "onlyhash"
    good = lg._REC_SEP + lg._FIELD_SEP.join(
        ["h", "2026-07-25T00:00:00Z", "e@x.com", "subj"])
    recs = list(lg._parse_log(bad + "\n" + good, "repo"))
    assert [r["commit_hash"] for r in recs] == ["h"]


# ---- collect: happy path ---------------------------------------------------
@pytest.mark.unit
def test_collect_aggregates_and_advances_watermark(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg, "find_repos", lambda: ["/x/AIDash", "/x/aidata"])
    monkeypatch.setattr(lg, "_global_email", lambda: "me@qq.com")
    monkeypatch.setattr(lg, "_git_log",
                        lambda repo, since, email: _log(_COMMITS))
    store = {}
    monkeypatch.setattr(lg, "get_watermark", lambda s: store.get(s))
    monkeypatch.setattr(lg, "set_watermark", lambda s, v: store.__setitem__(s, v))
    written = []

    def _cap(source, records):
        recs = list(records)
        written.extend(recs)
        return len(recs)

    monkeypatch.setattr(lg, "write_raw", _cap)

    n = lg.collect()
    assert n == 4  # 2 commits x 2 repos
    # watermark advanced to the newest commit timestamp
    assert store[lg.SOURCE] == "2026-07-26T12:00:00+08:00"
    assert all(r["author_all"] is False for r in written)


@pytest.mark.unit
def test_collect_uses_watermark_as_since(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg, "find_repos", lambda: ["/x/AIDash"])
    monkeypatch.setattr(lg, "_global_email", lambda: "me@qq.com")
    captured = {}

    def _spy(repo, since, email):
        captured["since"] = since
        captured["email"] = email
        return _log(_COMMITS)

    monkeypatch.setattr(lg, "_git_log", _spy)
    monkeypatch.setattr(lg, "get_watermark", lambda s: "2026-07-24T00:00:00+08:00")
    monkeypatch.setattr(lg, "set_watermark", lambda s, v: None)
    monkeypatch.setattr(lg, "write_raw", lambda s, r: len(list(r)))
    lg.collect()
    assert captured["since"] == "2026-07-24T00:00:00+08:00"
    assert captured["email"] == "me@qq.com"


@pytest.mark.unit
def test_collect_first_run_uses_default_since(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg, "find_repos", lambda: ["/x/AIDash"])
    monkeypatch.setattr(lg, "_global_email", lambda: "me@qq.com")
    captured = {}

    def _spy(repo, since, email):
        captured["since"] = since
        return _log(_COMMITS)

    monkeypatch.setattr(lg, "_git_log", _spy)
    monkeypatch.setattr(lg, "get_watermark", lambda s: None)
    monkeypatch.setattr(lg, "set_watermark", lambda s, v: None)
    monkeypatch.setattr(lg, "write_raw", lambda s, r: len(list(r)))
    lg.collect()
    assert captured["since"] == lg._DEFAULT_SINCE


@pytest.mark.unit
def test_collect_no_email_collects_all_authors_tagged(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg, "find_repos", lambda: ["/x/AIDash"])
    monkeypatch.setattr(lg, "_global_email", lambda: None)  # can't resolve email
    captured = {}

    def _spy(repo, since, email):
        captured["email"] = email
        return _log(_COMMITS)

    monkeypatch.setattr(lg, "_git_log", _spy)
    monkeypatch.setattr(lg, "get_watermark", lambda s: None)
    monkeypatch.setattr(lg, "set_watermark", lambda s, v: None)
    written = []
    monkeypatch.setattr(lg, "write_raw",
                        lambda s, r: (written.extend(r), len(written))[1])
    lg.collect()
    assert captured["email"] is None  # no --author filter
    assert all(r["author_all"] is True for r in written)  # tagged as unfiltered


@pytest.mark.unit
def test_collect_skips_failed_repo_keeps_others(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg, "find_repos", lambda: ["/x/good", "/x/bad"])
    monkeypatch.setattr(lg, "_global_email", lambda: "me@qq.com")

    def _log_or_none(repo, since, email):
        return _log(_COMMITS) if repo == "/x/good" else None

    monkeypatch.setattr(lg, "_git_log", _log_or_none)
    monkeypatch.setattr(lg, "get_watermark", lambda s: None)
    monkeypatch.setattr(lg, "set_watermark", lambda s, v: None)
    written = []
    monkeypatch.setattr(lg, "write_raw",
                        lambda s, r: (written.extend(r), len(written))[1])
    n = lg.collect()
    assert n == 2  # only the good repo's 2 commits
    assert {r["repo"] for r in written} == {"good"}


# ---- collect: degrade-not-crash -------------------------------------------
@pytest.mark.unit
def test_collect_degrades_when_git_missing(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: None)
    monkeypatch.setattr(lg, "write_raw",
                        lambda *a, **k: pytest.fail("no git → no write"))
    assert lg.collect() == 0


@pytest.mark.unit
def test_collect_no_repos_is_zero(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg, "find_repos", lambda: [])
    monkeypatch.setattr(lg, "write_raw",
                        lambda *a, **k: pytest.fail("no repos → no write"))
    assert lg.collect() == 0


@pytest.mark.unit
def test_collect_no_commits_is_zero_no_watermark_advance(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg, "find_repos", lambda: ["/x/AIDash"])
    monkeypatch.setattr(lg, "_global_email", lambda: "me@qq.com")
    monkeypatch.setattr(lg, "_git_log", lambda *a, **k: "")  # no commits
    monkeypatch.setattr(lg, "get_watermark", lambda s: "2026-07-24T00:00:00+08:00")
    monkeypatch.setattr(lg, "set_watermark",
                        lambda s, v: pytest.fail("no advance on empty"))
    monkeypatch.setattr(lg, "write_raw",
                        lambda *a, **k: pytest.fail("empty → no write"))
    assert lg.collect() == 0


# ---- _git_log degrade paths ------------------------------------------------
@pytest.mark.unit
def test_git_log_degrades_on_nonzero_exit(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg.subprocess, "run", lambda *a, **k: _Proc(128, ""))
    assert lg._git_log("/not/a/repo", "30 days ago", "me@qq.com") is None


@pytest.mark.unit
def test_git_log_degrades_on_timeout(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")

    def _boom(*a, **k):
        raise lg.subprocess.TimeoutExpired(cmd="git", timeout=60)

    monkeypatch.setattr(lg.subprocess, "run", _boom)
    assert lg._git_log("/x/repo", "30 days ago", None) is None


@pytest.mark.unit
def test_git_log_omits_author_when_no_email(monkeypatch):
    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    captured = {}

    def _spy(cmd, *a, **k):
        captured["cmd"] = cmd
        return _Proc(0, "")

    monkeypatch.setattr(lg.subprocess, "run", _spy)
    lg._git_log("/x/repo", "30 days ago", None)
    assert not any(c.startswith("--author=") for c in captured["cmd"])
    lg._git_log("/x/repo", "30 days ago", "me@qq.com")
    assert "--author=me@qq.com" in captured["cmd"]


# ---- redaction red line (REAL write_raw) -----------------------------------
@pytest.mark.unit
def test_collect_redacts_subject_via_real_write_raw(monkeypatch, tmp_path):
    """A secret in a commit subject is scrubbed by the real write_raw path."""
    import config
    import rawio
    monkeypatch.setattr(config, "RAW_DIR", tmp_path, raising=False)
    monkeypatch.setattr(rawio, "raw_source_dir",
                        lambda src: tmp_path / src, raising=False)

    monkeypatch.setattr(lg, "_git_bin", lambda: "/usr/bin/git")
    monkeypatch.setattr(lg, "find_repos", lambda: ["/x/AIDash"])
    monkeypatch.setattr(lg, "_global_email", lambda: "me@qq.com")
    secret_commit = [(
        "h9", "2026-07-26T00:00:00Z", "me@qq.com",
        "chore: set token=abcdef0123456789ABCDEF in ci",
        [("1", "0", "ci.yml")],
    )]
    monkeypatch.setattr(lg, "_git_log", lambda *a, **k: _log(secret_commit))
    monkeypatch.setattr(lg, "get_watermark", lambda s: None)
    monkeypatch.setattr(lg, "set_watermark", lambda s, v: None)

    assert lg.collect() == 1
    shards = list((tmp_path / lg.SOURCE).glob("*.jsonl"))
    assert shards
    body = shards[0].read_text(encoding="utf-8")
    assert "abcdef0123456789ABCDEF" not in body  # secret scrubbed
    assert "<REDACTED>" in body


# ---- normalize -------------------------------------------------------------
@pytest.mark.unit
def test_normalize_one_row_per_commit(monkeypatch):
    raw = [
        {"commit_hash": "h1", "ts": "2026-07-25T10:00:00+08:00", "repo": "AIDash",
         "author_email": "me@qq.com", "insertions": 15, "deletions": 2,
         "files_changed": 2, "subject": "feat: x"},
        {"commit_hash": "h2", "ts": "2026-07-26T12:00:00+08:00", "repo": "aidata",
         "author_email": "me@qq.com", "insertions": 3, "deletions": 1,
         "files_changed": 1, "subject": "fix: y"},
    ]
    monkeypatch.setattr(lg, "read_raw", lambda s: raw)
    captured = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = {r["commit_hash"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(lg, "write_clean", _cap)
    assert lg.normalize() == 2
    assert captured["cols"] == (
        "commit_hash", "ts", "repo", "author_email",
        "insertions", "deletions", "files_changed", "subject")
    assert captured["rows"]["h1"]["repo"] == "AIDash"
    assert captured["rows"]["h2"]["insertions"] == 3


@pytest.mark.unit
def test_normalize_last_write_wins_by_hash(monkeypatch):
    # Same hash re-collected (fuzzy --since overlap): later shard refreshes it,
    # never duplicates — proves hash idempotency.
    raw = [
        {"commit_hash": "h1", "ts": "t", "repo": "AIDash", "insertions": 10},
        {"commit_hash": "h1", "ts": "t", "repo": "AIDash", "insertions": 12},
    ]
    monkeypatch.setattr(lg, "read_raw", lambda s: raw)
    captured = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = rows
        return len(rows)

    monkeypatch.setattr(lg, "write_clean", _cap)
    assert lg.normalize() == 1
    assert captured["rows"][0]["insertions"] == 12  # latest wins


@pytest.mark.unit
def test_normalize_skips_rows_without_hash(monkeypatch):
    monkeypatch.setattr(lg, "read_raw",
                        lambda s: [{"ts": "t", "repo": "x"}, {"insertions": 1}])
    monkeypatch.setattr(lg, "write_clean",
                        lambda s, t, ddl, rows, cols: len(rows))
    assert lg.normalize() == 0
