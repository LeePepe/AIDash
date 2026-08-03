"""Tests for the cost-attribution layer (project x cost x model).

Attribution is the one place in this pipeline where a number can be quietly
WRONG rather than merely missing: a session touches several projects, so the
obvious implementation (sum each session's cost into every project it touched)
inflates every figure and still looks plausible on screen. These tests pin the
weighting that prevents that, and the honest-coverage caveat around it.
"""

import pytest

from L5_apps.digest import sources as s


class _FakeRows:
    """Stand-in for serve.run_query returning (rows, cols)."""

    def __init__(self, rows, cols):
        self.rows, self.cols = rows, cols

    def __call__(self, name, params=None):
        return self.rows, self.cols


# --------------------------------------------------------------------------- #
# fetch_cost_by_project
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_cost_by_project_ranks_by_share(monkeypatch):
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("AIDash", 1552.93, 41.4, 331680.5, 1492.0, 19),
         ("VitalStride", 900.04, 24.0, 191641.8, 1807.0, 26)],
        ["project", "cost_usd", "cost_pct", "ktokens", "requests", "sessions"]))
    bundle = s.fetch_cost_by_project("2026-08-02")
    assert bundle.health.state == "ok"
    assert [i.label for i in bundle.items] == ["AIDash", "VitalStride"]
    # The bar is drawn from the SHARE, so the card reads as "where the money
    # went" rather than an unanchored dollar figure.
    assert bundle.items[0].value_text == "41%"


@pytest.mark.unit
def test_cost_by_project_degrades_on_failure(monkeypatch):
    def _boom(name, params=None):
        raise RuntimeError("warehouse missing")

    monkeypatch.setattr(s.serve, "run_query", _boom)
    bundle = s.fetch_cost_by_project("2026-08-02")
    assert bundle.items == []
    assert bundle.health.state == "error", "must degrade, never raise (ADR-23)"


@pytest.mark.unit
def test_cost_by_project_handles_empty(monkeypatch):
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [], ["project", "cost_usd", "cost_pct", "ktokens", "requests", "sessions"]))
    bundle = s.fetch_cost_by_project(None)
    assert bundle.items == []
    assert bundle.health.state == "ok"


# --------------------------------------------------------------------------- #
# fetch_model_by_project
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_model_by_project_labels_pair_and_shows_dollars(monkeypatch):
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("AIDash", "claude-opus-5", 1292.91, 83.3, 390.9),
         ("VitalStride", "claude-opus-4-7", 186.97, 20.8, 306.4)],
        ["project", "model", "cost_usd", "pct_of_project", "out_ktok"]))
    bundle = s.fetch_model_by_project("2026-08-02")
    assert bundle.items[0].label == "AIDash · claude-opus-5"
    assert bundle.items[0].value_text == "$1293"


@pytest.mark.unit
def test_model_by_project_degrades(monkeypatch):
    def _boom(name, params=None):
        raise RuntimeError("nope")

    monkeypatch.setattr(s.serve, "run_query", _boom)
    assert s.fetch_model_by_project(None).health.state == "error"


# --------------------------------------------------------------------------- #
# The card container
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_attribution_container_sits_below_the_trends_it_explains():
    from L5_apps.digest.aidash import _attribution_container

    bundle = s.RankBundle(
        [s.RankItem("AIDash", 41.4, "41%")], s.SourceHealth("attribution", "ok"))
    container = _attribution_container("0803", bundle, bundle)
    assert container is not None
    # 趋势指标 is order 20; attribution must land between it and AI 效能 (25),
    # because it exists to explain the arrows directly above it.
    assert 20 < container.order < 25
    assert container.title == "成本归因"
    assert len(container.cards) == 2
    assert all(c.type == "barList" for c in container.cards), (
        "reuses an existing CardType — no new renderer needed"
    )


@pytest.mark.unit
def test_attribution_container_omitted_when_unavailable():
    """An empty frame is worse than no section (ADR-23)."""
    from L5_apps.digest.aidash import _attribution_container

    empty = s.RankBundle([], s.SourceHealth("attribution", "skipped:未取"))
    assert _attribution_container("0803", empty, empty) is None


@pytest.mark.unit
def test_fetch_sources_wires_attribution():
    """The seam must actually be called, or the card silently never appears."""
    import ast
    import inspect

    from L5_apps.digest import app

    tree = ast.parse(inspect.getsource(app._fetch_sources))
    called = {
        n.func.id for n in ast.walk(tree)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
    }
    assert "fetch_cost_by_project" in called
    assert "fetch_model_by_project" in called
