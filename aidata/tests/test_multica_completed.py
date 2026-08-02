"""Unit + integration tests for the multica completed-issue fetcher and render.

Unit tests are hermetic (serve.run_query monkeypatched); integration tests hit
the built warehouse if present.
"""

import pytest

from L5_apps.digest.sources import (
    fetch_multica_completed, MulticaTrends, SourceHealth,
)


def _fake_query(rows, cols):
    def run_query(name, params=None):
        return rows, cols
    return run_query


@pytest.mark.unit
def test_fetch_multica_reshapes_total_and_per_workspace(monkeypatch):
    import serve
    from L5_apps.digest import sources

    # Hermetic: the real workspace ids live in the git-ignored config_local.py,
    # so pin the id→friendly-name map instead of depending on this machine's.
    monkeypatch.setattr(sources, "_WS_NAMES",
                        {"ws-a": "WorkspaceA", "ws-my": "my"})
    rows = [
        ("2026-07-09", "ws-a", 3),
        ("2026-07-09", "ws-my", 5),
        ("2026-07-08", "ws-my", 2),
    ]
    monkeypatch.setattr(serve, "run_query",
                        _fake_query(rows, ["day", "workspace_id", "completed"]))
    t = fetch_multica_completed()
    assert isinstance(t, MulticaTrends)
    assert t.health.state == "ok"
    # total per day = sum across workspaces
    assert dict(t.completed)["2026-07-09"] == 8.0
    assert dict(t.completed)["2026-07-08"] == 2.0
    # per-workspace mapped to friendly names
    assert dict(t.completed_by_ws["WorkspaceA"])["2026-07-09"] == 3.0
    assert dict(t.completed_by_ws["my"])["2026-07-09"] == 5.0


@pytest.mark.unit
def test_fetch_multica_degrades_on_failure(monkeypatch):
    import serve

    def boom(name, params=None):
        raise RuntimeError("multica query blew up")

    monkeypatch.setattr(serve, "run_query", boom)
    t = fetch_multica_completed()
    assert t.health.state == "error"
    assert "blew up" in t.health.detail
    assert t.completed == []
    assert t.completed_by_ws == {}


@pytest.mark.integration
def test_fetch_multica_completed_against_warehouse():
    t = fetch_multica_completed()
    # Either ok with real series, or gracefully degraded — never a crash.
    assert t.health.state in ("ok", "error")
    for day, val in t.completed:
        assert isinstance(day, str) and isinstance(val, (int, float))
