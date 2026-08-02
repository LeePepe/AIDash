"""Unit tests for the GitHub tool-radar → trending-card transform (aidash.py).

Pure transform only (no push): proves tier-splitting into trending cards, the
new optional delta/category item fields, the topic heuristic, and the
degrade-to-no-container path. RepoCards are hand-built, so no query/LLM.
"""

import pytest

from L5_apps.digest.aidash import _radar_containers, _radar_item, _radar_topic
from L5_apps.digest.repo_radar import RepoCard, TIER_NOW, TIER_HORIZON
from L5_apps.digest.sources import RepoRadar, SourceHealth


def _card(repo, stars, tier, *, delta=None, category="", project=None, reason=""):
    return RepoCard(
        repo=repo, stars=stars, star_delta=delta, description="d",
        language="Python", topics=(), url=f"https://github.com/{repo}",
        provenance="curated", category=category, tier=tier,
        related_project=project, reason=reason)


def _radar(cards):
    return RepoRadar(cards, SourceHealth("github_repo", "ok"))


MMDD = "0718"


@pytest.mark.unit
def test_splits_into_one_card_per_tier():
    radar = _radar([
        _card("a/now", 100, TIER_NOW),
        _card("b/horizon", 50, TIER_HORIZON),
    ])
    containers = _radar_containers(MMDD, radar)
    assert len(containers) == 1
    cont = containers[0]
    assert cont.title == "GitHub 工具雷达"
    assert cont.order == 60
    assert [c.type for c in cont.cards] == ["trending", "trending"]
    # now card first (accent), horizon second (neutral)
    assert cont.cards[0].style == "accent"
    assert cont.cards[1].style == "neutral"
    assert cont.cards[0].payload["topic"].startswith("值得现在看")
    assert cont.cards[1].payload["topic"].startswith("拓展视野")


@pytest.mark.unit
def test_item_carries_delta_and_category():
    item = _radar_item(_card("a/b", 100, TIER_NOW, delta=42, category="AI-agent",
                             reason="与 Financial 项目直接相关"))
    assert item["title"] == "a/b"
    assert item["url"] == "https://github.com/a/b"
    assert item["score"] == 100.0
    assert item["delta"] == 42.0
    assert item["category"] == "AI-agent"
    assert item["reason"] == "与 Financial 项目直接相关"


@pytest.mark.unit
def test_item_omits_reason_when_empty():
    item = _radar_item(_card("a/b", 100, TIER_NOW))
    assert "reason" not in item  # no LLM reason → clean payload, no empty key


@pytest.mark.unit
def test_item_omits_delta_when_none():
    item = _radar_item(_card("a/b", 100, TIER_NOW, delta=None))
    assert "delta" not in item  # day-1 snapshot: no fake 0


@pytest.mark.unit
def test_only_present_tier_yields_one_card():
    radar = _radar([_card("a/now", 100, TIER_NOW)])
    cont = _radar_containers(MMDD, radar)[0]
    assert len(cont.cards) == 1
    assert cont.cards[0].payload["topic"].startswith("值得现在看")


@pytest.mark.unit
def test_degraded_radar_yields_no_container():
    assert _radar_containers(MMDD, None) == []
    assert _radar_containers(MMDD, RepoRadar([], SourceHealth("github_repo", "error"))) == []
    assert _radar_containers(MMDD, RepoRadar([], SourceHealth("github_repo", "ok"))) == []


@pytest.mark.unit
def test_topic_appends_project_only_when_dominant():
    cards = [_card("a", 1, TIER_NOW, project="Financial"),
             _card("b", 1, TIER_NOW, project="Financial"),
             _card("c", 1, TIER_NOW, project=None)]
    assert _radar_topic("值得现在看", cards) == "值得现在看 · 多关联 Financial"


@pytest.mark.unit
def test_topic_stays_plain_when_projects_diverse():
    cards = [_card("a", 1, TIER_NOW, project="Financial"),
             _card("b", 1, TIER_NOW, project="AIDash"),
             _card("c", 1, TIER_NOW, project="Skills")]
    assert _radar_topic("值得现在看", cards) == "值得现在看"


@pytest.mark.unit
def test_items_keep_stars_desc_order_from_query():
    # The L4 query already sorts stars-desc; the transform must not reorder.
    radar = _radar([
        _card("big", 900, TIER_NOW),
        _card("small", 10, TIER_NOW),
    ])
    cont = _radar_containers(MMDD, radar)[0]
    scores = [it["score"] for it in cont.cards[0].payload["items"]]
    assert scores == [900.0, 10.0]
