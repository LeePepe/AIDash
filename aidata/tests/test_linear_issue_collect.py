"""Unit tests for the linear_issue pluggable L1/L2 adapter (TodoSyncProvider v1)."""

import json
from datetime import datetime, timezone

import adapters.linear_issue as li
import pytest

NOW = datetime(2026, 11, 9, 12, 0, 0, tzinfo=timezone.utc)  # noqa: UP017

TIA_ISSUES = [
    {
        "id": "lin-uuid-90",
        "identifier": "TIA-90",
        "title": "Sync voice todo to Linear",
        "state": "Todo",
        "stateType": "unstarted",
        "project": "Personal project",
        "priority": 1,
        "url": "https://linear.app/tianpeili/issue/TIA-90",
        "createdAt": "2026-11-09T09:00:00Z",
        "updatedAt": "2026-11-09T10:00:00Z",
        "labels": [],
    },
    {
        "id": "lin-uuid-91",
        "identifier": "TIA-91",
        "title": "Blocked on owner decision",
        "state": "In Progress",
        "stateType": "started",
        "project": "Agent Workflow",
        "priority": 3,
        "url": "https://linear.app/tianpeili/issue/TIA-91",
        "createdAt": "2026-11-08T09:00:00Z",
        "updatedAt": "2026-11-09T11:00:00Z",
        "labels": ["Needs Decision"],
    },
    {
        "id": "lin-uuid-92",
        "identifier": "TIA-92",
        "title": "Finished task with old blocked label",
        "state": "Done",
        "stateType": "completed",
        "project": "Bing",
        "priority": 4,
        "url": "https://linear.app/tianpeili/issue/TIA-92",
        "createdAt": "2026-11-01T09:00:00Z",
        "updatedAt": "2026-11-09T08:00:00Z",
        "labels": ["Blocked"],
    },
    {
        "id": "lin-uuid-93",
        "identifier": "TIA-93",
        "title": "Triage idea",
        "state": "Triage",
        "stateType": "triage",
        "project": None,
        "priority": 0,
        "url": "https://linear.app/tianpeili/issue/TIA-93",
        "createdAt": "2026-10-01T09:00:00Z",
        "updatedAt": "2026-10-02T09:00:00Z",
        "labels": [],
    },
]


@pytest.fixture
def canned_linear(monkeypatch, tmp_path):
    store: dict[str, str] = {}
    written: list[dict] = []
    script = tmp_path / "linear-sync.py"
    script.write_text("#!/usr/bin/env python3\n", encoding="utf-8")

    monkeypatch.setattr(li, "LINEAR_SYNC_SCRIPT", script)
    monkeypatch.setattr(li, "LINEAR_TEAM_KEY", "TIA")
    monkeypatch.setattr(li, "_list_team_issues", lambda team: list(TIA_ISSUES))
    monkeypatch.setattr(
        li, "write_raw", lambda src, recs: (written.extend(recs) or len(recs))
    )
    monkeypatch.setattr(li, "get_watermark", lambda k: store.get(k))
    monkeypatch.setattr(li, "set_watermark", lambda k, v: store.__setitem__(k, v))
    return store, written


@pytest.mark.unit
def test_collect_degrades_to_zero_when_script_absent(monkeypatch, tmp_path):
    monkeypatch.setattr(li, "LINEAR_SYNC_SCRIPT", tmp_path / "missing.py")
    assert li.collect(now=NOW) == 0


@pytest.mark.unit
def test_collect_skips_when_provider_mode_is_local(canned_linear, monkeypatch, tmp_path):
    _, written = canned_linear
    cfg_path = tmp_path / "todo-sync.json"
    cfg_path.write_text(json.dumps({"provider": "local", "teamKey": "TIA"}), encoding="utf-8")
    monkeypatch.setattr(li, "TODO_SYNC_CONFIG_PATH", cfg_path)
    monkeypatch.delenv("AIDASH_TODO_SYNC_PROVIDER", raising=False)
    assert li.collect(now=NOW) == 0
    assert written == []


