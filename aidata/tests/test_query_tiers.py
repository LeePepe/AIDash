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
                      + r')/[a-z0-9_-]+)"')


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
    bad = {}
    for name in _all_queries():
        sql = (QUERIES / f"{name}.sql").read_text(encoding="utf-8")
        match = TIER_DIRECTIVE.search(sql)
        if match and match.group(1) not in VALID_TIERS:
            bad[name] = match.group(1)
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
            (None, "2026-08-02", 25.0, 100),
        ],
        [
            ("s1", "AIDash", "2026-08-02"),
            ("s1", "Atlas", "2026-08-02"),
            ("s2", "  ", "2026-08-02"),
            ("s3", "AIDash", "2026-08-02"),
            ("s3", "Atlas", "2026-08-02"),
            ("s3", "Core", "2026-08-02"),
            ("s3", "Pilot", "2026-08-02"),
            ("s3", "Northstar", "2026-08-02"),
            ("s3", "Nexus", "2026-08-02"),
            ("s3", "Harbor", "2026-08-02"),
            ("s3", "Summit", "2026-08-02"),
            ("s3", "Beacon", "2026-08-02"),
            ("s3", "Vector", "2026-08-02"),
            ("s3", "Orbit", "2026-08-02"),
        ],
    )
    rows, idx = _run_cost_by_project(db)
    by_project = {r[idx["project"]]: r for r in rows}
    assert by_project["unattributed"][idx["cost_usd"]] == 225.0
    assert by_project["unattributed"][idx["sessions"]] == 1
    assert by_project["AIDash"][idx["cost_usd"]] == 54.55
    assert by_project["Atlas"][idx["cost_usd"]] == 54.55
    assert by_project["Core"][idx["cost_usd"]] == 4.55


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


def test_cost_by_project_scopes_residual_session_detection_to_the_day(tmp_path):
    db = _cost_by_project_warehouse(
        tmp_path,
        [
            ("s1", "2026-08-02", 100.0, 400),
            ("s2", "2026-08-02", 80.0, 300),
            ("s3", "2026-08-02", 50.0, 200),
        ],
        [
            ("s1", "Alpha", "2026-08-02"),
            ("s1", "Beta", "2026-08-02"),
            ("s1", "   ", "2026-08-03"),
            ("s2", "   ", "2026-08-02"),
            ("s3", "Gamma", "2026-08-02"),
        ],
    )
    rows, idx = _run_cost_by_project(db)
    by_project = {r[idx["project"]]: r for r in rows}
    assert by_project["unattributed"][idx["cost_usd"]] == 80.0
    assert by_project["unattributed"][idx["sessions"]] == 1
    assert by_project["Alpha"][idx["cost_usd"]] == 50.0
    assert by_project["Beta"][idx["cost_usd"]] == 50.0
    assert by_project["Gamma"][idx["cost_usd"]] == 50.0


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


