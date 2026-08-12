"""L4 rework-relationship query + its degrade-safe L5 bundle.

The relationship card is the first card in this pipeline whose value depends on
a cross-tabulation being *arithmetically sound*: a workspace × root-cause matrix
that counts one issue's tokens under two root causes inflates every cell and
still renders as a convincing heatmap. So the double-count guard is asserted
against the real .sql running on a throwaway warehouse, not mocked away.

Everything here is hermetic: the query runs against a temp SQLite file built in
the test, and the fetcher's failure paths are exercised with fakes.
"""

import sqlite3
from pathlib import Path

import pytest

from L5_apps.digest import sources as s

ROOT = Path(__file__).resolve().parent.parent
QUERY = ROOT / "L4_serve" / "queries" / "attribution" / "rework-relationship.sql"

WS_A = "11111111-1111-1111-1111-111111111111"
WS_B = "22222222-2222-2222-2222-222222222222"


def _warehouse(tmp_path: Path, issues, tasks) -> Path:
    """Build a throwaway warehouse holding only what this query reads."""
    db = tmp_path / "warehouse.db"
    con = sqlite3.connect(db)
    con.execute(
        "CREATE TABLE fact_issue (issue_id TEXT PRIMARY KEY, workspace_id TEXT)")
    con.execute(
        "CREATE TABLE fact_task (task_id TEXT PRIMARY KEY, source TEXT, "
        "issue_id TEXT, ts_start TEXT, status TEXT, tokens INTEGER, error TEXT)")
    con.executemany("INSERT INTO fact_issue VALUES (?, ?)", issues)
    con.executemany("INSERT INTO fact_task VALUES (?, ?, ?, ?, ?, ?, ?)", tasks)
    con.commit()
    con.close()
    return db


def _run(db: Path, since=None):
    con = sqlite3.connect(db)
    try:
        cur = con.execute(QUERY.read_text(encoding="utf-8"), {"since": since})
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description]
        return rows, {c: i for i, c in enumerate(cols)}
    finally:
        con.close()


def _task(task_id, issue_id, day, status, tokens, error=None):
    return (task_id, "multica_run", issue_id, f"{day}T02:00:00Z", status,
            tokens, error)


# A 2×2-capable fixture: two workspaces, two root causes, one issue each.
# Every issue has BOTH a cancelled and a completed run, which is the rework
# definition shared with health/rework-rate and attribution/rework-by-workspace.
_ISSUES = [("i1", WS_A), ("i2", WS_A), ("i3", WS_B), ("i4", WS_B)]
_TASKS = [
    _task("t1a", "i1", "2026-08-10", "cancelled", 1000, "runtime went offline"),
    _task("t1b", "i1", "2026-08-10", "completed", 2000),
    _task("t2a", "i2", "2026-08-10", "cancelled", 500, "task expired abc"),
    _task("t2b", "i2", "2026-08-10", "completed", 1500),
    _task("t3a", "i3", "2026-08-11", "cancelled", 300, "runtime went offline"),
    _task("t3b", "i3", "2026-08-11", "completed", 700),
    _task("t4a", "i4", "2026-08-11", "cancelled", 900, "task expired xyz"),
    _task("t4b", "i4", "2026-08-11", "completed", 1100),
]


# --------------------------------------------------------------------------- #
# The SQL contract
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_query_exposes_the_documented_columns(tmp_path):
    _, idx = _run(_warehouse(tmp_path, _ISSUES, _TASKS))
    for col in ("workspace_id", "root_cause", "issues", "rework_tokens",
                "sample_size", "window_start", "window_end"):
        assert col in idx, f"missing contract column {col}"


@pytest.mark.unit
def test_query_produces_a_two_by_two_matrix(tmp_path):
    rows, idx = _run(_warehouse(tmp_path, _ISSUES, _TASKS))
    workspaces = {r[idx["workspace_id"]] for r in rows}
    causes = {r[idx["root_cause"]] for r in rows}
    assert workspaces == {WS_A, WS_B}
    assert causes == {"runtime-offline", "queue-timeout"}
    assert len(rows) == 4


@pytest.mark.unit
def test_one_issue_is_never_counted_under_two_root_causes(tmp_path):
    """The correctness guard: an issue whose runs failed for two different
    reasons must land in exactly ONE cell, or every total is inflated."""
    issues = [("i1", WS_A), ("i2", WS_A)]
    tasks = [
        # i1 failed twice, for two DIFFERENT reasons, then completed.
        _task("t1a", "i1", "2026-08-10", "cancelled", 1000, "runtime went offline"),
        _task("t1b", "i1", "2026-08-10", "cancelled", 100, "task expired abc"),
        _task("t1c", "i1", "2026-08-10", "completed", 900),
        _task("t2a", "i2", "2026-08-10", "cancelled", 40, "task expired abc"),
        _task("t2b", "i2", "2026-08-10", "completed", 60),
    ]
    rows, idx = _run(_warehouse(tmp_path, issues, tasks))
    assert sum(r[idx["issues"]] for r in rows) == 2, "issue counted twice"
    assert sum(r[idx["rework_tokens"]] for r in rows) == 2100, (
        "token total must equal the sum over issues, not over (issue, cause)"
    )
    # And the surviving cause for i1 is the dominant one, deterministically.
    i1_row = [r for r in rows if r[idx["issues"]] == 1
              and r[idx["rework_tokens"]] == 2000]
    assert i1_row and i1_row[0][idx["root_cause"]] == "runtime-offline"


