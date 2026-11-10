"""Test L3 merge of linear_issue into fact_issue alongside multica_issue."""

import sqlite3

import cleanio
import config
import merge
import pytest
from adapters import linear_issue, multica_issue


@pytest.mark.unit
def test_merge_combines_multica_and_linear_issues(monkeypatch, tmp_path):
    clean = tmp_path / "clean"
    monkeypatch.setattr(cleanio, "CLEAN_DIR", clean)
    monkeypatch.setattr(config, "CLEAN_DIR", clean)
    monkeypatch.setattr(merge, "WAREHOUSE_DB", tmp_path / "warehouse.db")

    cleanio.write_clean(
        "multica_issue",
        "issue",
        multica_issue._CLEAN_DDL,
        [
            {
                "issue_id": "m-1",
                "issue_number": 10,
                "identifier": "MY-10",
                "title": "Multica task",
                "status": "todo",
                "priority": "medium",
                "created_at": "2026-11-08T10:00:00Z",
                "workspace_id": "ws-my",
                "updated_at": "2026-11-08T12:00:00Z",
                "project_id": "AIDash",
            }
        ],
        multica_issue._CLEAN_COLS,
    )
    cleanio.write_clean(
        "linear_issue",
        "issue",
        linear_issue._CLEAN_DDL,
        [
            {
                "issue_id": "lin-90",
                "issue_number": 90,
                "identifier": "TIA-90",
                "title": "Linear SSOT todo",
                "status": "in_progress",
                "priority": "high",
                "created_at": "2026-11-09T09:00:00Z",
                "workspace_id": "linear:TIA",
                "updated_at": "2026-11-09T11:00:00Z",
                "project_id": "Personal project",
            }
        ],
        linear_issue._CLEAN_COLS,
    )

    counts = merge.run_merge()
    assert counts["fact_issue"] == 2
    with sqlite3.connect(merge.WAREHOUSE_DB) as conn:
        rows = conn.execute(
            "SELECT identifier, status, priority, workspace_id, project_id, cst_day "
            "FROM fact_issue ORDER BY identifier"
        ).fetchall()
    assert rows == [
        ("MY-10", "todo", "medium", "ws-my", "AIDash", "2026-11-08"),
        ("TIA-90", "in_progress", "high", "linear:TIA", "Personal project", "2026-11-09"),
    ]