@pytest.mark.unit
def test_collect_degrades_to_zero_when_subprocess_fails(monkeypatch, tmp_path):
    script = tmp_path / "linear-sync.py"
    script.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    monkeypatch.setattr(li, "LINEAR_SYNC_SCRIPT", script)

    class FailedProc:
        returncode = 1
        stdout = '{"ok": false}'

    monkeypatch.setattr(li.subprocess, "run", lambda *a, **k: FailedProc())
    assert li.collect(now=NOW) == 0


@pytest.mark.unit
def test_collect_first_run_backfills_and_sets_watermark(canned_linear):
    store, written = canned_linear
    count = li.collect(now=NOW)
    assert count == 4
    assert {r["identifier"] for r in written} == {
        "TIA-90",
        "TIA-91",
        "TIA-92",
        "TIA-93",
    }
    assert store["linear_issue:TIA"] == "2026-11-09T11:00:00Z"


@pytest.mark.unit
def test_collect_window_filters_by_watermark_and_cutoff(canned_linear):
    store, written = canned_linear
    store["linear_issue:TIA"] = "2026-11-09T09:30:00Z"
    count = li.collect(now=NOW)
    assert count == 2
    assert {r["identifier"] for r in written} == {"TIA-90", "TIA-91"}
    assert store["linear_issue:TIA"] == "2026-11-09T11:00:00Z"


@pytest.mark.unit
def test_list_team_issues_parses_cli_json(monkeypatch, tmp_path):
    script = tmp_path / "linear-sync.py"
    script.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    monkeypatch.setattr(li, "LINEAR_SYNC_SCRIPT", script)

    class OkProc:
        returncode = 0
        stdout = json.dumps({"ok": True, "issues": TIA_ISSUES[:1]})

    monkeypatch.setattr(li.subprocess, "run", lambda *a, **k: OkProc())
    out = li._list_team_issues("TIA")
    assert len(out) == 1
    assert out[0]["identifier"] == "TIA-90"


@pytest.mark.unit
def test_normalize_maps_states_priorities_and_labels(monkeypatch):
    raw_records = [
        *TIA_ISSUES,
        {
            "identifier": "TIA-94",
            "title": "In review item",
            "state": "In Review",
            "stateType": "started",
            "priority": 2,
            "updatedAt": "2026-11-09T12:00:00Z",
            "labels": [],
        },
        {
            "identifier": "TIA-95",
            "title": "Cancelled item",
            "state": "Canceled",
            "stateType": "canceled",
            "priority": 3,
            "updatedAt": "2026-11-09T12:00:00Z",
            "labels": ["NEED_GO"],
        },
    ]
    monkeypatch.setattr(li, "read_raw", lambda src: raw_records)
    captured: dict = {}

    def fake_write_clean(source, table, ddl, rows, cols):
        captured["rows"] = {r["identifier"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(li, "write_clean", fake_write_clean)
    assert li.normalize() == 6
    by_ident = captured["rows"]

    assert by_ident["TIA-90"]["issue_id"] == "lin-uuid-90"
    assert by_ident["TIA-90"]["issue_number"] == 90
    assert by_ident["TIA-90"]["status"] == "todo"
    assert by_ident["TIA-90"]["priority"] == "high"
    assert by_ident["TIA-90"]["workspace_id"] == "linear:TIA"
    assert by_ident["TIA-90"]["project_id"] == "Personal project"

    # Open issue with Needs Decision label maps to blocked
    assert by_ident["TIA-91"]["status"] == "blocked"
    assert by_ident["TIA-91"]["priority"] == "medium"

    # Completed issue ignores stale Blocked label
    assert by_ident["TIA-92"]["status"] == "done"
    assert by_ident["TIA-92"]["priority"] == "low"

    # Triage maps to backlog (excluded from active inbox until promoted to Todo)
    assert by_ident["TIA-93"]["status"] == "backlog"
    assert by_ident["TIA-93"]["priority"] == "medium"

    # Fallback id when UUID is absent + In Review + Priority 2 -> high
    assert by_ident["TIA-94"]["issue_id"] == "linear:TIA-94"
    assert by_ident["TIA-94"]["status"] == "in_review"
    assert by_ident["TIA-94"]["priority"] == "high"

    # Canceled state wins over NEED_GO label
    assert by_ident["TIA-95"]["status"] == "cancelled"