@pytest.mark.unit
def test_sample_size_counts_rework_issues_once(tmp_path):
    rows, idx = _run(_warehouse(tmp_path, _ISSUES, _TASKS))
    assert {r[idx["sample_size"]] for r in rows} == {4}


@pytest.mark.unit
def test_window_bounds_are_cst_days(tmp_path):
    rows, idx = _run(_warehouse(tmp_path, _ISSUES, _TASKS))
    assert rows[0][idx["window_start"]] == "2026-08-10"
    assert rows[0][idx["window_end"]] == "2026-08-11"


@pytest.mark.unit
def test_issues_without_both_cancelled_and_completed_are_not_rework(tmp_path):
    issues = [("i1", WS_A)]
    tasks = [
        _task("t1a", "i1", "2026-08-10", "cancelled", 1000, "runtime went offline"),
    ]
    rows, _ = _run(_warehouse(tmp_path, issues, tasks))
    assert rows == [], "a cancelled-only issue was never redone; it is not rework"


@pytest.mark.unit
def test_since_filters_by_cst_day(tmp_path):
    rows, idx = _run(_warehouse(tmp_path, _ISSUES, _TASKS), since="2026-08-11")
    assert {r[idx["workspace_id"]] for r in rows} == {WS_B}


@pytest.mark.unit
def test_unclassified_failures_get_their_own_bucket(tmp_path):
    """An issue redone with no recorded error still belongs on the matrix —
    dropping it would understate rework, which is the number that matters."""
    issues = [("i1", WS_A)]
    tasks = [
        _task("t1a", "i1", "2026-08-10", "cancelled", 100),
        _task("t1b", "i1", "2026-08-10", "completed", 200),
    ]
    rows, idx = _run(_warehouse(tmp_path, issues, tasks))
    assert [r[idx["root_cause"]] for r in rows] == ["unclassified"]


# --------------------------------------------------------------------------- #
# fetch_rework_relationship — degrade-safe L5 bundle
# --------------------------------------------------------------------------- #
class _FakeRows:
    def __init__(self, rows, cols):
        self.rows, self.cols = rows, cols

    def __call__(self, name, params=None):
        return self.rows, self.cols


_COLS = ["workspace_id", "root_cause", "issues", "rework_tokens",
         "sample_size", "window_start", "window_end"]


class _Exists:
    @staticmethod
    def exists() -> bool:
        return True


class _Missing:
    @staticmethod
    def exists() -> bool:
        return False


@pytest.mark.unit
def test_fetch_builds_cells_keyed_row_workspace_column_cause(monkeypatch):
    monkeypatch.setattr(s, "clean_path", lambda _n: _Exists)
    monkeypatch.setattr(s.serve, "run_query", _FakeRows([
        (WS_A, "runtime-offline", 2, 48000, 4, "2026-08-05", "2026-08-11"),
        (WS_B, "queue-timeout", 1, 12000, 4, "2026-08-05", "2026-08-11"),
    ], _COLS))
    bundle = s.fetch_rework_relationship(None)
    assert bundle.health.state == "ok"
    assert bundle.sample_size == 4
    assert bundle.time_window == "2026-08-05 → 2026-08-11"
    assert [(c.row, c.column, c.value) for c in bundle.cells] == [
        (WS_A[:8], "runtime-offline", 48000.0),
        (WS_B[:8], "queue-timeout", 12000.0),
    ]


@pytest.mark.unit
def test_fetch_maps_workspace_uuid_to_friendly_name(monkeypatch):
    """Workspace names live in the gitignored config, so SQL cannot map them."""
    monkeypatch.setattr(s, "clean_path", lambda _n: _Exists)
    monkeypatch.setattr(s, "_WS_NAMES", {WS_A: "my"})
    monkeypatch.setattr(s.serve, "run_query", _FakeRows([
        (WS_A, "runtime-offline", 2, 48000, 2, "2026-08-05", "2026-08-11"),
    ], _COLS))
    assert s.fetch_rework_relationship(None).cells[0].row == "my"


@pytest.mark.unit
def test_fetch_degrades_when_source_never_collected(monkeypatch):
    monkeypatch.setattr(s, "clean_path", lambda _n: _Missing)
    bundle = s.fetch_rework_relationship(None)
    assert bundle.cells == []
    assert bundle.sample_size == 0
    assert bundle.health.state != "ok"


@pytest.mark.unit
def test_fetch_degrades_on_query_failure_without_raising(monkeypatch):
    def _boom(name, params=None):
        raise RuntimeError("warehouse missing")

    monkeypatch.setattr(s, "clean_path", lambda _n: _Exists)
    monkeypatch.setattr(s.serve, "run_query", _boom)
    bundle = s.fetch_rework_relationship(None)
    assert bundle.cells == []
    assert bundle.health.state == "error", "must degrade, never raise (ADR-23)"


@pytest.mark.unit
def test_fetch_handles_empty_result(monkeypatch):
    monkeypatch.setattr(s, "clean_path", lambda _n: _Exists)
    monkeypatch.setattr(s.serve, "run_query", _FakeRows([], _COLS))
    bundle = s.fetch_rework_relationship(None)
    assert bundle.cells == []
    assert bundle.sample_size == 0
    assert bundle.health.state != "ok", "no rows is not a publishable relationship"
