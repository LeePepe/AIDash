"""L4 query tiers — production contract vs exploratory (audit Phase 3).

The audit found L4 mixing two populations with very different lifetimes:

  24 queries feed the daily digest through L5 — changing their shape breaks a
     card, so they are a CONTRACT.
  15 queries have no L5 consumer at all — they exist for ad-hoc investigation
     via `cli.py query <name>`, and nothing downstream depends on their columns.

Nothing marked the difference, so both looked equally load-bearing. An agent
refactoring the warehouse could not tell which queries it was free to change,
and the 15 exploratory ones added noise to every "what does L4 guarantee?"
question.

Rather than MOVE the exploratory files (their paths are published in README
usage examples and cli.py's `--help`, and `cli.py query issues/trend` is
documented — moving them breaks every one of those), each declares its tier
in a header line, mirroring the existing `-- aidata-attach:` convention:

    -- aidata-tier: explore

Absence of the marker means production. These tests keep the two populations
honest: every query declares a valid tier, the production set is exactly what
L5 actually imports, and no exploratory query is silently wired into L5.

Hermetic — reads only the repo's .sql and .py files, never the warehouse.
"""

import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUERIES = ROOT / "L4_serve" / "queries"
DIGEST = ROOT / "L5_apps" / "digest"
QUERY = QUERIES / "attribution" / "cost-by-project.sql"

TIER_DIRECTIVE = re.compile(r"^\s*--\s*aidata-tier:\s*(\S+)\s*$", re.MULTILINE)
VALID_TIERS = {"explore"}

# Every query name L5 references as a string literal. This is how the digest
# actually addresses queries (serve.run_query("trend/daily-cost")), so it is the
# real consumer set — not a hand-maintained list that would drift.
# Query names L5 references as string literals. The directory prefixes are
# derived from disk rather than hardcoded: a hand-written alternation silently
# stops matching when a new query directory appears (`attribution/` did exactly
# that), and the failure looks like "production query has no consumer" — a
# misleading symptom pointing at the wrong file.
def _query_ref_pattern() -> re.Pattern[str]:
    prefixes = sorted({p.name for p in QUERIES.iterdir() if p.is_dir()})
    assert prefixes, "no query directories found — is QUERIES_DIR wired?"
    return re.compile(r'"((?:' + "|".join(map(re.escape, prefixes))
                      + r')/[a-z0-9-]+)"')


QUERY_REF = _query_ref_pattern()


def _all_queries() -> set[str]:
    return {
        str(p.relative_to(QUERIES).with_suffix("")) for p in QUERIES.glob("**/*.sql")
    }


def _tier_of(name: str) -> str:
    sql = (QUERIES / f"{name}.sql").read_text(encoding="utf-8")
    match = TIER_DIRECTIVE.search(sql)
    return match.group(1) if match else "production"


def _l5_referenced() -> set[str]:
    names: set[str] = set()
    for path in DIGEST.glob("*.py"):
        names |= set(QUERY_REF.findall(path.read_text(encoding="utf-8")))
    return names


def test_every_query_declares_a_valid_tier():
    """A typo'd marker would silently read as production — catch it."""
    bad = {
        name: _tier_of(name)
        for name in _all_queries()
        if _tier_of(name) not in VALID_TIERS | {"production"}
    }
    assert not bad, f"queries with an unrecognized aidata-tier: {bad}"


def test_production_tier_is_exactly_what_l5_consumes():
    """The contract set must match reality in BOTH directions.

    A production query with no consumer is an orphan that should be marked
    explore; an explore query that L5 imports is a contract in disguise, and
    changing its columns would break a card without warning.
    """
    production = {n for n in _all_queries() if _tier_of(n) == "production"}
    referenced = _l5_referenced()

    unconsumed = production - referenced
    assert not unconsumed, (
        f"production queries with no L5 consumer: {sorted(unconsumed)} — "
        "either wire them into the digest or mark `-- aidata-tier: explore`"
    )

    # Only flag names that actually exist; a stale string in L5 is a different
    # bug, covered by test_l5_references_resolve below.
    misfiled = (referenced & _all_queries()) - production
    assert not misfiled, (
        f"explore queries consumed by L5: {sorted(misfiled)} — "
        "they are a contract; remove their explore marker"
    )


def test_l5_references_resolve():
    """Every query name L5 mentions exists on disk (guards renames)."""
    missing = _l5_referenced() - _all_queries()
    assert not missing, f"L5 references non-existent queries: {sorted(missing)}"


def test_explore_tier_is_documented():
    """The convention must be discoverable, or the markers rot into noise."""
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "aidata-tier" in readme, "README does not explain the aidata-tier marker"


