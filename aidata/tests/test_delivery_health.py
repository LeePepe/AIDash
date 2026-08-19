"""Hermetic tests for separated content-source vs delivery/XPC health (MY-1450).

The pre-fix contradiction: all content sources report OK while delivery (XPC)
is degraded — the user sees "数据源健康: raven✅ multica✅ …" and reasonably
infers end-to-end success, but the briefing never reached the app.

After the fix:
  - Content-source health and delivery/XPC health are reported in separate
    labeled outputs.
  - Delivery state is persisted with timestamp/freshness semantics.
  - A degraded delivery does not mask or imply overall success.
"""

from __future__ import annotations

import pytest

from L5_apps.digest.aidash import (
    DeliveryState, PushResult,
    build_briefing, delivery_health_line,
    save_delivery_state, load_delivery_state,
)
from L5_apps.digest.render import render_digest


# --- Fixtures ----------------------------------------------------------------

def _minimal_raven_trends():
    """A minimal healthy RavenTrends stub for testing."""
    from L5_apps.digest.sources import RavenTrends, SourceHealth
    health = SourceHealth(name="raven", state="ok")
    empty: list[tuple[str, float]] = []
    return RavenTrends(
        health=health,
        cost=empty,
        tokens=empty,
        requests=empty,
        waste=empty,
        sessions=empty,
        pipeline_completed=empty,
        pipeline_cancelled=empty,
    )


def _minimal_full_md():
    """Minimal rendered markdown with a healthy source-health line."""
    return (
        "# AI 使用日报 2026-08-18\n\n"
        "> 数据源: raven✅ multica✅ ADO✅ state.db✅\n\n"
        "## ⚡ Trending\n- 成本: $0 → vs 昨 $0\n\n"
        "## 📌 TODO\n- 无\n\n"
        "## 📝 昨日汇总\n- 无\n\n"
        "## 🔧 可改良\n- 无\n"
    )


# --- Test: pre-fix contradiction (regression guard) --------------------------

@pytest.mark.unit
def test_prefix_contradiction_sources_ok_but_delivery_degraded():
    """CORE REGRESSION TEST: all sources OK + XPC unavailable.

    Pre-fix: the overview card only showed "数据源健康: raven✅ …" with NO
    delivery signal — implying end-to-end success.

    Post-fix: a separate "投递健康" card surfaces the XPC failure.
    """
    delivery = DeliveryState(
        ok=False,
        reason="AIDash XPC not reachable",
        timestamp="2026-08-19T04:01:00Z",
    )
    briefing = build_briefing(
        "2026-08-19", _minimal_raven_trends(), _minimal_full_md(),
        must_see="", delivery=delivery,
    )
    overview = briefing.containers[0]
    # There must be both a "数据源健康" AND a "投递健康" card.
    titles = [c.payload.get("title") for c in overview.cards]
    assert "数据源健康" in titles, "content-source health card must be present"
    assert "投递健康" in titles, "delivery health card must surface XPC failure"

    # Verify the delivery card body mentions XPC failure.
    delivery_card = next(c for c in overview.cards if c.payload.get("title") == "投递健康")
    assert "XPC" in delivery_card.payload["body"]
    assert "⚠️" in delivery_card.payload["body"] or "not reachable" in delivery_card.payload["body"]


@pytest.mark.unit
def test_no_delivery_card_when_delivery_ok():
    """When delivery is healthy, no extra delivery card pollutes the overview."""
    delivery = DeliveryState(ok=True, reason="", timestamp="2026-08-19T04:01:00Z")
    briefing = build_briefing(
        "2026-08-19", _minimal_raven_trends(), _minimal_full_md(),
        must_see="", delivery=delivery,
    )
    overview = briefing.containers[0]
    titles = [c.payload.get("title") for c in overview.cards]
    assert "投递健康" not in titles


@pytest.mark.unit
def test_no_delivery_card_when_delivery_none():
    """First run (no delivery state ever persisted) shows no delivery card."""
    briefing = build_briefing(
        "2026-08-19", _minimal_raven_trends(), _minimal_full_md(),
        must_see="", delivery=None,
    )
    overview = briefing.containers[0]
    titles = [c.payload.get("title") for c in overview.cards]
    assert "投递健康" not in titles


