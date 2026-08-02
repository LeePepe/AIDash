"""Tests for the M1 '值不值·效率' card (research-backed, not a naive ratio).

Covers the pure body renderer + container wiring with synthetic
ValueEfficiency bundles — no warehouse access.
"""

import pytest

from L5_apps.digest.aidash import _value_efficiency_body, _prose_containers
from L5_apps.digest.sources import ValueEfficiency, SourceHealth


def _ve(cpt=61.0, share=0.42, cost=13159.0, tasks=215, days=7, state="ok"):
    return ValueEfficiency(
        total_cost=cost, completed_tasks=tasks,
        cost_per_completed_task=cpt, output_share_pct=share,
        window_days=days, health=SourceHealth("efficiency", state),
    )


@pytest.mark.unit
def test_body_renders_both_metrics():
    body = _value_efficiency_body(_ve())
    assert "$61" in body
    assert "215" in body
    assert "含失败" in body           # honest: includes failed-task spend
    assert "0.4%" in body
    assert "input 主导" in body or "上下文" in body
    # observation framing, not a verdict — no "值得/应该" imperatives asserted
    for line in body.splitlines():
        assert not line.lstrip().startswith(("- ", "#", ">"))


@pytest.mark.unit
def test_body_window_label_reflects_days():
    body = _value_efficiency_body(_ve(days=14))
    assert "近 14 天" in body


@pytest.mark.unit
def test_body_omits_missing_metric():
    body = _value_efficiency_body(_ve(cpt=None))
    assert "每完成任务" not in body   # cost-per-task line skipped
    assert "输出 token" in body       # output share still shown


@pytest.mark.unit
def test_body_empty_when_both_missing():
    assert _value_efficiency_body(_ve(cpt=None, share=None)) == ""


@pytest.mark.unit
def test_body_empty_when_degraded():
    assert _value_efficiency_body(_ve(state="error")) == ""


@pytest.mark.unit
def test_body_empty_when_none():
    assert _value_efficiency_body(None) == ""


@pytest.mark.unit
def test_prose_container_value_card_comes_first():
    from L5_apps.digest.sources import CostImprovement, ModelSpend
    ci = CostImprovement(
        [ModelSpend("claude-opus-4-6", 100.0, 39.0)], 50.0, 10,
        SourceHealth("cost", "ok"))
    containers = _prose_containers(
        "0714", {"可改良": ["旧文案"]},
        cost_improvement=ci, value_efficiency=_ve())
    improve = [c for c in containers if c.title == "可改良"][0]
    titles = [card.payload["title"] for card in improve.cards]
    # value/efficiency first, then cost, then markdown
    assert titles == ["值不值·效率", "可改良·成本", "可改良"]


@pytest.mark.unit
def test_prose_container_value_card_alone():
    containers = _prose_containers("0714", {}, value_efficiency=_ve())
    improve = [c for c in containers if c.title == "可改良"]
    assert improve
    assert [c.payload["title"] for c in improve[0].cards] == ["值不值·效率"]