def _cost_by_project_warehouse(tmp_path: Path, requests, turns) -> Path:
    db = tmp_path / "warehouse.db"
    con = sqlite3.connect(db)
    con.execute(
        "CREATE TABLE fact_request (session_uuid TEXT, cst_day TEXT, "
        "cost_usd REAL, total_tokens INTEGER)"
    )
    con.execute(
        "CREATE TABLE fact_turn (session_id TEXT, project TEXT, cst_day TEXT)"
    )
    con.executemany(
        "INSERT INTO fact_request VALUES (?, ?, ?, ?)", requests
    )
    con.executemany(
        "INSERT INTO fact_turn VALUES (?, ?, ?)", turns
    )
    con.commit()
    con.close()
    return db


def _run_cost_by_project(db: Path, day="2026-08-02"):
    con = sqlite3.connect(db)
    try:
        cur = con.execute(QUERY.read_text(encoding="utf-8"), {"day": day})
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description]
        return rows, {c: i for i, c in enumerate(cols)}
    finally:
        con.close()


def test_cost_by_project_tracks_day_total_and_unattributed_share(tmp_path):
    db = _cost_by_project_warehouse(
        tmp_path,
        [
            ("s1", "2026-08-02", 100.0, 600),
            ("s2", "2026-08-02", 200.0, 400),
        ],
        [
            ("s1", "AIDash", "2026-08-02"),
            ("s1", " Atlas ", "2026-08-02"),
            ("s2", "   ", "2026-08-02"),
        ],
    )
    rows, idx = _run_cost_by_project(db)
    by_project = {r[idx["project"]]: r for r in rows}
    assert {"AIDash", "Atlas", "unattributed"} <= set(by_project)
    assert by_project["unattributed"][idx["cost_usd"]] == 200.0
    assert by_project["unattributed"][idx["day_total"]] == 300.0
    assert by_project["unattributed"][idx["attributed_total"]] == 100.0
    assert by_project["unattributed"][idx["sessions"]] == 1
    assert by_project["AIDash"][idx["cost_pct"]] == 16.7
    assert by_project["Atlas"][idx["cost_pct"]] == 16.7


def test_cost_by_project_counts_residual_sessions_at_session_grain(tmp_path):
    db = _cost_by_project_warehouse(
        tmp_path,
        [
            ("s1", "2026-08-02", 100.0, 500),
            ("s2", "2026-08-02", 200.0, 800),
            ("s3", "2026-08-02", 50.0, 200),
        ],
        [
            ("s1", "AIDash", "2026-08-02"),
            ("s1", "Atlas", "2026-08-02"),
            ("s2", "  ", "2026-08-02"),
            ("s3", "AIDash", "2026-08-02"),
        ],
    )
    rows, idx = _run_cost_by_project(db)
    by_project = {r[idx["project"]]: r for r in rows}
    assert by_project["unattributed"][idx["cost_usd"]] == 200.0
    assert by_project["unattributed"][idx["sessions"]] == 1
    assert by_project["AIDash"][idx["cost_usd"]] == 100.0
    assert by_project["Atlas"][idx["cost_usd"]] == 50.0


def test_cost_by_project_keeps_null_turns_unattributed_in_mixed_sessions(tmp_path):
    db = _cost_by_project_warehouse(
        tmp_path,
        [
            ("s1", "2026-08-02", 100.0, 500),
            ("s2", "2026-08-02", 50.0, 200),
        ],
        [
            ("s1", "Atlas", "2026-08-02"),
            ("s1", "   ", "2026-08-02"),
            ("s2", None, "2026-08-02"),
        ],
    )
    rows, idx = _run_cost_by_project(db)
    by_project = {r[idx["project"]]: r for r in rows}
    assert by_project["Atlas"][idx["cost_usd"]] == 50.0
    assert by_project["unattributed"][idx["cost_usd"]] == 100.0
    assert by_project["unattributed"][idx["day_total"]] == 150.0
    assert by_project["unattributed"][idx["attributed_total"]] == 50.0
    assert by_project["unattributed"][idx["bucket"]] == "residual"


def test_cost_by_project_preserves_zero_valid_attribution(tmp_path):
    db = _cost_by_project_warehouse(
        tmp_path,
        [
            ("s1", "2026-08-02", 30.0, 120),
            ("s2", "2026-08-02", 20.0, 80),
        ],
        [
            ("s1", "   ", "2026-08-02"),
            ("s2", None, "2026-08-02"),
        ],
    )
    rows, idx = _run_cost_by_project(db)
    assert len(rows) == 1
    assert rows[0][idx["project"]] == "unattributed"
    assert rows[0][idx["day_total"]] == 50.0
    assert rows[0][idx["attributed_total"]] == 0.0
    assert rows[0][idx["cost_pct"]] == 100.0
    assert rows[0][idx["bucket"]] == "residual"


def test_cost_by_project_normalizes_blank_project_labels(tmp_path):
    db = _cost_by_project_warehouse(
        tmp_path,
        [("s1", "2026-08-02", 90.0, 300)],
        [("s1", "   AIDash   ", "2026-08-02")],
    )
    rows, idx = _run_cost_by_project(db)
    assert rows[0][idx["project"]] == "AIDash"
    assert rows[0][idx["cost_usd"]] == 90.0
    assert rows[0][idx["bucket"]] == "project"