def test_app_crash_and_perf_aggregates_7d_crash_and_p95_regression(tmp_path):
    db = tmp_path / "warehouse.db"
    sql_path = QUERIES / "retro" / "app_crash_and_perf.sql"
    con = sqlite3.connect(db)
    try:
        con.execute(
            """
            CREATE TABLE fact_product_telemetry (
                event_id TEXT PRIMARY KEY,
                app_name TEXT NOT NULL,
                app_version TEXT,
                build_number TEXT,
                platform TEXT,
                event_kind TEXT NOT NULL,
                signature TEXT,
                stack_top_symbol TEXT,
                metric_ms REAL,
                occurred_at TEXT NOT NULL,
                cst_day TEXT GENERATED ALWAYS AS (date(occurred_at, '+8 hours')) STORED
            )
            """
        )
        events = [
            # Prior 7d baseline for AIDash perf (20 samples: 19 at 100ms, 1 outlier at 500ms -> P95 is 19th = 100ms)
            *(
                (f"e-prev-perf-{i}", "AIDash", "2.0", "100", "macos", "perf", "aidash.ready_scene", "BriefingView.body", 100.0, "2026-11-01T02:00:00Z")
                for i in range(19)
            ),
            ("e-prev-perf-outlier", "AIDash", "2.0", "100", "macos", "perf", "aidash.ready_scene", "BriefingView.body", 500.0, "2026-11-01T02:05:00Z"),
            ("e-prev-crash", "VoxPocket", "1.3", "40", "macos", "crash", "OLD_SIG", "OldSymbol.run", None, "2026-11-01T03:00:00Z"),
            # Current 7d: AIDash has >20% P95 regression (20 samples: 19 at 150ms, 1 outlier at 900ms -> P95 is 19th = 150ms vs 100ms = +50%)
            *(
                (f"e-cur-perf-{i}", "AIDash", "2.1", "108", "macos", "perf", "aidash.ready_scene", "BriefingView.body", 150.0, "2026-11-09T02:00:00Z")
                for i in range(19)
            ),
            ("e-cur-perf-outlier", "AIDash", "2.1", "108", "macos", "perf", "aidash.ready_scene", "BriefingView.body", 900.0, "2026-11-10T02:00:00Z"),
            # Current 7d: VitalStride has a brand new crash signature; its 20 perf samples have 19 at 200ms and 1 outlier at 1000ms (P95 = 200ms, no regression)
            ("e-cur-crash-1", "VitalStride", "1.1", "12", "ios", "crash", "EXC_BAD_ACCESS:HealthSync", "HealthSyncService.fetch()", None, "2026-11-10T04:00:00Z"),
            *(
                (f"e-prev-vs-{i}", "VitalStride", "1.0", "10", "ios", "perf", "vitalstride.launch", "AppDelegate.didFinish", 200.0, "2026-11-01T04:05:00Z")
                for i in range(20)
            ),
            *(
                (f"e-cur-perf-vs-{i}", "VitalStride", "1.1", "12", "ios", "perf", "vitalstride.launch", "AppDelegate.didFinish", 200.0, "2026-11-10T04:05:00Z")
                for i in range(19)
            ),
            ("e-cur-perf-vs-outlier", "VitalStride", "1.1", "12", "ios", "perf", "vitalstride.launch", "AppDelegate.didFinish", 1000.0, "2026-11-10T04:06:00Z"),
        ]
        con.executemany(
            "INSERT INTO fact_product_telemetry "
            "(event_id, app_name, app_version, build_number, platform, event_kind, "
            "signature, stack_top_symbol, metric_ms, occurred_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            events,
        )
        con.commit()
        cur = con.execute(sql_path.read_text(encoding="utf-8"))
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description]
        by_app = {r[cols.index("app_name")]: dict(zip(cols, r)) for r in rows}
    finally:
        con.close()

    assert set(by_app) == {"AIDash", "VitalStride"}
    vs = by_app["VitalStride"]
    assert vs["crash_count_7d"] == 1
    assert vs["new_crash_signature_count"] == 1
    assert vs["crash_free_rate_7d"] == round(1.0 - 1.0 / 21.0, 4)
    assert vs["signature"] == "EXC_BAD_ACCESS:HealthSync"
    assert vs["stack_top_symbol"] == "HealthSyncService.fetch()"
    assert vs["p95_metric_ms_7d"] == 200.0
    assert vs["p95_metric_ms_prev_7d"] == 200.0
    assert vs["is_perf_regressed"] == 0

    ad = by_app["AIDash"]
    assert ad["crash_count_7d"] == 0
    assert ad["new_crash_signature_count"] == 0
    assert ad["crash_free_rate_7d"] == 1.0
    assert ad["p95_metric_ms_7d"] == 150.0
    assert ad["p95_metric_ms_prev_7d"] == 100.0
    assert ad["p95_regression_pct"] == 50.0
    assert ad["is_perf_regressed"] == 1

