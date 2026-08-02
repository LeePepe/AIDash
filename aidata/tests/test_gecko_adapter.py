"""Hermetic unit tests for adapters/gecko — no real gecko install required.

query_ro and the raw/clean/watermark IO are monkeypatched (or pointed at a temp
SQLite), so the epoch->ISO CST conversion, url reduction / query-string stripping,
watermark advance, degrade paths, redaction pass-through, and last-write-wins
normalize are all proven deterministically. One test builds a real temp
focus_sessions table and reads it through the actual query_ro path to prove the
adapter uses a PLAIN mode=ro open (immutable=False) — the load-bearing WAL
difference from browser_history.
"""

import sqlite3
from pathlib import Path

import pytest

import adapters.gecko as gk


# A known Unix epoch <-> CST ISO cross-check.
# 2026-07-27T00:00:00Z == 2026-07-27T08:00:00+08:00 (CST). Unix = 1785110400.
_UNIX_20260727 = 1785110400


# ---- epoch -> ISO CST conversion (the load-bearing bit) --------------------
@pytest.mark.unit
def test_epoch_to_iso_is_cst_iso8601():
    assert gk.epoch_to_iso(_UNIX_20260727) == "2026-07-27T08:00:00+08:00"


@pytest.mark.unit
def test_epoch_to_iso_accepts_float_seconds():
    # gecko stores epoch SECONDS as a double; a fractional second still renders.
    iso = gk.epoch_to_iso(_UNIX_20260727 + 0.0)
    assert iso == "2026-07-27T08:00:00+08:00"


@pytest.mark.unit
def test_epoch_to_iso_rejects_zero_and_bad():
    assert gk.epoch_to_iso(0) is None
    assert gk.epoch_to_iso(-5) is None
    assert gk.epoch_to_iso(None) is None
    assert gk.epoch_to_iso("nope") is None


# ---- url reduction / privacy ----------------------------------------------
@pytest.mark.unit
def test_reduce_url_drops_query_and_fragment():
    host, path = gk.reduce_url(
        "https://github.com/search?q=secret_token_abc123#frag"
    )
    assert host == "github.com"
    assert path == "/search"


@pytest.mark.unit
def test_reduce_url_lowercases_host_defaults_path():
    host, path = gk.reduce_url("https://Claude.AI")
    assert host == "claude.ai"
    assert path == "/"


@pytest.mark.unit
def test_reduce_url_skips_hostless_and_empty():
    for u in ("about:blank", "chrome://settings", "", None, "not a url"):
        assert gk.reduce_url(u) == (None, None)


# ---- collect: degrade paths ------------------------------------------------
@pytest.mark.unit
def test_collect_degrades_when_db_missing(monkeypatch):
    monkeypatch.setattr(gk, "GECKO_DB", Path("/nope/does/not/exist.sqlite"))
    monkeypatch.setattr(gk, "query_ro",
                        lambda *a, **k: pytest.fail("should not query a missing db"))
    assert gk.collect() == 0


@pytest.mark.unit
def test_collect_degrades_on_locked_db(monkeypatch, tmp_path):
    db = tmp_path / "gecko.sqlite"
    db.write_text("not a real sqlite file")
    monkeypatch.setattr(gk, "GECKO_DB", db)
    monkeypatch.setattr(gk, "get_watermark", lambda s: 0)

    def _boom(*a, **k):
        raise sqlite3.OperationalError("database is locked")

    monkeypatch.setattr(gk, "query_ro", _boom)
    monkeypatch.setattr(gk, "write_raw",
                        lambda *a, **k: pytest.fail("no write on failure"))
    assert gk.collect() == 0  # never raises


@pytest.mark.unit
def test_collect_empty_is_zero_no_watermark(monkeypatch, tmp_path):
    db = tmp_path / "gecko.sqlite"
    db.write_text("stub")
    monkeypatch.setattr(gk, "GECKO_DB", db)
    monkeypatch.setattr(gk, "get_watermark", lambda s: 0)
    monkeypatch.setattr(gk, "query_ro", lambda *a, **k: [])
    monkeypatch.setattr(gk, "set_watermark",
                        lambda *a, **k: pytest.fail("no watermark on empty"))
    monkeypatch.setattr(gk, "write_raw",
                        lambda *a, **k: pytest.fail("no write on empty"))
    assert gk.collect() == 0


