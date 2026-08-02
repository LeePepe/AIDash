"""Hermetic tests for the M3 digest fetchers (ADO PR + automation).

serve.run_query and clean_path are monkeypatched, so no warehouse.db / state.db
is needed and the degrade-not-crash paths (ADR-23) are proven deterministically.
"""


import pytest

import L5_apps.digest.sources as src
from L5_apps.digest.sources import (
    AdoPrTrends, AutomationTrends, fetch_ado_pr_trends, fetch_automation_trends,
)


class _Exists:
    def exists(self):
        return True


class _Missing:
    def exists(self):
        return False


# --- ADO PR -----------------------------------------------------------------

@pytest.mark.unit
def test_fetch_ado_pr_degrades_when_clean_missing(monkeypatch):
    monkeypatch.setattr(src, "clean_path", lambda s: _Missing())
    monkeypatch.setattr(src.serve, "run_query",
                        lambda *a, **k: pytest.fail("must not query when uncollected"))
    t = fetch_ado_pr_trends()
    assert isinstance(t, AdoPrTrends)
    assert t.health.state.startswith("skipped")
    assert t.opened == [] and t.merged == []


@pytest.mark.unit
def test_fetch_ado_pr_reshapes_series(monkeypatch):
    monkeypatch.setattr(src, "clean_path", lambda s: _Exists())
    rows = [("2026-07-09", 3, 2), ("2026-07-08", 1, 0)]
    cols = ["day", "opened", "merged"]
    monkeypatch.setattr(src.serve, "run_query", lambda name, *a, **k: (rows, cols))
    t = fetch_ado_pr_trends()
    assert t.health.state == "ok"
    assert t.opened == [("2026-07-09", 3.0), ("2026-07-08", 1.0)]
    assert t.merged == [("2026-07-09", 2.0), ("2026-07-08", 0.0)]


@pytest.mark.unit
def test_fetch_ado_pr_degrades_on_query_error(monkeypatch):
    monkeypatch.setattr(src, "clean_path", lambda s: _Exists())

    def boom(*a, **k):
        raise RuntimeError("bad sql")

    monkeypatch.setattr(src.serve, "run_query", boom)
    t = fetch_ado_pr_trends()
    assert t.health.state == "error"
    assert "bad sql" in t.health.detail
    assert t.opened == [] and t.merged == []


# --- Automation -------------------------------------------------------------

@pytest.mark.unit
def test_fetch_automation_degrades_when_clean_missing(monkeypatch):
    monkeypatch.setattr(src, "clean_path", lambda s: _Missing())
    t = fetch_automation_trends()
    assert isinstance(t, AutomationTrends)
    assert t.health.state.startswith("skipped")
    assert t.ratio == [] and t.automated == [] and t.manual == []


@pytest.mark.unit
def test_fetch_automation_reshapes_series(monkeypatch):
    monkeypatch.setattr(src, "clean_path", lambda s: _Exists())
    rows = [("2026-07-09", 8, 2, 10, 0.8), ("2026-07-08", 3, 3, 6, 0.5)]
    cols = ["day", "automated", "manual", "total", "automation_ratio"]
    monkeypatch.setattr(src.serve, "run_query", lambda name, *a, **k: (rows, cols))
    t = fetch_automation_trends()
    assert t.health.state == "ok"
    assert t.ratio == [("2026-07-09", 0.8), ("2026-07-08", 0.5)]
    assert t.automated == [("2026-07-09", 8.0), ("2026-07-08", 3.0)]
    assert t.manual == [("2026-07-09", 2.0), ("2026-07-08", 3.0)]


@pytest.mark.unit
def test_fetch_automation_degrades_on_query_error(monkeypatch):
    monkeypatch.setattr(src, "clean_path", lambda s: _Exists())

    def boom(*a, **k):
        raise RuntimeError("attach failed")

    monkeypatch.setattr(src.serve, "run_query", boom)
    t = fetch_automation_trends()
    assert t.health.state == "error"
    assert t.ratio == []
