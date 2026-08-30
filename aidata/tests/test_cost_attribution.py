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


class _Exists:
    """Stand-in for a clean_path() result whose file is present."""

    @staticmethod
    def exists() -> bool:
        return True


class _Missing:
    """Stand-in for a clean_path() result whose file was never collected."""

    @staticmethod
    def exists() -> bool:
        return False


# --------------------------------------------------------------------------- #
# fetch_cost_by_project
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_cost_by_project_ranks_by_share(monkeypatch):
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("AIDash", 1552.93, 41.4, 331680.5, 1492.0, 19, 3748.50, 3748.50),
         ("VitalStride", 900.04, 24.0, 191641.8, 1807.0, 26, 3748.50, 3748.50)],
        ["project", "cost_usd", "cost_pct", "ktokens", "requests", "sessions",
         "day_total", "attributed_total"]))
    bundle = s.fetch_cost_by_project("2026-08-02")
    assert bundle.health.state == "ok"
    assert [i.label for i in bundle.items] == ["AIDash", "VitalStride"]
    # The bar is drawn from the SHARE, so the card reads as "where the money
    # went" rather than an unanchored dollar figure.
    assert bundle.items[0].value_text == "41%"
    # Full coverage — no "未归因" row appended.
    assert bundle.coverage_pct >= 99.5
    assert all(i.label != "未归因" for i in bundle.items)


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
        [], ["project", "cost_usd", "cost_pct", "ktokens", "requests", "sessions",
             "day_total", "attributed_total"]))
    bundle = s.fetch_cost_by_project(None)
    assert bundle.items == []
    assert bundle.health.state == "ok"


# --------------------------------------------------------------------------- #
# MY-1435 regression: partial coverage must be explicit
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_cost_by_project_partial_coverage_regression(monkeypatch):
    """Regression for headline $2858.35 with attributed total $2107.23.

    The unattributed portion ($751.12, ~26%) must be explicitly visible as a
    "未归因" row and the bundle must carry coverage metadata so the container
    can surface the gap in its subtitle. Previously, percentages were shown
    relative to the attributed total alone, silently implying full coverage.
    """
    # Simulate 3 projects summing to $2107.23, against a day total of $2858.35.
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("AIDash", 1200.00, 41.97, 200000.0, 800.0, 12, 2858.35, 2107.23),
         ("VitalStride", 600.00, 20.99, 100000.0, 400.0, 8, 2858.35, 2107.23),
         ("Multica", 307.23, 10.75, 50000.0, 200.0, 5, 2858.35, 2107.23)],
        ["project", "cost_usd", "cost_pct", "ktokens", "requests", "sessions",
         "day_total", "attributed_total"]))
    bundle = s.fetch_cost_by_project("2026-08-15")

    # Coverage metadata is explicit and reconcilable.
    assert bundle.headline_total == 2858.35
    assert bundle.attributed_total == 2107.23
    assert bundle.coverage_pct < 99.5, "partial coverage must be flagged"
    assert abs(bundle.coverage_pct - 100.0 * 2107.23 / 2858.35) < 0.1

    # The unattributed portion is visible as a row and kept in value order.
    labels = [i.label for i in bundle.items]
    assert "未归因" in labels, (
        "partial coverage must append an explicit unattributed row"
    )
    assert labels == ["AIDash", "未归因", "VitalStride", "Multica"], (
        "gap rows must be sorted by descending value, not appended at the end"
    )
    gap_item = next(i for i in bundle.items if i.label == "未归因")
    expected_gap = 2858.35 - 2107.23
    assert abs(gap_item.value - expected_gap) < 0.01
    assert gap_item.semantic == "warning", "renderer-supported semantic only"
    # Gap percentage is relative to headline, not attributed total.
    assert gap_item.value_text == "26%"

    # Arithmetic reconciliation: headline = attributed + gap.
    assert abs(bundle.headline_total
               - bundle.attributed_total - gap_item.value) < 0.01


@pytest.mark.unit
def test_cost_by_project_zero_attributable_keeps_headline_total(monkeypatch):
    """A day with spend but zero attributable rows still reports a truthful gap."""
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [(None, 0.0, 0.0, 0.0, 0, 0, 2858.35, 0.0)],
        ["project", "cost_usd", "cost_pct", "ktokens", "requests", "sessions",
         "day_total", "attributed_total"]))
    bundle = s.fetch_cost_by_project("2026-08-15")

    assert bundle.headline_total == 2858.35
    assert bundle.attributed_total == 0.0
    assert bundle.coverage_pct == 0.0
    assert [i.label for i in bundle.items] == ["未归因"]
    assert bundle.items[0].value == 2858.35
    assert bundle.items[0].value_text == "100%"
    assert bundle.items[0].semantic == "warning"