# ---- collect: happy path (reduction, watermark, mode=ro NOT immutable) -----
_RAW_ROWS = [
    {"id": "s1", "app_name": "Safari", "window_title": "GitHub",
     "url": "https://github.com/anthropics/claude-code?tab=readme#top",
     "start_time": float(_UNIX_20260727), "end_time": float(_UNIX_20260727 + 60),
     "duration": 60.0, "bundle_id": "com.apple.Safari",
     "tab_title": "claude-code", "tab_count": 5},
    {"id": "s2", "app_name": "System Settings", "window_title": "Displays",
     "url": None, "start_time": float(_UNIX_20260727 - 500),
     "end_time": float(_UNIX_20260727 - 400), "duration": 100.0,
     "bundle_id": "com.apple.systempreferences", "tab_title": None,
     "tab_count": None},
    {"id": "", "app_name": "NoPK", "window_title": "x", "url": None,
     "start_time": float(_UNIX_20260727 - 1), "end_time": None,
     "duration": 1.0, "bundle_id": None, "tab_title": None,
     "tab_count": None},  # empty id -> skipped
]


@pytest.mark.unit
def test_collect_reduces_advances_watermark_uses_plain_ro(monkeypatch, tmp_path):
    db = tmp_path / "gecko.sqlite"
    db.write_text("stub")
    monkeypatch.setattr(gk, "GECKO_DB", db)
    monkeypatch.setattr(gk, "get_watermark", lambda s: 0)
    captured = {}

    # Record the immutable kwarg to prove we open PLAIN mode=ro. gecko writes in
    # WAL mode; immutable=True would read only the base file and MISS -wal rows —
    # the opposite of browser_history. Guard against a future "unify to immutable".
    def _fake_query(dbp, sql, params, immutable=False):
        captured["immutable"] = immutable
        captured["params"] = params
        return _RAW_ROWS

    monkeypatch.setattr(gk, "query_ro", _fake_query)
    monkeypatch.setattr(gk, "write_raw",
                        lambda source, recs: (captured.__setitem__("recs", recs), len(recs))[1])
    monkeypatch.setattr(gk, "set_watermark",
                        lambda s, v: captured.__setitem__("wm", v))

    n = gk.collect()
    assert n == 2  # empty-id row dropped
    assert captured["immutable"] is False  # MUST be plain mode=ro (WAL rows)
    assert captured["params"] == (0.0,)
    # watermark advances to the max start_time seen.
    assert captured["wm"] == float(_UNIX_20260727)
    recs = {r["id"]: r for r in captured["recs"]}
    assert set(recs) == {"s1", "s2"}
    # url reduced to host+path; query string / fragment stripped; no raw url kept.
    assert recs["s1"]["url_host"] == "github.com"
    assert recs["s1"]["url_path"] == "/anthropics/claude-code"
    assert "url" not in recs["s1"]  # only reduced host/path leave collect()
    assert recs["s1"]["duration"] == 60.0
    # url-less session carries NULL host/path.
    assert recs["s2"]["url_host"] is None and recs["s2"]["url_path"] is None


@pytest.mark.unit
def test_collect_does_not_read_synced_at():
    # synced_at is cloud-sync bookkeeping with no analytic value — never selected.
    assert "synced_at" not in gk._SELECT
    assert "focus_sessions" in gk._SELECT


@pytest.mark.unit
def test_collect_real_plain_ro_read(tmp_path, monkeypatch):
    # Build a real gecko-shaped focus_sessions table and read it through the
    # ACTUAL query_ro path (no monkeypatched query) to prove the plain mode=ro
    # open works end-to-end.
    db = tmp_path / "gecko.sqlite"
    conn = sqlite3.connect(db)
    conn.execute(
        "CREATE TABLE focus_sessions ("
        "id TEXT PRIMARY KEY, app_name TEXT, window_title TEXT, url TEXT, "
        "start_time REAL, end_time REAL, duration REAL, bundle_id TEXT, "
        "tab_title TEXT, tab_count INTEGER, synced_at REAL)"
    )
    conn.execute(
        "INSERT INTO focus_sessions VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        ("r1", "Xcode", "AIDash.xcodeproj", None,
         float(_UNIX_20260727), float(_UNIX_20260727 + 120), 120.0,
         "com.apple.dt.Xcode", None, None, 999.0),
    )
    conn.commit()
    conn.close()

    monkeypatch.setattr(gk, "GECKO_DB", db)
    monkeypatch.setattr(gk, "get_watermark", lambda s: 0)
    captured = {}
    monkeypatch.setattr(gk, "write_raw",
                        lambda source, recs: (captured.__setitem__("recs", recs), len(recs))[1])
    monkeypatch.setattr(gk, "set_watermark", lambda s, v: None)

    n = gk.collect()
    assert n == 1
    rec = captured["recs"][0]
    assert rec["id"] == "r1"
    assert rec["app_name"] == "Xcode"
    assert rec["duration"] == 120.0
    assert "synced_at" not in rec  # never surfaced


