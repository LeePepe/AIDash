"""L5 briefing ordering and information-budget contract tests."""

import pytest

from L5_apps.digest.aidash import (
    Briefing,
    Card,
    Container,
    _apply_budget,
    build_briefing,
)
from L5_apps.digest.card_policy import (
    FIRST_SCREEN_CARDS,
    MAX_CARDS,
    OVERVIEW_KPI_LIMIT,
)
from L5_apps.digest.sources import DigestSources
from tests.test_digest_golden import (
    _FROZEN_ADO,
    _FROZEN_AUTOMATION,
    _FROZEN_MULTICA,
    _FROZEN_TRENDS,
)


REPORT_DATE = "2026-07-10"
FULL_MD = """# AI 使用日报 2026-07-09

> 💡 点评: 成本回落但请求下滑

> 数据源: raven✅ multica✅ ADO✅ state.db✅

## ⚡ Trending
- 成本: 2699$ ↑(+24%) vs 昨 2180$
- 会话数: 76 ↑(+300%) vs 昨 19

## 📅 今日 TODO
- P0: 查 pipeline 取消率
- P1: 降级 opus 用量

## 🗂 昨日汇总
- 昨日花费 $2699.44，请求 8273 次
"""


@pytest.fixture
def sources() -> DigestSources:
    return DigestSources(
        raven=_FROZEN_TRENDS,
        multica=_FROZEN_MULTICA,
        ado=_FROZEN_ADO,
        automation=_FROZEN_AUTOMATION,
    )


def _build(sources: DigestSources) -> Briefing:
    return build_briefing(
        REPORT_DATE,
        sources,
        FULL_MD,
        "> 💡 点评: 成本回落但请求下滑",
    )


def _cards(briefing: Briefing) -> list[Card]:
    return [card for container in briefing.containers for card in container.cards]


@pytest.mark.unit
def test_overview_is_a_bounded_kpi_grid_followed_by_the_focal_digest(sources):
    overview = _build(sources).containers[0]
    assert (overview.title, overview.order, overview.layout) == ("总览", 10, "grid")
    kpis = [card for card in overview.cards if card.type == "metric"]
    assert 1 <= len(kpis) <= OVERVIEW_KPI_LIMIT
    assert all(card.size in {"small", "medium"} for card in kpis)
    assert all(len(card.payload["items"]) == 1 for card in kpis)
    digest_index = next(
        index for index, card in enumerate(overview.cards) if card.type == "digest"
    )
    assert all(card.type == "metric" for card in overview.cards[:digest_index])


@pytest.mark.unit
def test_reading_flow_uses_overview_action_context_and_support_bands(sources):
    briefing = _build(sources)
    assert [container.order for container in briefing.containers] == sorted(
        container.order for container in briefing.containers
    )
    assert briefing.containers[0].order == 10
    for container in briefing.containers:
        if container.title in {"今日工作", "今日规划", "昨日汇总"}:
            assert 20 <= container.order <= 40
        elif container.title in {"24h 证据时间线", "交叉信号", "工程与编排图表",
                                 "时间与产出", "AI 效能"}:
            assert 50 <= container.order <= 70
        elif container.title not in {"总览"}:
            assert container.order >= 80 or container.title == "今日规划"


@pytest.mark.unit
def test_briefing_budget_counts_cards_and_keeps_containers_whole(sources):
    briefing = _build(sources)
    assert len(_cards(briefing)) <= MAX_CARDS
    assert all(container.cards for container in briefing.containers)
    overview_cards = len(briefing.containers[0].cards)
    assert overview_cards <= FIRST_SCREEN_CARDS


@pytest.mark.unit
def test_budget_preserves_authored_reading_order_after_selection():
    def container(name: str, order: int, count: int) -> Container:
        return Container(
            name,
            name,
            order,
            tuple(
                Card(f"{name}-{index}", "insight", "wide", {"body": name})
                for index in range(count)
            ),
        )

    published = _apply_budget([
        container("总览", 10, 2),
        container("action", 20, 2),
        container("context", 55, 2),
        container("support", 80, 2),
    ])
    assert [item.title for item in published] == [
        "总览", "action", "context", "support",
    ]
    assert [item.order for item in published] == [10, 20, 55, 80]


@pytest.mark.unit
def test_overview_kpi_labels_are_concise_and_not_a_second_mega_card(sources):
    overview = _build(sources).containers[0]
    labels = [
        card.payload["items"][0]["label"]
        for card in overview.cards
        if card.type == "metric"
    ]
    assert labels
    assert all(len(label) <= 8 for label in labels)
    assert all(len(card.payload["items"]) == 1
               for card in overview.cards if card.type == "metric")
