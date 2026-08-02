"""Tests for the M2 '今日工作' card (goal ① 做了什么, per-project effort)."""

import pytest

from L5_apps.digest.aidash import _work_container
from L5_apps.digest.sources import WorkByProject, ProjectWork, SourceHealth


def _work(projects, state="ok"):
    return WorkByProject(projects, SourceHealth("work", state))


def _p(name, turns, ktok=0.0, sessions=1):
    return ProjectWork(name, turns, ktok, sessions)


@pytest.mark.unit
def test_container_has_metric_card_per_project():
    w = _work([_p("VitalStride", 538, 274.0, 14),
               _p("WorkspaceA", 422, 401.6, 4),
               _p("AIDash", 24, 36.0, 1)])
    c = _work_container("0717", w)
    assert c is not None
    assert c.title == "今日工作"
    assert c.order == 15
    assert len(c.cards) == 1
    card = c.cards[0]
    assert card.type == "metric"
    items = card.payload["items"]
    assert [i["label"] for i in items] == ["VitalStride", "WorkspaceA", "AIDash"]
    assert items[0]["value"] == 538
    assert items[0]["unit"] == "turns"
    assert "14 会话" in items[0]["context"]


@pytest.mark.unit
def test_container_caps_at_six_projects():
    w = _work([_p(f"P{i}", 100 - i) for i in range(10)])
    c = _work_container("0717", w)
    assert len(c.cards[0].payload["items"]) == 6


@pytest.mark.unit
def test_context_omits_ktok_when_tiny():
    c = _work_container("0717", _work([_p("X", 5, 0.3, 2)]))
    ctx = c.cards[0].payload["items"][0]["context"]
    assert ctx == "2 会话"          # no "k out" when <1k


@pytest.mark.unit
def test_none_when_no_projects():
    assert _work_container("0717", _work([])) is None


@pytest.mark.unit
def test_none_when_degraded():
    assert _work_container("0717", _work([_p("X", 1)], state="error")) is None


@pytest.mark.unit
def test_none_when_work_is_none():
    assert _work_container("0717", None) is None