# ---- collect: redaction is enforced ----------------------------------------
@pytest.mark.unit
def test_collect_redacts_sensitive_titles(monkeypatch, tmp_path):
    # write_raw runs redact_obj on every record (the enforced red line). A fake
    # token in window_title must be scrubbed before it lands in raw/.
    from rawio import write_raw as real_write_raw  # exercise the real redact path

    db = tmp_path / "gecko.sqlite"
    db.write_text("stub")
    monkeypatch.setattr(gk, "GECKO_DB", db)
    monkeypatch.setattr(gk, "get_watermark", lambda s: 0)
    monkeypatch.setattr(gk, "query_ro", lambda *a, **k: [
        {"id": "leak", "app_name": "Terminal",
         "window_title": "export GITHUB_TOKEN=ghp_ABCDEFGHIJ0123456789XYZ",
         "url": None, "start_time": float(_UNIX_20260727), "end_time": None,
         "duration": 3.0, "bundle_id": None, "tab_title": None,
         "tab_count": None},
    ])
    monkeypatch.setattr(gk, "set_watermark", lambda s, v: None)
    written = {}

    def _capture(source, records):
        written["recs"] = list(records)
        return real_write_raw(source, written["recs"])

    # Redirect the raw shard into tmp so we assert on the persisted, redacted line.
    import config
    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    import rawio
    monkeypatch.setattr(rawio, "raw_source_dir",
                        lambda s: (tmp_path / "raw" / s))
    monkeypatch.setattr(gk, "write_raw", _capture)

    n = gk.collect()
    assert n == 1
    shard_dir = tmp_path / "raw" / gk.SOURCE
    persisted = "".join(p.read_text() for p in shard_dir.glob("*.jsonl"))
    assert "ghp_ABCDEFGHIJ0123456789XYZ" not in persisted  # token redacted
    assert "<REDACTED>" in persisted


# ---- normalize -------------------------------------------------------------
@pytest.mark.unit
def test_normalize_last_write_wins_and_iso(monkeypatch):
    raw = [
        {"id": "s1", "app_name": "Safari", "window_title": "old",
         "url_host": "github.com", "url_path": "/x", "tab_title": "t",
         "tab_count": 3, "start_time": float(_UNIX_20260727 - 1000),
         "duration": 10.0},
        {"id": "s1", "app_name": "Safari", "window_title": "new",
         "url_host": "github.com", "url_path": "/x", "tab_title": "t2",
         "tab_count": 4, "start_time": float(_UNIX_20260727),
         "duration": 42.0},  # same id, later -> wins
        {"id": "s2", "app_name": "System Settings", "window_title": "Displays",
         "url_host": None, "url_path": None, "tab_title": None,
         "tab_count": None, "start_time": float(_UNIX_20260727), "duration": 5.0},
        {"app_name": "no-id"},  # missing id -> skipped
    ]
    monkeypatch.setattr(gk, "read_raw", lambda s: raw)
    captured = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = {r["session_id"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(gk, "write_clean", _cap)
    n = gk.normalize()
    assert n == 2  # s1 collapsed (last-write-wins) + s2
    s1 = captured["rows"]["s1"]
    assert s1["window_title"] == "new"  # last write wins
    assert s1["duration_sec"] == 42.0
    assert s1["ts"] == "2026-07-27T08:00:00+08:00"  # ISO CST
    assert s1["url_host"] == "github.com" and s1["url_path"] == "/x"
    # url-less session -> NULL host/path survive.
    s2 = captured["rows"]["s2"]
    assert s2["url_host"] is None and s2["url_path"] is None
    assert captured["cols"] == gk._CLEAN_COLS


@pytest.mark.unit
def test_normalize_ddl_shape():
    # The clean table contract other layers rely on.
    for col in ("session_id", "ts", "app_name", "bundle_id", "window_title",
                "url_host", "url_path", "tab_title", "tab_count", "duration_sec"):
        assert col in gk._CLEAN_DDL
    assert gk._CLEAN_COLS[0] == "session_id"  # PK first
