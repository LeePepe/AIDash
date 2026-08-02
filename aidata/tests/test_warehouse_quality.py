"""Warehouse data-quality gates — the six quality dimensions (audit Phase 4).

The audit found `test_warehouse_integrity.py` covered only 3 assertions, all on
one table. This module adds the missing dimensions:

  completeness · accuracy · consistency · timeliness · validity · uniqueness

Two of these encode *honest* facts rather than aspirations. `fact_task.pr_url`
resolves to `fact_pr` on 0.03% of rows and `fact_task.session_id` on 13% — the
tests below LOCK those in as known-weak so nobody writes an analysis that
assumes they join cleanly, and so a future fix shows up as a test that starts
over-performing (which the test tells you to come update).

All tests here are integration: they read the locally built warehouse and skip
when it is absent (fresh clone / CI), matching test_warehouse_integrity.py.
"""

import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
WAREHOUSE = ROOT / "L3_merge" / "warehouse.db"

pytestmark = pytest.mark.skipif(
    not WAREHOUSE.exists(),
    reason="warehouse.db not built (gitignored local artifact) — run `cli.py merge`",
)


def _q(sql: str) -> str:
    return subprocess.run(
        ["sqlite3", str(WAREHOUSE), sql],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def _count(sql: str) -> int:
    return int(_q(sql) or 0)


# ---------------------------------------------------------------------------
# Validity — every categorical column stays inside its documented domain.
#
# The domains below were read off the live warehouse, not invented. A new value
# appearing upstream (a new multica run status, say) should FAIL loudly here:
# that is the signal to decide whether L4 queries filtering on these values
# need updating — several use equality filters (status='completed') that would
# silently under-count if a synonym appeared.
# ---------------------------------------------------------------------------
VALUE_DOMAINS = [
    ("fact_task", "status",
     {"completed", "cancelled", "failed", "queued", "running", "blocked", "done"}),
    ("fact_task", "source", {"multica_run", "claude_job"}),
    ("fact_issue", "status",
     {"done", "cancelled", "todo", "in_review", "in_progress", "blocked", "backlog"}),
    ("fact_ado_pr", "status", {"completed", "abandoned", "active"}),
    ("fact_github_pr", "state", {"MERGED", "CLOSED", "OPEN"}),
    ("fact_request", "status", {"success", "error"}),
]


@pytest.mark.integration
@pytest.mark.parametrize("table,column,allowed", VALUE_DOMAINS)
def test_categorical_values_are_in_domain(table: str, column: str, allowed: set):
    raw = _q(f"SELECT DISTINCT {column} FROM {table} WHERE {column} IS NOT NULL;")
    seen = {v for v in raw.splitlines() if v}
    unexpected = seen - allowed
    assert not unexpected, (
        f"{table}.{column} has undocumented values {sorted(unexpected)}. "
        f"If upstream added a status, update this domain AND check every L4 "
        f"query filtering on {column} — equality filters silently under-count."
    )


# ---------------------------------------------------------------------------
# Uniqueness — the grain each fact table claims is actually one row.
# ---------------------------------------------------------------------------
GRAIN_KEYS = [
    ("fact_request", "request_id"),
    ("fact_turn", "turn_uuid"),
    ("fact_task", "task_id"),
    ("fact_issue", "issue_id"),
    ("fact_pr", "pr_url"),
    ("fact_ado_pr", "pr_id"),
    ("fact_repo_snapshot", "repo, snapshot_date"),
    ("fact_github_pr", "repo, pr_number"),
]


@pytest.mark.integration
@pytest.mark.parametrize("table,key", GRAIN_KEYS)
def test_grain_is_unique(table: str, key: str):
    """One row per claimed grain — merge is idempotent, so re-runs must not dup."""
    dups = _count(
        f"SELECT count(*) FROM (SELECT {key} FROM {table} "
        f"GROUP BY {key} HAVING count(*) > 1);"
    )
    assert dups == 0, f"{table} has {dups} duplicate {key} groups"


# ---------------------------------------------------------------------------
# Completeness — required fields are populated.
# ---------------------------------------------------------------------------
@pytest.mark.integration
def test_facts_are_non_empty():
    """A silently empty fact table means a broken collect, not 'a quiet day'."""
    for table in ("fact_request", "fact_turn", "fact_task", "fact_issue"):
        assert _count(f"SELECT count(*) FROM {table};") > 0, f"{table} is empty"


@pytest.mark.integration
def test_every_fact_row_has_a_cst_day():
    """The CST day drives every trend. A NULL there drops the row off the chart.

    Scoped to rows whose source timestamp is present — a NULL ts_start legitimately
    yields a NULL cst_day (claude_job rows predating the field), and that is not a
    defect. What would be a defect is a populated timestamp producing no day.
    """
    checks = [
        ("fact_request", "ts IS NOT NULL"),
        ("fact_turn", "ts IS NOT NULL"),
        ("fact_task", "ts_start IS NOT NULL"),
        ("fact_issue", "updated_at IS NOT NULL"),
    ]
    for table, present in checks:
        n = _count(
            f"SELECT count(*) FROM {table} WHERE {present} AND cst_day IS NULL;"
        )
        assert n == 0, f"{table}: {n} rows have a timestamp but no cst_day"


# ---------------------------------------------------------------------------
# Timeliness — the warehouse reflects recent reality.
# ---------------------------------------------------------------------------
@pytest.mark.integration
def test_warehouse_is_fresh():
    """The high-volume facts carry data from the last few days.

    Deliberately loose (7 days): this is a local dev machine that may sit idle
    over a weekend, and the point is to catch a *broken pipeline*, not to police
    working habits. The 04:00 cron chain silently failing is the real failure
    mode this guards (it has happened before — see the digest push chain doc).
    """
    for table in ("fact_request", "fact_turn"):
        stale_days = float(_q(
            f"SELECT julianday('now','+8 hours') - julianday(max(cst_day)) "
            f"FROM {table};"
        ))
        assert stale_days < 7, (
            f"{table} newest row is {stale_days:.1f} days old — "
            f"collect/normalize/merge chain may be broken"
        )


# ---------------------------------------------------------------------------
# Accuracy — derived values agree with their SSOT.
# ---------------------------------------------------------------------------
@pytest.mark.integration
def test_cost_is_never_negative():
    """Cost comes from adapters/raven.py::_cost() (L2). Negative = pricing bug."""
    n = _count("SELECT count(*) FROM fact_request WHERE cost_usd < 0;")
    assert n == 0, f"{n} rows have negative cost"


@pytest.mark.integration
def test_dim_session_rollup_matches_facts():
    """dim_session is a rollup OF fact_request — it must not drift from it.

    Guards the merge step: if the GROUP BY ever changes shape, or fact_request
    is reloaded without rebuilding dim_session, this catches the divergence.
    """
    mismatched = _count("""
        SELECT count(*) FROM (
          SELECT s.session_id
          FROM dim_session s
          JOIN (SELECT session_uuid, count(*) AS n
                FROM fact_request WHERE session_uuid IS NOT NULL
                GROUP BY session_uuid) f
            ON f.session_uuid = s.session_id
          WHERE s.request_count != f.n
        );
    """)
    assert mismatched == 0, f"{mismatched} dim_session rows disagree with fact_request"


# ---------------------------------------------------------------------------
# Consistency — cross-table bridges, INCLUDING the honestly broken ones.
# ---------------------------------------------------------------------------
@pytest.mark.integration
def test_strong_bridges_resolve():
    """The two bridges the warehouse actually relies on must stay near-total."""
    turn_pct = float(_q(
        "SELECT round(100.0 * sum(session_id IN "
        "(SELECT session_uuid FROM fact_request)) / count(*), 2) FROM fact_turn;"
    ))
    assert turn_pct > 99, f"fact_turn -> fact_request fell to {turn_pct}%"

    task_pct = float(_q(
        "SELECT round(100.0 * sum(issue_id IS NULL OR issue_id IN "
        "(SELECT issue_id FROM fact_issue)) / count(*), 2) FROM fact_task;"
    ))
    assert task_pct > 99, f"fact_task -> fact_issue fell to {task_pct}%"


@pytest.mark.integration
def test_weak_bridges_are_documented_as_weak():
    """Lock in the KNOWN-BROKEN bridges so no analysis assumes they join.

    These are honest keys, not bugs to fix silently:
      - fact_task.pr_url -> fact_pr: ~0.03% (fact_pr has 6 rows; pr_cache's
        source, ~/.claude/gh-pr-status-cache.json, covers almost nothing)
      - fact_task.session_id -> fact_request: ~13% (only runs the runtime
        routed as claude-cli carry a resolvable session)

    If either RISES materially, that is good news — but come update this test
    and the schema comments rather than letting the docs drift.
    """
    pr_pct = float(_q(
        "SELECT round(100.0 * sum(pr_url IN "
        "(SELECT pr_url FROM fact_pr)) / count(*), 2) FROM fact_task;"
    ))
    assert pr_pct < 5, (
        f"fact_task -> fact_pr now resolves {pr_pct}% (was ~0.03%). "
        "If pr_cache coverage improved, update this test + the schema comment."
    )

    sess_pct = float(_q(
        "SELECT round(100.0 * sum(session_id IN "
        "(SELECT session_uuid FROM fact_request)) / count(*), 2) FROM fact_task;"
    ))
    assert sess_pct < 40, (
        f"fact_task -> fact_request now resolves {sess_pct}% (was ~13%). "
        "If routing changed, update this test + the schema comment."
    )
