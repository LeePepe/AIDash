"""Warehouse-level CST day-bucketing contract (Phase 1 of the warehouse audit).

Every fact table that carries a timestamp exposes a STORED generated column
`cst_day` holding the CST (Asia/Shanghai) calendar day. This is the SINGLE
definition of "which day did this happen on" — L4 queries read `cst_day`
instead of each re-deriving `date(..., '+8 hours')` (which had drifted into 39
occurrences across 18 files, in 5 physically different timestamp formats).

Two disciplines are asserted here:
  1. **Existence** — the column is present on every timestamped fact.
  2. **Equivalence** — it equals the legacy expression exactly, so the
     refactor is provably row-identical (ADR-22: explicit +8h, never
     `localtime`, which is host-timezone dependent).

These are integration tests: they read the locally built warehouse and skip
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

# (table, cst_day column, the legacy expression it must equal).
# The legacy expressions differ per table because the underlying timestamps are
# physically different: epoch-ms integers, ISO-Z text, and ISO-with-offset text.
# That heterogeneity is exactly why a single shared column is worth having.
CST_FACTS = [
    ("fact_request", "cst_day", "date(ts/1000,'unixepoch','+8 hours')"),
    ("fact_turn", "cst_day", "date(ts,'+8 hours')"),
    ("fact_task", "cst_day", "date(ts_start,'+8 hours')"),
    ("fact_issue", "cst_day", "date(updated_at,'+8 hours')"),
    ("fact_ado_pr", "cst_day", "date(created_date,'+8 hours')"),
    ("fact_ado_pr", "cst_closed_day", "date(closed_date,'+8 hours')"),
    ("fact_github_pr", "cst_day", "date(created_date,'+8 hours')"),
    ("fact_github_pr", "cst_merged_day", "date(merged_date,'+8 hours')"),
]


def _q(sql: str) -> str:
    out = subprocess.run(
        ["sqlite3", str(WAREHOUSE), sql],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return out


@pytest.mark.integration
@pytest.mark.parametrize("table,column,_expr", CST_FACTS)
def test_cst_column_exists(table: str, column: str, _expr: str):
    """Every timestamped fact exposes its CST day as a real column.

    Uses `table_xinfo`, not `table_info` — the latter deliberately HIDES
    generated columns, so it would report these as missing even though they
    exist and are queryable.
    """
    cols = _q(f"PRAGMA table_xinfo({table});")
    assert column in cols, f"{table} is missing the {column} generated column"


@pytest.mark.integration
@pytest.mark.parametrize("table,column,expr", CST_FACTS)
def test_cst_column_matches_legacy_expression(table: str, column: str, expr: str):
    """The column equals the legacy inline expression on every row.

    This is the refactor's safety net: if it holds, rewriting a query from the
    inline expression to the column cannot change a single row. NULL timestamps
    yield NULL on both sides — `IS NOT` treats those as equal (unlike `!=`).
    """
    n = int(_q(
        f"SELECT count(*) FROM {table} WHERE {column} IS NOT ({expr});"
    ))
    assert n == 0, f"{table}.{column} diverges from {expr} on {n} rows"


@pytest.mark.integration
def test_cst_day_is_indexed():
    """Day-bucketed aggregation is the hottest access path — it must be indexed.

    Without an index, `GROUP BY cst_day` degrades to a full scan plus a temp
    B-tree, which is what the audit measured on fact_request (708k rows).
    """
    idx = _q(
        "SELECT group_concat(name) FROM sqlite_master "
        "WHERE type='index' AND tbl_name='fact_request';"
    )
    assert "idx_req_cst_day" in idx, "fact_request.cst_day is not indexed"


@pytest.mark.integration
def test_no_localtime_in_queries():
    """ADR-22: day bucketing uses explicit +8h, never `localtime`.

    `localtime` depends on the host timezone, so it breaks reproducibility and
    makes the 04:00 cron run differ from a manual run on another machine.
    """
    queries = ROOT / "L4_serve" / "queries"
    offenders = [
        str(p.relative_to(queries))
        for p in queries.glob("**/*.sql")
        # Only flag real SQL usage, not the prose in a comment warning against it.
        if any(
            "localtime" in line and not line.lstrip().startswith("--")
            for line in p.read_text(encoding="utf-8").splitlines()
        )
    ]
    assert not offenders, f"queries using localtime: {offenders}"
