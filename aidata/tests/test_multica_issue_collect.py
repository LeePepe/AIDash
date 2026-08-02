"""Unit tests for the multica_issue adapter's updated_since window read.

Hermetic: the multica CLI, raw writer, and watermark state are all monkeypatched
so these run without a live CLI or warehouse (ADR-19 / EXT-1/2/3).
"""

from datetime import datetime, timezone

import pytest

import adapters.multica_issue as mi


NOW = datetime(2026, 7, 11, 12, 0, 0, tzinfo=timezone.utc)

# Two workspaces' worth of canned issues. Old issue MY-3 was created long ago but
# just got completed today (updated_at recent) — the case the old number>watermark
# strategy missed forever.
MY_ISSUES = [
    {"id": "u-new", "number": 100, "identifier": "MY-100", "title": "new",
     "status": "todo", "priority": "none", "created_at": "2026-07-11T09:00:00Z",
     "updated_at": "2026-07-11T09:00:00Z", "project_id": None,
     "workspace_id": "ws-my"},
    {"id": "u-old-done", "number": 3, "identifier": "MY-3", "title": "old but done",
     "status": "done", "priority": "high", "created_at": "2026-05-01T09:00:00Z",
     "updated_at": "2026-07-11T08:00:00Z", "project_id": "proj-x",
     "workspace_id": "ws-my"},
    {"id": "u-stale", "number": 4, "identifier": "MY-4", "title": "untouched old",
     "status": "todo", "priority": "none", "created_at": "2026-05-01T09:00:00Z",
     "updated_at": "2026-05-02T09:00:00Z", "project_id": None,
     "workspace_id": "ws-my"},
]
SAP_ISSUES = [
    {"id": "s-1", "number": 429, "identifier": "ABC-429", "title": "wsa one",
     "status": "done", "priority": "none", "created_at": "2026-07-11T07:00:00Z",
     "updated_at": "2026-07-11T07:00:00Z", "project_id": None,
     "workspace_id": "ws-wsa"},
]


@pytest.fixture
def canned(monkeypatch):
    """Wire per-workspace issue lists + capture raw writes + fake watermarks."""
    store: dict[str, str] = {}
    written: list[dict] = []

    def fake_list(ws_id: str) -> list[dict]:
        return {"ws-wsa": SAP_ISSUES, "ws-my": MY_ISSUES}.get(ws_id, [])

    # collect() now short-circuits when the CLI is absent (degrade guard);
    # pretend it's present so these hermetic tests exercise the real path.
    monkeypatch.setattr(mi, "_multica_bin", lambda: "/usr/bin/multica")
    monkeypatch.setattr(mi, "_list_workspace_issues", fake_list)
    monkeypatch.setattr(mi, "write_raw", lambda src, recs: (written.extend(recs) or len(recs)))
    monkeypatch.setattr(mi, "get_watermark", lambda k: store.get(k))
    monkeypatch.setattr(mi, "set_watermark", lambda k, v: store.__setitem__(k, v))
    monkeypatch.setattr(mi, "MULTICA_WORKSPACES", (("ws-wsa", "WorkspaceA"), ("ws-my", "my")))
    return store, written


@pytest.mark.unit
def test_backfill_first_run_writes_all_issues(canned):
    store, written = canned
    n = mi.collect(now=NOW)
    ids = {r["id"] for r in written}
    # first run has no watermark -> full backfill of both workspaces
    assert ids == {"u-new", "u-old-done", "u-stale", "s-1"}
    assert n == 4


@pytest.mark.unit
def test_per_workspace_watermark_isolation(canned):
    store, written = canned
    # my is already caught up to its newest edit; workspace-a never collected.
    store["multica_issue:ws-my"] = "2026-07-11T09:00:00Z"
    written.clear()
    mi.collect(now=NOW)
    ids = {r["id"] for r in written}
    # my: nothing newer than its watermark; workspace-a: full backfill
    assert ids == {"s-1"}


@pytest.mark.unit
def test_window_read_captures_old_issue_completed_recently(canned):
    store, written = canned
    # my watermark sits just before the old issue's completion edit
    store["multica_issue:ws-my"] = "2026-07-11T07:30:00Z"
    written.clear()
    mi.collect(now=NOW)
    ids = {r["id"] for r in written}
    # u-old-done (updated 08:00, number 3) is captured despite a low number;
    # u-stale (updated May, outside window) is NOT re-written.
    assert "u-old-done" in ids
    assert "u-stale" not in ids


@pytest.mark.unit
def test_watermark_advances_to_max_updated_at(canned):
    store, written = canned
    mi.collect(now=NOW)
    assert store["multica_issue:ws-my"] == "2026-07-11T09:00:00Z"
    assert store["multica_issue:ws-wsa"] == "2026-07-11T07:00:00Z"


@pytest.mark.unit
def test_normalize_carries_updated_at_and_project_id(monkeypatch):
    monkeypatch.setattr(mi, "read_raw", lambda src: [MY_ISSUES[1]])  # u-old-done
    captured: dict = {}

    def fake_write_clean(source, table, ddl, rows, cols):
        captured["rows"] = rows
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(mi, "write_clean", fake_write_clean)
    mi.normalize()
    assert "updated_at" in captured["cols"]
    assert "project_id" in captured["cols"]
    row = captured["rows"][0]
    assert row["updated_at"] == "2026-07-11T08:00:00Z"
    assert row["project_id"] == "proj-x"


@pytest.mark.unit
def test_collect_degrades_to_zero_without_cli(monkeypatch):
    """Missing CLI → collect returns 0 and never touches the workspace list."""
    monkeypatch.setattr(mi, "_multica_bin", lambda: None)
    called = {"n": 0}
    monkeypatch.setattr(
        mi, "_list_workspace_issues",
        lambda ws: called.__setitem__("n", called["n"] + 1) or [])
    assert mi.collect(now=NOW) == 0
    assert called["n"] == 0  # short-circuited before enumerating workspaces
