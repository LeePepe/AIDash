"""Unit tests for multica_run multi-workspace collection (EXT-2).

Hermetic: the CLI runner and raw IO are monkeypatched. Verifies runs are fetched
per-workspace with the right --workspace-id and per-workspace watermarks.
"""

import pytest

import adapters.multica_run as mr


# Raw issue records (as multica_issue writes them) across two workspaces.
RAW_ISSUES = [
    {"id": "s-1", "identifier": "ABC-429", "number": 429, "workspace_id": "ws-wsa"},
    {"id": "u-1", "identifier": "MY-100", "number": 100, "workspace_id": "ws-my"},
]


@pytest.fixture
def canned(monkeypatch):
    calls: list[list[str]] = []
    store: dict[str, object] = {}
    written: list[dict] = []

    def fake_run_json(args):
        calls.append(args)
        if args[1] == "runs":
            return [{"id": f"run-{args[2]}", "issue_id": "x", "status": "completed"}]
        return {}  # usage

    monkeypatch.setattr(mr, "_run_json", fake_run_json)
    monkeypatch.setattr(mr, "read_raw", lambda src: RAW_ISSUES)
    monkeypatch.setattr(mr, "write_raw", lambda src, recs: (written.extend(recs) or len(recs)))
    monkeypatch.setattr(mr, "get_watermark", lambda k: store.get(k))
    monkeypatch.setattr(mr, "set_watermark", lambda k, v: store.__setitem__(k, v))
    monkeypatch.setattr(mr, "MULTICA_WORKSPACES", (("ws-wsa", "WorkspaceA"), ("ws-my", "my")))
    return calls, store, written


@pytest.mark.unit
def test_runs_fetched_with_workspace_id_flag(canned):
    calls, store, written = canned
    mr.collect()
    runs_calls = [c for c in calls if c[1] == "runs"]
    # ABC-429 fetched with workspace-a ws id, MY-100 with my ws id
    wsa = [c for c in runs_calls if c[2] == "ABC-429"][0]
    my = [c for c in runs_calls if c[2] == "MY-100"][0]
    assert "ws-wsa" in wsa and "--workspace-id" in wsa
    assert "ws-my" in my and "--workspace-id" in my


@pytest.mark.unit
def test_per_workspace_watermark_isolates_backfill(canned):
    calls, store, written = canned
    # workspace-a already caught up past ABC-429; my never collected
    store["multica_run:ws-wsa"] = 429
    mr.collect()
    runs_calls = [c[2] for c in calls if c[1] == "runs"]
    assert "ABC-429" not in runs_calls  # skipped by watermark
    assert "MY-100" in runs_calls
    assert store["multica_run:ws-my"] == 100


@pytest.mark.unit
def test_writes_carry_issue_and_workspace_context(canned):
    calls, store, written = canned
    mr.collect()
    by_ident = {r["_issue_identifier"]: r for r in written}
    assert by_ident["ABC-429"]["_workspace_id"] == "ws-wsa"
    assert by_ident["MY-100"]["_workspace_id"] == "ws-my"


@pytest.mark.unit
def test_normalize_carries_workflow_columns_and_nulls_none_error(monkeypatch):
    """The 3 new clean columns are populated and the literal "None" error -> NULL."""
    raw = [
        {  # a failed run with a real root-cause error + trigger context
            "id": "run-1", "issue_id": "iss-x", "status": "failed",
            "trigger_summary": "[@Team Lead](mention://agent/x) retry",
            "trigger_comment_id": "cmt-1", "error": "runtime went offline",
        },
        {  # a clean run whose absent error arrives as the string "None"
            "id": "run-2", "issue_id": "iss-x", "status": "completed",
            "trigger_summary": None, "trigger_comment_id": None, "error": "None",
        },
    ]
    monkeypatch.setattr(mr, "read_raw", lambda src: raw)
    captured: dict = {}

    def fake_write_clean(source, table, ddl, rows, cols):
        captured["rows"] = {r["task_id"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(mr, "write_clean", fake_write_clean)
    mr.normalize()
    for col in ("trigger_summary", "trigger_comment_id", "error"):
        assert col in captured["cols"]
    r1 = captured["rows"]["run-1"]
    r2 = captured["rows"]["run-2"]
    assert r1["error"] == "runtime went offline"
    assert r1["trigger_comment_id"] == "cmt-1"
    assert "Team Lead" in r1["trigger_summary"]
    # "None" string is normalized to a real SQL NULL, not carried through
    assert r2["error"] is None
    assert r2["trigger_summary"] is None