@pytest.mark.unit
def test_attribution_container_shows_coverage_subtitle(monkeypatch):
    """When coverage < 99.5%, the container subtitle surfaces the gap."""
    from L5_apps.digest.aidash import _attribution_container

    bundle = s.CostByProjectBundle(
        items=[s.RankItem("AIDash", 41.4, "42%")],
        headline_total=2858.35,
        attributed_total=2107.23,
        coverage_pct=73.7,
        health=s.SourceHealth("attribution", "ok"),
    )
    model_bundle = s.RankBundle(
        [s.RankItem("opus-5", 1200.0, "$1200")],
        s.SourceHealth("attribution", "ok"))
    container = _attribution_container("0815", bundle, model_bundle)
    assert container is not None
    assert "归因覆盖" in container.subtitle
    assert "73%" in container.subtitle
    # Dollar amounts present for reconciliation.
    assert "$2107" in container.subtitle
    assert "$2858" in container.subtitle


@pytest.mark.unit
def test_attribution_container_no_warning_at_full_coverage():
    """Full coverage (>=99.5%) produces a clean subtitle, no warning."""
    from L5_apps.digest.aidash import _attribution_container

    bundle = s.CostByProjectBundle(
        items=[s.RankItem("AIDash", 99.8, "100%")],
        headline_total=3000.0,
        attributed_total=2998.50,
        coverage_pct=99.95,
        health=s.SourceHealth("attribution", "ok"),
    )
    model_bundle = s.RankBundle(
        [s.RankItem("opus-5", 3000.0, "$3000")],
        s.SourceHealth("attribution", "ok"))
    container = _attribution_container("0815", bundle, model_bundle)
    assert container is not None
    assert "归因覆盖" not in container.subtitle


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

    bundle = s.CostByProjectBundle(
        [s.RankItem("AIDash", 41.4, "41%")],
        3748.50, 3748.50, 100.0,
        s.SourceHealth("attribution", "ok"))
    model_bundle = s.RankBundle(
        [s.RankItem("opus-5", 1200.0, "$1200")],
        s.SourceHealth("attribution", "ok"))
    container = _attribution_container("0803", bundle, model_bundle)
    assert container is not None
    # 趋势指標 is order 20; attribution must land between it and AI 效能 (25),
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

    empty = s.CostByProjectBundle(
        [], 0.0, 0.0, 100.0, s.SourceHealth("attribution", "skipped:未取"))
    model_empty = s.RankBundle([], s.SourceHealth("attribution", "skipped:未取"))
    assert _attribution_container("0803", empty, model_empty) is None


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


# --------------------------------------------------------------------------- #
# Round 2: leverage (human/machine ratio) + rework attribution
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_leverage_prices_one_typed_prompt(monkeypatch):
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [(86, 12, 3310.27, 38.49, 46.2, 17.7, 68.0)],
        ["prompts", "sessions", "cost_usd", "usd_per_prompt",
         "requests_per_prompt", "out_ktok_per_prompt", "avg_prompt_chars"]))
    monkeypatch.setattr(s, "clean_path", lambda name: _Exists())
    lev = s.fetch_leverage("2026-08-02")
    assert lev.health.state == "ok"
    assert lev.prompts == 86
    assert lev.usd_per_prompt == 38.49


@pytest.mark.unit
def test_leverage_skips_a_day_with_no_typing(monkeypatch):
    """Dividing by zero prompts is meaningless — omit rather than show 0."""
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [(0, 0, 0.0, 0.0, 0.0, 0.0, 0.0)],
        ["prompts", "sessions", "cost_usd", "usd_per_prompt",
         "requests_per_prompt", "out_ktok_per_prompt", "avg_prompt_chars"]))
    monkeypatch.setattr(s, "clean_path", lambda name: _Exists())
    assert s.fetch_leverage("2026-08-02").health.state != "ok"


@pytest.mark.unit
def test_leverage_degrades_when_source_absent(monkeypatch):
    monkeypatch.setattr(s, "clean_path", lambda name: _Missing())
    lev = s.fetch_leverage(None)
    assert lev.prompts == 0
    assert lev.health.state.startswith("skipped")


@pytest.mark.unit
def test_rework_drops_workspaces_below_min_sample(monkeypatch):
    """A rate over a handful of issues is noise wearing a percentage sign.

    Measured on the 7-day window: one workspace showed 0% across 22 issues,
    which reads as "healthy" but means "too few to tell". Small samples are
    dropped, not rendered.
    """
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("ws-big", 1138, 787, 69.2, 68493.0),
         ("ws-small", 22, 0, 0.0, 0.0)],
        ["workspace_id", "issues", "rework_issues", "rework_pct", "rework_ktok"]))
    monkeypatch.setattr(s, "clean_path", lambda name: _Exists())
    bundle = s.fetch_rework_by_workspace(None, min_issues=30)
    assert [i.label for i in bundle.items] == ["ws-big"]


