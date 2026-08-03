"""T1 — on-demand ATTACH in serve.py.

Guards the fix that replaced "unconditionally ATTACH every existing L2-only
clean DB" (which hit SQLite's 10-attach ceiling the moment an 11th L2-only DB
appeared on disk, taking down *all* L4 queries at connect time) with per-query
`-- aidata-attach:` declarations.

Split by data dependency:
  * Hermetic tests (default, run under `-m "not integration"`): build tiny
    throwaway warehouse/clean/query dirs and monkeypatch serve's module globals.
    They prove the attach *mechanism* without needing the live warehouse.
  * The 35-query sweep (a) is marked `integration` — it runs every real query
    against the built warehouse.db to catch a missing/typo'd attach header
    ("no such table") or an over-attach.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

import serve
from config import SOURCES, MERGE_SOURCES, QUERIES_DIR

# The 11 sources that stop at L2 (un-merged) — each read directly from its clean
# DB and therefore ATTACHed on demand. This is exactly the set that used to be
# attached unconditionally and blew past SQLite's limit.
L2_ONLY = tuple(s for s in SOURCES if s not in MERGE_SOURCES)


# --------------------------------------------------------------------------- #
# Hermetic scaffolding
# --------------------------------------------------------------------------- #
def _make_env(tmp_path, monkeypatch, *, clean_dbs, queries):
    """Point serve at throwaway warehouse/clean/query dirs.

    serve.py binds WAREHOUSE_DB / QUERIES_DIR / clean_path at import time, so we
    monkeypatch the names on the serve module (patching config would not reach
    the already-bound references).
    """
    wh = tmp_path / "warehouse.db"
    con = sqlite3.connect(wh)
    con.execute("CREATE TABLE fact_probe(x INTEGER)")
    con.execute("INSERT INTO fact_probe VALUES (1)")
    con.commit()
    con.close()

    clean_dir = tmp_path / "clean"
    clean_dir.mkdir()
    for name in clean_dbs:
        c = sqlite3.connect(clean_dir / f"{name}.db")
        c.execute("CREATE TABLE session(x INTEGER)")
        c.execute("INSERT INTO session VALUES (1)")
        c.commit()
        c.close()

    qdir = tmp_path / "queries"
    qdir.mkdir()
    for qname, content in queries.items():
        (qdir / f"{qname}.sql").write_text(content, encoding="utf-8")

    monkeypatch.setattr(serve, "WAREHOUSE_DB", wh)
    monkeypatch.setattr(serve, "QUERIES_DIR", qdir)
    monkeypatch.setattr(serve, "clean_path", lambda s: clean_dir / f"{s}.db")
    return qdir


def _attached(conn) -> set[str]:
    """Schema names currently attached (excludes 'main' and 'temp')."""
    return {
        row[1]
        for row in conn.execute("PRAGMA database_list").fetchall()
        if row[1] not in ("main", "temp")
    }


# --------------------------------------------------------------------------- #
# parse_required_sources — the header-directive contract
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_parse_reads_single_directive():
    sql = "-- aidata-attach: state_db\nSELECT * FROM state_db.session;"
    assert serve.parse_required_sources(sql) == ["state_db"]


@pytest.mark.unit
def test_parse_ignores_source_name_in_plain_comment():
    """The rework-threads.sql regression: `state_db` appears only in a prose
    comment; the naive `\\b<src>\\.` regex would wrongly demand attaching it.
    The header-directive parser must NOT pick it up."""
    sql = (
        "-- aidata-attach: multica_comment\n"
        "-- exactly like daily-automation.sql reads state_db.session (ADR-13).\n"
        "SELECT * FROM multica_comment.comment;"
    )
    assert serve.parse_required_sources(sql) == ["multica_comment"]


@pytest.mark.unit
def test_parse_no_directive_yields_empty():
    assert serve.parse_required_sources("SELECT 1;") == []


@pytest.mark.unit
def test_parse_dedups_multiple_tokens():
    sql = "-- aidata-attach: state_db, state_db memory_claude\nSELECT 1;"
    assert serve.parse_required_sources(sql) == ["state_db", "memory_claude"]


# --------------------------------------------------------------------------- #
# Structural sweep over the real query files (no DB needed)
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_all_real_queries_declare_only_valid_l2_only_sources():
    """Every real .sql that declares attaches must (1) name only L2-only sources
    and (2) stay well under the 10-attach ceiling. This catches a typo'd or
    merged-source header without touching a DB."""
    sql_files = sorted(QUERIES_DIR.glob("**/*.sql"))
    assert sql_files, "no query files found"
    for path in sql_files:
        req = serve.parse_required_sources(path.read_text(encoding="utf-8"))
        assert len(req) <= 9, f"{path.name} declares {len(req)} attaches (limit 10)"
        for src in req:
            assert src in L2_ONLY, (
                f"{path.name} declares {src!r}, not an L2-only source"
            )


@pytest.mark.unit
def test_rework_threads_declares_multica_comment_not_state_db():
    """End-to-end guard on the false-positive file: it must declare exactly
    multica_comment even though `state_db` is named in its comments."""
    path = QUERIES_DIR / "health" / "rework-threads.sql"
    assert serve.parse_required_sources(path.read_text(encoding="utf-8")) == [
        "multica_comment"
    ]


# --------------------------------------------------------------------------- #
# (b) a state_db query attaches exactly state_db
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_real_state_db_query_declares_exactly_state_db():
    path = QUERIES_DIR / "trend" / "daily-automation.sql"
    assert serve.parse_required_sources(path.read_text(encoding="utf-8")) == [
        "state_db"
    ]


@pytest.mark.unit
def test_connect_attaches_exactly_declared_state_db(tmp_path, monkeypatch):
    _make_env(tmp_path, monkeypatch, clean_dbs=["state_db"], queries={})
    conn = serve._connect(["state_db"])
    try:
        assert _attached(conn) == {"state_db"}
    finally:
        conn.close()


# --------------------------------------------------------------------------- #
# (c) a query with no L2-only source attaches nothing
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_connect_with_no_sources_attaches_nothing(tmp_path, monkeypatch):
    _make_env(tmp_path, monkeypatch, clean_dbs=list(L2_ONLY), queries={})
    conn = serve._connect([])
    try:
        assert _attached(conn) == set()
    finally:
        conn.close()


@pytest.mark.unit
def test_run_query_without_directive_attaches_no_l2_only(tmp_path, monkeypatch):
    _make_env(
        tmp_path,
        monkeypatch,
        clean_dbs=list(L2_ONLY),
        queries={"probe": "SELECT count(*) AS n FROM fact_probe;"},
    )
    rows, cols = serve.run_query("probe")
    assert rows == [(1,)] and cols == ["n"]


# --------------------------------------------------------------------------- #
# (d) every L2-only clean DB on disk → still nowhere near the 10-attach limit
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_all_l2_dbs_present_query_attaches_only_declared(tmp_path, monkeypatch):
    """The bomb the fix defuses: with EVERY L2-only clean DB present on disk,
    the OLD serve.py would ATTACH them all and raise 'too many attached
    databases' (SQLite's compiled limit is 10). On-demand ATTACH pulls in only
    what the query declares.

    Not pinned to a count — the point is "all of them, however many that is",
    and the pressure only grows as sources are added (12 as of hermes_messages).
    A hardcoded number would fail on every new source while testing nothing.
    """
    assert len(L2_ONLY) > 10, (
        f"only {len(L2_ONLY)} L2-only sources — fewer than SQLite's 10-attach "
        "limit, so this test no longer exercises the failure it guards"
    )
    q = "-- aidata-attach: state_db\nSELECT count(*) AS n FROM state_db.session;"
    _make_env(
        tmp_path,
        monkeypatch,
        clean_dbs=list(L2_ONLY),  # all 11 exist on disk
        queries={"needs_state": q},
    )
    rows, cols = serve.run_query("needs_state")
    assert cols == ["n"] and rows == [(1,)]


@pytest.mark.unit
def test_connect_stays_under_limit_with_many_declared(tmp_path, monkeypatch):
    """Even declaring several sources at once stays under SQLite's 10 ceiling
    and reports exactly the requested attaches."""
    declared = list(L2_ONLY[:9])
    _make_env(tmp_path, monkeypatch, clean_dbs=list(L2_ONLY), queries={})
    conn = serve._connect(declared)
    try:
        assert _attached(conn) == set(declared)
    finally:
        conn.close()


# --------------------------------------------------------------------------- #
# Guards: validation + path containment
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_connect_rejects_unknown_source(tmp_path, monkeypatch):
    _make_env(tmp_path, monkeypatch, clean_dbs=[], queries={})
    with pytest.raises(ValueError):
        serve._connect(["not_a_source"])


@pytest.mark.unit
def test_connect_rejects_merged_source(tmp_path, monkeypatch):
    _make_env(tmp_path, monkeypatch, clean_dbs=[], queries={})
    merged = MERGE_SOURCES[0]
    with pytest.raises(ValueError):
        serve._connect([merged])


@pytest.mark.unit
def test_run_query_rejects_path_escape():
    with pytest.raises(ValueError):
        serve.run_query("../../etc/passwd")


@pytest.mark.unit
def test_missing_clean_db_is_not_fatal_at_connect(tmp_path, monkeypatch):
    """Degrade-safe: declaring a source whose clean DB is absent must not raise
    at connect time (the query itself surfaces 'no such table' only if needed)."""
    _make_env(tmp_path, monkeypatch, clean_dbs=[], queries={})
    conn = serve._connect(["state_db"])
    try:
        assert _attached(conn) == set()  # nothing attached, but no error
    finally:
        conn.close()


# --------------------------------------------------------------------------- #
# (a) THE backstop: every real query runs against the live warehouse
# --------------------------------------------------------------------------- #
@pytest.mark.integration
@pytest.mark.skipif(
    not (Path(__file__).resolve().parent.parent / "L3_merge" / "warehouse.db").exists(),
    reason="warehouse.db not built (gitignored local artifact) — run `cli.py merge`",
)
def test_all_queries_run_against_live_warehouse():
    """Every query on disk executes — the backstop for ATTACH/schema changes.

    Deliberately NOT pinned to a count. A hardcoded number tests nothing about
    correctness (adding a query is normal) while breaking on every addition, so
    it trains people to bump the constant without reading the failure. What
    matters is that ALL of them run, whatever "all" currently means.
    """
    names = serve.list_queries()
    assert names, "no queries discovered — is QUERIES_DIR wired correctly?"
    failures = []
    for name in names:
        try:
            serve.run_query(name)
        except Exception as exc:  # noqa: BLE001 — collect all, report together
            failures.append(f"{name}: {exc!r}")
    assert not failures, "queries failed:\n" + "\n".join(failures)
