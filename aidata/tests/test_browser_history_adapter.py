"""Hermetic unit tests for adapters/browser_history — no real Chrome required.

query_ro and the raw/clean/watermark IO are monkeypatched (or pointed at a temp
SQLite), so the Chrome-epoch conversion, url reduction / query-string stripping,
host extraction, watermark advance, degrade paths, and last-write-wins normalize
are all proven deterministically. The one test that DOES build a temp `urls`
table exercises the real immutable read path end-to-end.
"""

import sqlite3
from pathlib import Path

import pytest

import adapters.browser_history as bh


# A known Chrome/WebKit timestamp <-> Unix cross-check.
# Unix 2026-07-27T00:00:00Z = 1785110400. Chrome = (unix + 11644473600) * 1e6.
_UNIX_20260727 = 1785110400
_CHROME_20260727 = (_UNIX_20260727 + 11_644_473_600) * 1_000_000  # 13429583...


# ---- chrome epoch conversion (the load-bearing bit) ------------------------
@pytest.mark.unit
def test_chrome_to_unix_known_value():
    assert bh.chrome_to_unix(_CHROME_20260727) == pytest.approx(_UNIX_20260727)


@pytest.mark.unit
def test_chrome_to_unix_uses_microsecond_offset():
    # Epoch offset 11,644,473,600 s and µs scaling must both be applied.
    # chrome=0 is invalid (returns None), so use 1 second past 1601: 1e6 µs.
    assert bh.chrome_to_unix(1_000_000) == pytest.approx(1 - 11_644_473_600)


@pytest.mark.unit
def test_chrome_to_unix_rejects_zero_and_bad():
    assert bh.chrome_to_unix(0) is None
    assert bh.chrome_to_unix(-5) is None
    assert bh.chrome_to_unix(None) is None
    assert bh.chrome_to_unix("nope") is None


@pytest.mark.unit
def test_chrome_to_iso_is_cst_iso8601():
    iso = bh.chrome_to_iso(_CHROME_20260727)
    # 2026-07-27T00:00:00Z == 2026-07-27T08:00:00+08:00 (CST).
    assert iso == "2026-07-27T08:00:00+08:00"


@pytest.mark.unit
def test_chrome_to_iso_none_passthrough():
    assert bh.chrome_to_iso(0) is None
    assert bh.chrome_to_iso(None) is None


# ---- url reduction / privacy ----------------------------------------------
@pytest.mark.unit
def test_reduce_url_drops_query_and_fragment():
    reduced, host, path = bh.reduce_url(
        "https://github.com/search?q=secret_token_abc123#frag"
    )
    assert reduced == "https://github.com/search"
    assert host == "github.com"
    assert path == "/search"
    assert "secret_token_abc123" not in reduced  # query string is gone
    assert "?" not in reduced and "#" not in reduced


@pytest.mark.unit
def test_reduce_url_lowercases_host_defaults_path():
    reduced, host, path = bh.reduce_url("https://Claude.AI")
    assert host == "claude.ai"
    assert path == "/"
    assert reduced == "https://claude.ai/"


@pytest.mark.unit
def test_reduce_url_skips_hostless():
    for u in ("about:blank", "chrome://settings", "", None, "not a url"):
        assert bh.reduce_url(u) == (None, None, None)


@pytest.mark.unit
def test_title_preview_truncates():
    assert bh._title_preview("x" * 250) == "x" * bh._TITLE_PREVIEW_MAX
    assert bh._title_preview("  hi  ") == "hi"
    assert bh._title_preview("") is None
    assert bh._title_preview(None) is None


# ---- collect: degrade paths ------------------------------------------------
@pytest.mark.unit
def test_collect_degrades_when_db_missing(monkeypatch):
    monkeypatch.setattr(bh, "CHROME_HISTORY_DB", Path("/nope/does/not/exist"))
    monkeypatch.setattr(bh, "query_ro",
                        lambda *a, **k: pytest.fail("should not query a missing db"))
    assert bh.collect() == 0


@pytest.mark.unit
def test_collect_degrades_on_query_error(monkeypatch, tmp_path):
    db = tmp_path / "History"
    db.write_text("not a real sqlite file")
    monkeypatch.setattr(bh, "CHROME_HISTORY_DB", db)
    monkeypatch.setattr(bh, "get_watermark", lambda s: 0)

    def _boom(*a, **k):
        raise sqlite3.DatabaseError("database is locked")

    monkeypatch.setattr(bh, "query_ro", _boom)
    monkeypatch.setattr(bh, "write_raw",
                        lambda *a, **k: pytest.fail("no write on failure"))
    assert bh.collect() == 0  # never raises


@pytest.mark.unit
def test_collect_empty_is_zero_no_watermark(monkeypatch, tmp_path):
    db = tmp_path / "History"
    db.write_text("stub")
    monkeypatch.setattr(bh, "CHROME_HISTORY_DB", db)
    monkeypatch.setattr(bh, "get_watermark", lambda s: 0)
    monkeypatch.setattr(bh, "query_ro", lambda *a, **k: [])
    monkeypatch.setattr(bh, "set_watermark",
                        lambda *a, **k: pytest.fail("no watermark on empty"))
    monkeypatch.setattr(bh, "write_raw",
                        lambda *a, **k: pytest.fail("no write on empty"))
    assert bh.collect() == 0