@pytest.mark.unit
def test_rework_reports_insufficient_sample(monkeypatch):
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("ws-small", 5, 1, 20.0, 10.0)],
        ["workspace_id", "issues", "rework_issues", "rework_pct", "rework_ktok"]))
    monkeypatch.setattr(s, "clean_path", lambda name: _Exists())
    bundle = s.fetch_rework_by_workspace(None, min_issues=30)
    assert bundle.items == []
    assert "样本不足" in bundle.health.state


@pytest.mark.unit
def test_rework_uses_all_time_window_not_the_weekly_one():
    """Rework needs cancel-then-complete, which takes days to accumulate."""
    import ast
    import inspect

    from L5_apps.digest import app

    tree = ast.parse(inspect.getsource(app._fetch_sources))
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == "fetch_rework_by_workspace"):
            assert node.args and isinstance(node.args[0], ast.Constant), (
                "rework must be passed an explicit all-time (None) window, "
                "not the 7-day `since` used by spend attribution"
            )
            assert node.args[0].value is None
            return
    raise AssertionError("fetch_rework_by_workspace not wired")


# --------------------------------------------------------------------------- #
# Payload schema — the failure mode that hides itself
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_metric_values_are_numeric_not_formatted_strings():
    """MetricPayload.Item.value is a Double in the Swift schema.

    A formatted string ("$38.5") builds fine in Python and renders fine in any
    local inspection, but the app rejects it with schema.payload_decode_failed
    — and the push path logs only "card put exit 1". The card then silently
    disappears from the briefing while every local check still shows it. This
    was a real bug, caught only by reading the pushed briefing back.
    """
    from L5_apps.digest.aidash import _leverage_card

    lev = s.Leverage(prompts=86, usd_per_prompt=38.49, requests_per_prompt=46.2,
                     avg_prompt_chars=68, health=s.SourceHealth("leverage", "ok"))
    card = _leverage_card("0803", lev)
    assert card is not None
    for item in card.payload["items"]:
        assert isinstance(item["value"], (int, float)), (
            f"{item['label']}: value must be numeric for the Swift schema, "
            f"got {type(item['value']).__name__} ({item['value']!r})"
        )
        assert not isinstance(item["value"], bool)


@pytest.mark.unit
def test_leverage_card_omitted_when_unhealthy():
    from L5_apps.digest.aidash import _leverage_card

    assert _leverage_card("0803", None) is None
    assert _leverage_card("0803", s.Leverage.empty()) is None


# --------------------------------------------------------------------------- #
# Tool cross — the dimension hermes_tools could never provide
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_tool_cross_ranks_by_cost_per_call_not_volume(monkeypatch):
    """Raw call counts are what hermes_tools already showed, and they answered
    nothing ("terminal 2577 times" — so what). Ranking by tokens-per-call
    surfaces the tools that are individually expensive, which is actionable.
    """
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("terminal", 48451, 3838, 275.92, 5.7, 50.0),
         ("execute_code", 2113, 181, 25.06, 11.9, 0.0)],
        ["tool", "calls", "sessions", "mtokens", "ktok_per_call",
         "automated_pct"]))
    monkeypatch.setattr(s, "clean_path", lambda name: _Exists())
    bundle = s.fetch_tool_cross(None)
    # execute_code is 23x rarer than terminal but twice as heavy per call, so
    # it must outrank it.
    assert bundle.items[0].label.startswith("execute_code")
    assert bundle.items[0].value_text == "11.9 Ktok"


@pytest.mark.unit
def test_tool_cross_label_carries_automation_share(monkeypatch):
    """Cost and autonomy together say something neither says alone: an
    expensive tool at 0% automated is work still on me."""
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("write_file", 5825, 1773, 27.68, 4.8, 86.0)],
        ["tool", "calls", "sessions", "mtokens", "ktok_per_call",
         "automated_pct"]))
    monkeypatch.setattr(s, "clean_path", lambda name: _Exists())
    assert s.fetch_tool_cross(None).items[0].label == "write_file · 自动 86%"


@pytest.mark.unit
def test_tool_cross_drops_rare_tools(monkeypatch):
    """A per-call average over a handful of calls is noise."""
    monkeypatch.setattr(s.serve, "run_query", _FakeRows(
        [("common", 500, 50, 10.0, 5.0, 10.0),
         ("rare", 3, 1, 9.0, 3000.0, 0.0)],
        ["tool", "calls", "sessions", "mtokens", "ktok_per_call",
         "automated_pct"]))
    monkeypatch.setattr(s, "clean_path", lambda name: _Exists())
    labels = [i.label for i in s.fetch_tool_cross(None).items]
    assert any(x.startswith("common") for x in labels)
    assert not any(x.startswith("rare") for x in labels), (
        "a 3-call tool must not top the ranking on a meaningless average"
    )


@pytest.mark.unit
def test_tool_cross_degrades_when_source_absent(monkeypatch):
    monkeypatch.setattr(s, "clean_path", lambda name: _Missing())
    bundle = s.fetch_tool_cross(None)
    assert bundle.items == []
    assert bundle.health.state.startswith("skipped")
