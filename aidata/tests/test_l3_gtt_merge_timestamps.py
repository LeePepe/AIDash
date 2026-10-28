"""Exercise goal upsert ordering through the real attached-source merge path."""

import sqlite3

import cleanio
import config
import merge
import pytest
from adapters import gtt_ledger


@pytest.mark.unit
@pytest.mark.parametrize("reverse", [False, True])
@pytest.mark.parametrize("newer,older", [
    ("2026-10-28T02:00:00Z", "2026-10-28T09:00:00+08:00"),
    ("2026-10-28T02:00:00", "2026-10-28T01:00:00Z"),
    ("2026-10-28T02:00:00.000001Z", "2026-10-28T02:00:00Z"),
    ("2026-10-28T02:00:00+00:00", None),
    ("2026-10-28T02:00:00Z", "invalid"),
])
def test_merge_keeps_newest_goal_across_timestamp_formats(monkeypatch, tmp_path, newer, older, reverse):
    clean = tmp_path / "clean"
    monkeypatch.setattr(cleanio, "CLEAN_DIR", clean)
    monkeypatch.setattr(config, "CLEAN_DIR", clean)
    monkeypatch.setattr(merge, "WAREHOUSE_DB", tmp_path / "warehouse.db")
    # A legacy source can contain duplicate goal keys. Remove its source-side
    # uniqueness constraint to exercise both branches of the warehouse upsert.
    ddl = gtt_ledger._GOAL_DDL.replace("PRIMARY KEY", "")
    with sqlite3.connect(":memory:") as conn:
        conn.execute(ddl)
        columns = [row[1] for row in conn.execute("PRAGMA table_info(goal)")]
    rows = [dict.fromkeys(columns) for _ in range(2)]
    for row, title, ts in ((rows[0], "newest", newer), (rows[1], "older", older)):
        row.update(goal_uid="machine:goal", machine_id="machine", goal_id="goal",
                   title=title, last_event_at=ts)
    if reverse:
        rows.reverse()
    cleanio.write_clean("gtt_ledger", "goal", ddl, rows, columns)
    cleanio.write_clean("gtt_ledger", "gtt_event", gtt_ledger._EVENT_DDL, [], ())
    for _ in range(2):
        assert merge.run_merge()["dim_goal"] == 1
        with sqlite3.connect(merge.WAREHOUSE_DB) as conn:
            assert conn.execute("SELECT title, last_event_at FROM dim_goal").fetchall() == [("newest", newer)]