# ---- collect: happy path (reduction, watermark, immutable flag) ------------
_RAW_ROWS = [
    {"url": "https://github.com/anthropics/claude-code?tab=readme#top",
     "title": "claude-code", "visit_count": 12,
     "last_visit_time": _CHROME_20260727},
    {"url": "https://claude.ai/chat/abc?token=leak", "title": "Claude",
     "visit_count": 40, "last_visit_time": _CHROME_20260727 - 500_000_000},
    {"url": "chrome://settings", "title": "Settings", "visit_count": 3,
     "last_visit_time": _CHROME_20260727 - 1},  # hostless -> skipped
]


@pytest.mark.unit
def test_collect_reduces_advances_watermark_passes_immutable(monkeypatch, tmp_path):
    db = tmp_path / "History"
    db.write_text("stub")
    monkeypatch.setattr(bh, "CHROME_HISTORY_DB", db)
    monkeypatch.setattr(bh, "get_watermark", lambda s: 0)
    captured = {}

    def _fake_query(dbp, sql, params, immutable=False):
        captured["immutable"] = immutable
        captured["params"] = params
        return _RAW_ROWS

    monkeypatch.setattr(bh, "query_ro", _fake_query)
    monkeypatch.setattr(bh, "write_raw",
                        lambda source, recs: (captured.__setitem__("recs", recs), len(recs))[1])
    monkeypatch.setattr(bh, "set_watermark",
                        lambda s, v: captured.__setitem__("wm", v))

    n = bh.collect()
    assert n == 2  # chrome:// row dropped (no host)
    assert captured["immutable"] is True  # MUST open immutable (Chrome lock)
    assert captured["params"] == (0,)
    # watermark advances to the max chrome-epoch seen.
    assert captured["wm"] == _CHROME_20260727
    recs = {r["host"]: r for r in captured["recs"]}
    assert set(recs) == {"github.com", "claude.ai"}
    # query string / fragment stripped; visit_count preserved.
    assert recs["github.com"]["url"] == "https://github.com/anthropics/claude-code"
    assert recs["github.com"]["visit_count"] == 12
    assert "token=leak" not in recs["claude.ai"]["url"]
    assert recs["claude.ai"]["url"] == "https://claude.ai/chat/abc"


@pytest.mark.unit
def test_collect_real_immutable_read(tmp_path, monkeypatch):
    # Build a real Chrome-shaped urls table and read it through the actual
    # query_ro immutable path (end-to-end, no monkeypatched query).
    db = tmp_path / "History"
    conn = sqlite3.connect(db)
    conn.execute("CREATE TABLE urls (url TEXT, title TEXT, "
                 "visit_count INTEGER, last_visit_time INTEGER)")
    conn.execute("INSERT INTO urls VALUES (?,?,?,?)",
                 ("https://stackoverflow.com/questions/1?a=b", "SO", 7,
                  _CHROME_20260727))
    conn.commit()
    conn.close()

    monkeypatch.setattr(bh, "CHROME_HISTORY_DB", db)
    monkeypatch.setattr(bh, "get_watermark", lambda s: 0)
    captured = {}
    monkeypatch.setattr(bh, "write_raw",
                        lambda source, recs: (captured.__setitem__("recs", recs), len(recs))[1])
    monkeypatch.setattr(bh, "set_watermark", lambda s, v: None)

    n = bh.collect()
    assert n == 1
    assert captured["recs"][0]["host"] == "stackoverflow.com"
    assert captured["recs"][0]["url"] == "https://stackoverflow.com/questions/1"


# ---- normalize -------------------------------------------------------------
@pytest.mark.unit
def test_normalize_host_iso_and_last_write_wins(monkeypatch):
    raw = [
        {"url": "https://github.com/x", "host": "github.com", "path": "/x",
         "title_preview": "old", "visit_count": 3,
         "last_visit_time": _CHROME_20260727 - 1_000_000},
        {"url": "https://github.com/x", "host": "github.com", "path": "/x",
         "title_preview": "new", "visit_count": 9,
         "last_visit_time": _CHROME_20260727},
        {"url": "https://claude.ai/", "host": "claude.ai", "path": "/",
         "title_preview": "Claude", "visit_count": 40,
         "last_visit_time": _CHROME_20260727},
        {"host": "no-url"},  # missing url_id -> skipped
    ]
    monkeypatch.setattr(bh, "read_raw", lambda s: raw)
    captured = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = {r["url_id"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(bh, "write_clean", _cap)
    n = bh.normalize()
    assert n == 2  # github/x collapsed (last-write-wins) + claude.ai
    gh = captured["rows"]["https://github.com/x"]
    assert gh["title_preview"] == "new" and gh["visit_count"] == 9  # last wins
    assert gh["host"] == "github.com"
    assert gh["last_visit_ts"] == "2026-07-27T08:00:00+08:00"  # ISO CST
    assert captured["cols"] == bh._CLEAN_COLS


@pytest.mark.unit
def test_normalize_group_by_host(monkeypatch):
    # Two urls on the same host -> two rows, but both share the host dimension
    # so a downstream GROUP BY host can aggregate visit_count.
    raw = [
        {"url": "https://github.com/a", "host": "github.com", "path": "/a",
         "title_preview": "a", "visit_count": 2, "last_visit_time": _CHROME_20260727},
        {"url": "https://github.com/b", "host": "github.com", "path": "/b",
         "title_preview": "b", "visit_count": 5, "last_visit_time": _CHROME_20260727},
    ]
    monkeypatch.setattr(bh, "read_raw", lambda s: raw)
    captured = {}
    monkeypatch.setattr(bh, "write_clean",
                        lambda s, t, ddl, rows, cols: captured.setdefault("rows", rows) or len(rows))
    bh.normalize()
    hosts = [r["host"] for r in captured["rows"]]
    assert hosts == ["github.com", "github.com"]
    assert sum(r["visit_count"] for r in captured["rows"]) == 7