# --- Test: delivery_health_line() --------------------------------------------

@pytest.mark.unit
def test_delivery_health_line_ok():
    state = DeliveryState(ok=True, timestamp="2026-08-19T04:00:00Z")
    line = delivery_health_line("2026-08-19", state)
    assert "XPC✅" in line
    assert "投递" in line


@pytest.mark.unit
def test_delivery_health_line_degraded():
    state = DeliveryState(ok=False, reason="AIDash XPC not reachable",
                          timestamp="2026-08-19T04:00:00Z")
    line = delivery_health_line("2026-08-19", state)
    assert "XPC⚠️" in line
    assert "投递" in line


@pytest.mark.unit
def test_delivery_health_line_stale():
    """A delivery state older than 36h is marked stale."""
    state = DeliveryState(ok=True, timestamp="2026-08-17T01:00:00Z")
    line = delivery_health_line("2026-08-19", state)
    assert "stale" in line


@pytest.mark.unit
def test_delivery_health_line_none():
    """No delivery state → empty string (no line rendered)."""
    assert delivery_health_line("2026-08-19", None) == ""


# --- Test: render_digest includes delivery line ------------------------------

@pytest.mark.unit
def test_render_digest_includes_delivery_line_when_degraded():
    delivery = DeliveryState(ok=False, reason="AIDash XPC not reachable",
                             timestamp="2026-08-19T04:00:00Z")
    md = render_digest(_minimal_raven_trends(), "2026-08-19", delivery=delivery)
    assert "> 投递:" in md
    assert "XPC⚠️" in md


@pytest.mark.unit
def test_render_digest_includes_delivery_ok():
    delivery = DeliveryState(ok=True, timestamp="2026-08-19T04:00:00Z")
    md = render_digest(_minimal_raven_trends(), "2026-08-19", delivery=delivery)
    assert "> 投递:" in md
    assert "XPC✅" in md


@pytest.mark.unit
def test_render_digest_no_delivery_line_when_none():
    md = render_digest(_minimal_raven_trends(), "2026-08-19", delivery=None)
    assert "> 投递:" not in md


# --- Test: save/load delivery state ------------------------------------------

@pytest.mark.unit
def test_save_and_load_delivery_state(tmp_path, monkeypatch):
    """Round-trip: save then load produces equivalent DeliveryState."""
    state_file = tmp_path / "state.json"
    monkeypatch.setattr("config.STATE_FILE", state_file)

    result = PushResult(ok=False, reason="AIDash XPC not reachable")
    saved = save_delivery_state(result, now=lambda: "2026-08-19T04:01:00Z")

    assert saved.ok is False
    assert saved.reason == "AIDash XPC not reachable"
    assert saved.timestamp == "2026-08-19T04:01:00Z"

    loaded = load_delivery_state()
    assert loaded is not None
    assert loaded.ok is False
    assert loaded.reason == "AIDash XPC not reachable"
    assert loaded.timestamp == "2026-08-19T04:01:00Z"


@pytest.mark.unit
def test_load_delivery_state_returns_none_when_empty(tmp_path, monkeypatch):
    """No state file → None."""
    state_file = tmp_path / "state.json"
    monkeypatch.setattr("config.STATE_FILE", state_file)
    assert load_delivery_state() is None


# --- Test: XPC unavailable does not block local digest generation -------------

@pytest.mark.unit
def test_xpc_unavailable_allows_local_digest():
    """A degraded delivery state does not prevent build_briefing from producing
    a valid briefing — the overview card is always present (ADR-23)."""
    delivery = DeliveryState(ok=False, reason="AIDash XPC not reachable",
                             timestamp="2026-08-19T04:01:00Z")
    briefing = build_briefing(
        "2026-08-19", _minimal_raven_trends(), _minimal_full_md(),
        must_see="", delivery=delivery,
    )
    # Must still produce a valid briefing with at least the overview.
    assert briefing.date == "2026-08-18"
    assert len(briefing.containers) >= 1
    assert briefing.containers[0].title == "总览"
