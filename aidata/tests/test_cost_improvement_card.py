"""Tests for the M1 cost-improvement card (real-data '可改良·成本').

Covers the pure body renderer and the container wiring, using synthetic
CostImprovement bundles — no warehouse access.
"""

import pytest

from L5_apps.digest.aidash import _cost_improvement_body, _prose_containers
from L5_apps.digest.sources import CostImprovement, ModelSpend, SourceHealth


def _ci(top, waste=0.0, reqs=0, state="ok"):
    return CostImprovement(
        top_models=top, downgrade_usd=waste, downgrade_requests=reqs,
        health=SourceHealth("cost", state),
    )


@pytest.mark.unit
def test_body_renders_concentration_and_downgrade():
    ci = _ci(
        [ModelSpend("claude-opus-4-6", 39839.34, 38.9),
         ModelSpend("claude-opus-4-8", 24177.38, 23.6),
         ModelSpend("claude-opus-4-7", 13316.79, 13.0)],
        waste=3403.0, reqs=17457,
    )
    body = _cost_improvement_body(ci)
    assert "claude-opus-4-6" in body
    assert "39%" in body            # lead model pct
    assert "76%" in body            # top-3 sum
    assert "$3403" in body          # spend involved (not an asserted saving)
    assert "17457" in body
    # research 2026-07-18: must NOT assert a guaranteed saving (overthinking tax)
    assert "可省" not in body
    assert "核查" in body           # neutral "worth checking" framing
    # plain text, no markdown markers
    for line in body.splitlines():
        assert not line.lstrip().startswith(("- ", "#", ">"))


@pytest.mark.unit
def test_body_omits_downgrade_line_when_zero():
    ci = _ci([ModelSpend("gpt-5.5", 100.0, 90.0)], waste=0.0, reqs=0)
    body = _cost_improvement_body(ci)
    assert "gpt-5.5" in body
    assert "可省" not in body       # no downgrade line when nothing to save


@pytest.mark.unit
def test_body_empty_when_no_models():
    assert _cost_improvement_body(_ci([])) == ""


@pytest.mark.unit
def test_body_empty_when_degraded():
    ci = _ci([ModelSpend("x", 1.0, 1.0)], state="error")
    assert _cost_improvement_body(ci) == ""


@pytest.mark.unit
def test_body_empty_when_none():
    assert _cost_improvement_body(None) == ""


@pytest.mark.unit
def test_prose_container_adds_cost_card_when_data_present():
    ci = _ci([ModelSpend("claude-opus-4-6", 100.0, 39.0)], waste=50.0, reqs=10)
    containers = _prose_containers("0714", {"可改良": ["旧文案"]}, cost_improvement=ci)
    improve = [c for c in containers if c.title == "可改良"]
    assert improve, "可改良 container should exist"
    types_titles = [(card.type, card.payload.get("title")) for card in improve[0].cards]
    # real-data cost card comes first, markdown 可改良 second
    assert ("insight", "可改良·成本") in types_titles
    assert ("insight", "可改良") in types_titles
    assert types_titles[0][1] == "可改良·成本"


@pytest.mark.unit
def test_prose_container_cost_card_alone_when_no_markdown():
    ci = _ci([ModelSpend("claude-opus-4-6", 100.0, 39.0)], waste=50.0, reqs=10)
    containers = _prose_containers("0714", {}, cost_improvement=ci)
    improve = [c for c in containers if c.title == "可改良"]
    assert improve
    assert [card.payload["title"] for card in improve[0].cards] == ["可改良·成本"]


@pytest.mark.unit
def test_prose_container_absent_when_nothing():
    containers = _prose_containers("0714", {}, cost_improvement=_ci([]))
    assert not [c for c in containers if c.title == "可改良"]
