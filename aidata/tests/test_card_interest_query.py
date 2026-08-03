"""behavior/card-interest — spec 005 T006 whole-card star aggregation.

Hermetic: builds a throwaway aidash_events clean DB using the REAL schema from
adapters/aidash_events.py (so a drift between the adapter's DDL and this test's
fixture is impossible) and ATTACHes it via serve, running the actual
L4_serve/queries/behavior/card-interest.sql on disk — not a copy. An
integration test backstops against the live clean DB when it exists locally.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

import serve
from adapters.aidash_events import _CLEAN_DDL, _CLEAN_COLS

ROOT = Path(__file__).resolve().parent.parent


def _make_events_db(tmp_path: Path, rows: list[tuple]) -> Path:
    db = tmp_path / "aidash_events.db"
    conn = sqlite3.connect(db)
    conn.executescript(_CLEAN_DDL)
    if rows:
        placeholders = ",".join("?" for _ in _CLEAN_COLS)
        conn.executemany(
            f"INSERT INTO user_event ({','.join(_CLEAN_COLS)}) "
            f"VALUES ({placeholders})",
            rows,
        )
    conn.commit()
    conn.close()
    return db


def _make_env(tmp_path: Path, monkeypatch, rows: list[tuple]) -> None:
    """Point serve at a throwaway warehouse + aidash_events clean DB.

    WAREHOUSE_DB just needs to exist and be a valid (even empty) sqlite file —
    the query only reads through the ATTACHed `aidash_events` alias, never
    `main`. clean_path is monkeypatched so `-- aidata-attach: aidash_events`
    resolves to our fixture DB, mirroring test_serve_attach.py's pattern.
    """
    wh = tmp_path / "warehouse.db"
    sqlite3.connect(wh).close()
    monkeypatch.setattr(serve, "WAREHOUSE_DB", wh)
    events_db = _make_events_db(tmp_path, rows)
    monkeypatch.setattr(
        serve, "clean_path",
        lambda s: events_db if s == "aidash_events" else tmp_path / f"{s}.db",
    )


@pytest.mark.unit
def test_counts_whole_card_stars_by_type_excludes_item_star(tmp_path, monkeypatch):
    """The item_ref IS NULL filter (spec 005 D1) is the whole point of this
    query: a single-item star on a radar card (item_ref = repo url) must NOT
    inflate that card type's whole-card total."""
    rows = [
        ("e1", "2026-08-01T00:00:00Z", "Mac", "c1", "star", None, "insight"),
        ("e2", "2026-08-01T00:00:00Z", "Mac", "c2", "star", None, "insight"),
        ("e3", "2026-08-01T00:00:00Z", "Mac", "c3", "star", None, "trending"),
        # single-item star (item_ref set) — must not count toward "trending"
        ("e4", "2026-08-01T00:00:00Z", "Mac", "c3", "star",
         "https://github.com/a/b", "trending"),
        # a `done` event must never count as a star
        ("e5", "2026-08-01T00:00:00Z", "Mac", "c4", "done", None, "todoList"),
        # an event with no card_type (predates spec 005 D2) must be excluded,
        # not folded into some "unknown" bucket
        ("e6", "2026-08-01T00:00:00Z", "Mac", "c5", "star", None, None),
    ]
    _make_env(tmp_path, monkeypatch, rows)
    result_rows, cols = serve.run_query("behavior/card-interest")
    assert cols == ["card_type", "star_count"]
    by_type = dict(result_rows)
    assert by_type == {"insight": 2, "trending": 1}


@pytest.mark.unit
def test_since_param_excludes_events_before_window(tmp_path, monkeypatch):
    rows = [
        ("e1", "2026-08-01T00:00:00Z", "Mac", "c1", "star", None, "insight"),
        ("e2", "2026-07-01T00:00:00Z", "Mac", "c2", "star", None, "insight"),
    ]
    _make_env(tmp_path, monkeypatch, rows)
    result_rows, _cols = serve.run_query(
        "behavior/card-interest", {"since": "2026-07-25"})
    assert result_rows == [("insight", 1)]


@pytest.mark.unit
def test_bare_call_is_all_time(tmp_path, monkeypatch):
    """serve.run_query auto-binds a missing :since to NULL — a bare call (as
    L5 would make with report_date=None) must not silently exclude everything."""
    rows = [
        ("e1", "2026-01-01T00:00:00Z", "Mac", "c1", "star", None, "insight"),
    ]
    _make_env(tmp_path, monkeypatch, rows)
    result_rows, _cols = serve.run_query("behavior/card-interest")
    assert result_rows == [("insight", 1)]


@pytest.mark.unit
def test_empty_source_returns_empty_not_error(tmp_path, monkeypatch):
    _make_env(tmp_path, monkeypatch, [])
    rows, _cols = serve.run_query("behavior/card-interest")
    assert rows == []  # degrade-safe (ADR-23): empty result set, no raise


@pytest.mark.integration
@pytest.mark.skipif(
    not (ROOT / "L2_normalize" / "clean" / "aidash_events.db").exists(),
    reason="aidash_events clean db not collected locally",
)
def test_against_live_clean_db():
    rows, cols = serve.run_query("behavior/card-interest")
    assert cols == ["card_type", "star_count"]
    for card_type, count in rows:
        assert isinstance(card_type, str) and count > 0
