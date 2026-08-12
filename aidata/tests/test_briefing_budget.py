"""build_briefing under the data-driven card policy (MY-1395).

Two behaviours are asserted here that no earlier test could:

  1. The briefing carries a `relationship` card ONLY when the underlying data is
     genuinely a 2×2-or-better matrix, and that card carries its evidence
     (sample size, window, metric definition, non-causal summary).
  2. The briefing obeys an information budget — a first screen a reader can
     finish in two minutes, a whole page in five — instead of appending every
     container that has data.

Both are pure-transform tests: `build_briefing` never touches a warehouse, so
the fixtures below are hand-built bundles rather than frozen captures.
"""

import pytest

from L5_apps.digest.aidash import Briefing, build_briefing
from L5_apps.digest.card_policy import FIRST_SCREEN_CARDS, MAX_ACTIONS, MAX_CARDS
from L5_apps.digest.sources import (
    AdoPrTrends, AiEfficiency, AutomationTrends, CardInterest, CardTypeStar,
    DigestSources, Leverage, ModelTier, MulticaTrends, NewsItem, NewsRadar,
    RankBundle, RankItem, RavenTrends, RelationshipCell, ReworkRelationship,
    Segment, SegmentBundle, SourceHealth,
)

from tests.test_digest_golden import (
    _FROZEN_ADO, _FROZEN_AUTOMATION, _FROZEN_MULTICA, _FROZEN_TRENDS,
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
- P1: 核查缓存命中
- P2: 清理旧分支
- P2: 更新 README

## 🗂 昨日汇总
- 昨日花费 $2699.44，请求 8273 次
- 开了 4 个 PR（合并 3 个）

## 🔍 可改良
- 昨日 $262 花在极小输出/大上下文
"""

MUST_SEE = "> 💡 点评: 成本回落但请求下滑"


def _matrix(rows: int, cols: int, *, sample: int = 12) -> ReworkRelationship:
    """A rework matrix with `rows` workspaces × `cols` root causes."""
    cells = [
        RelationshipCell(row=f"ws{r}", column=f"cause{c}",
                         value=float(1000 * (r + 1) * (c + 1)))
        for r in range(rows) for c in range(cols)
    ]
    return ReworkRelationship(cells, sample, "2026-07-03 → 2026-07-09",
                              SourceHealth("multica_run", "ok"))


def _sources(**kw) -> DigestSources:
    base = dict(raven=_FROZEN_TRENDS, multica=_FROZEN_MULTICA,
                ado=_FROZEN_ADO, automation=_FROZEN_AUTOMATION)
    base.update(kw)
    return DigestSources(**base)


def _empty_sources(**kw) -> DigestSources:
    empty: list = []
    base = dict(
        raven=RavenTrends(empty, empty, empty, empty, empty, empty, empty,
                          SourceHealth("raven", "error", "boom")),
        multica=MulticaTrends(empty, {}, SourceHealth("multica", "error")),
        ado=AdoPrTrends(empty, empty, SourceHealth("ado_pr", "skipped:未采集")),
        automation=AutomationTrends(empty, empty, empty,
                                    SourceHealth("state_db", "skipped:未采集")),
    )
    base.update(kw)
    return DigestSources(**base)


def _build(sources: DigestSources, md: str = FULL_MD) -> Briefing:
    return build_briefing(REPORT_DATE, sources, md, MUST_SEE)


def _rich_sources() -> DigestSources:
    """A day where every source is healthy and several containers hold 4–5 cards.

    The budget cannot be tested against a thin day: the default fixture
    publishes 6 cards, under every cap, so a briefing with no budget at all
    would pass. This one publishes 16 cards before trimming — enough that
    `AI 效能` (5 cards), `成本归因` (4) and `可改良` (2) alone overrun the
    10-card total, which is exactly the container-vs-card confusion the caps
    must catch.
    """
    ok = lambda name: SourceHealth(name, "ok")  # noqa: E731
    ranks = [RankItem("alpha", 3.0, "3"), RankItem("beta", 2.0, "2")]
    segments = [Segment("end_turn", 5.0, "good"), Segment("tool_use", 3.0, None)]
    return _sources(
        rework_relationship=_matrix(3, 3),
        ai_efficiency=AiEfficiency(
            cache=[("2026-07-08", 40.0), ("2026-07-09", 50.0)],
            cache_savings=[("2026-07-09", 12.0)], cache_health=ok("state_db"),
            rework=[("2026-W27", 9.0), ("2026-W28", 11.0)],
            rework_health=ok("multica_run"),
            failure=RankBundle(ranks, ok("multica_run")),
            quality=SegmentBundle(segments, ok("claude_jsonl")),
            planner_gap_count=3, planner_gap_health=ok("multica_comment")),
        tool_cross=RankBundle(ranks, ok("hermes_messages")),
        cost_by_project=RankBundle(ranks, ok("attribution")),
        model_by_project=RankBundle(ranks, ok("attribution")),
        leverage=Leverage(10, 4.0, 3.0, 120, ok("leverage")),
        rework_by_workspace=RankBundle(ranks, ok("multica_run")),
        app_focus=RankBundle(ranks, ok("gecko")),
        commit_by_repo=RankBundle(ranks, ok("local_git")),
        model_tier=ModelTier(segments, ok("state_db")),
        news_radar=NewsRadar(
            [NewsItem("hn", "t1", "u1", "s"), NewsItem("finance", "t2", "u2", "s")],
            ok("news")),
        card_interest=CardInterest([CardTypeStar("insight", 4)],
                                   ok("aidash_events")),
    )


def _untrimmed_containers(sources=None) -> list:
    """Every container the producers build, BEFORE the budget trims anything.

    Reads the same seam `build_briefing` uses, so the "does the fixture still
    overflow?" guard measures the real authored set rather than a hand-copied
    number that would rot.
    """
    from L5_apps.digest import aidash

    captured: list = []
    original = aidash._apply_budget

    def _spy(containers):
        captured.extend(containers)
        return original(containers)

    aidash._apply_budget = _spy
    try:
        _build(sources if sources is not None else _rich_sources())
    finally:
        aidash._apply_budget = original
    return captured


def _cards(b: Briefing) -> list:
    return [card for c in b.containers for card in c.cards]


def _first_screen_cards(b: Briefing) -> list:
    """The cards a reader sees before scrolling.

    Containers are the scanning unit, so the first screen is the cards of the
    leading containers that fit whole — never a container cut in half.
    """
    lead: list = []
    for container in b.containers:
        if len(lead) + len(container.cards) > FIRST_SCREEN_CARDS:
            break
        lead.extend(container.cards)
    return lead


def _of_type(b: Briefing, card_type: str) -> list:
    return [card for card in _cards(b) if card.type == card_type]


# --------------------------------------------------------------------------- #
# relationship: emitted only when the data is genuinely two-dimensional
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_two_by_two_matrix_emits_a_wide_heatmap_relationship():
    b = _build(_sources(rework_relationship=_matrix(2, 2)))
    cards = _of_type(b, "relationship")
    assert len(cards) == 1
    card = cards[0]
    assert card.size == "wide"
    assert card.payload["visualization"] == "heatmap"


@pytest.mark.unit
def test_relationship_payload_carries_its_evidence():
    """Constitution §Relationship visualization: sample size, window, and
    metric definition are required, and the summary must not claim causation."""
    card = _of_type(_build(_sources(rework_relationship=_matrix(2, 3))),
                    "relationship")[0]
    payload = card.payload
    assert payload["sampleSize"] == 12
    assert payload["timeWindow"] == "2026-07-03 → 2026-07-09"
    assert payload["metricDefinition"]
    assert payload["summary"]
    # Observation, never cause — the words that would assert one are absent.
    for banned in ("导致", "因为", "causes", "caused by", "because"):
        assert banned not in payload["summary"]


@pytest.mark.unit
def test_relationship_payload_matches_the_locked_heatmap_contract():
    """Only `cells` may be populated for a heatmap; axes are labeled; every
    value is finite. A mismatch is rejected app-side as
    schema.payload_decode_failed and the card silently vanishes."""
    payload = _of_type(_build(_sources(rework_relationship=_matrix(2, 2))),
                       "relationship")[0].payload
    assert payload["cells"]
    assert "points" not in payload and "slopes" not in payload
    assert payload["xAxis"]["label"] and payload["yAxis"]["label"]
    assert all(isinstance(c["value"], float) for c in payload["cells"])
    assert all(c["row"] and c["column"] for c in payload["cells"])


@pytest.mark.unit
def test_single_row_matrix_is_omitted_rather_than_drawn_thin():
    """One workspace is a ranking, not a relationship — drawing it as a matrix
    asserts a second dimension the data does not have."""
    b = _build(_sources(rework_relationship=_matrix(1, 3)))
    assert _of_type(b, "relationship") == []


@pytest.mark.unit
def test_single_column_matrix_is_omitted():
    assert _of_type(_build(_sources(rework_relationship=_matrix(3, 1))),
                    "relationship") == []


@pytest.mark.unit
def test_degraded_relationship_source_emits_no_card():
    degraded = ReworkRelationship([], 0, "",
                                  SourceHealth("multica_run", "error", "boom"))
    assert _of_type(_build(_sources(rework_relationship=degraded)),
                    "relationship") == []


@pytest.mark.unit
def test_relationship_with_zero_sample_size_is_omitted():
    """sampleSize >= 1 is a schema invariant; publishing 0 would be rejected."""
    bundle = ReworkRelationship(
        [RelationshipCell("ws0", "c0", 1.0), RelationshipCell("ws1", "c1", 2.0),
         RelationshipCell("ws0", "c1", 3.0), RelationshipCell("ws1", "c0", 4.0)],
        0, "7d", SourceHealth("multica_run", "ok"))
    assert _of_type(_build(_sources(rework_relationship=bundle)),
                    "relationship") == []


@pytest.mark.unit
def test_relationship_absent_from_default_sources():
    """The default bundle is skipped/empty, so an unwired pipeline is silent
    rather than emitting a hollow card."""
    assert _of_type(_build(_sources()), "relationship") == []


# --------------------------------------------------------------------------- #
# information budget (§design 3)
#
# These run against `_rich_sources()` — a day where EVERY source is healthy and
# several containers carry 4–5 cards each. That matters: the thin default
# fixture publishes 6 cards, which is under every cap, so it cannot tell a
# working budget from an absent one. The rich fixture publishes 16 cards before
# any trimming, which is what makes the assertions below load-bearing.
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_the_rich_fixture_actually_overflows_before_trimming():
    """Guard the guard: if the fixture stops overflowing, every budget test
    below silently becomes vacuous — passing because there was nothing to trim
    rather than because trimming works."""
    untrimmed = sum(len(c.cards) for c in _untrimmed_containers())
    assert untrimmed > MAX_CARDS, (
        f"fixture publishes only {untrimmed} cards before the budget; it can no "
        f"longer prove the {MAX_CARDS}-card cap"
    )


@pytest.mark.unit
def test_briefing_respects_the_total_card_budget():
    """The cap is on PUBLISHED CARDS, not containers. Counting containers lets
    three 5-card containers publish 15 cards while reporting 3 against a cap of
    10 — the reader's five minutes are spent on cards, not section headers."""
    assert len(_cards(_build(_rich_sources()))) <= MAX_CARDS


@pytest.mark.unit
def test_first_screen_card_count_is_bounded():
    """The first screen is a two-minute read, measured in cards.

    Deliberately NOT `len(cards[:N]) <= N` — that slices to the bound and then
    asserts it, so it holds for any briefing and proves nothing. The real
    question is how many cards the leading containers carry.
    """
    b = _build(_rich_sources())
    lead = _first_screen_cards(b)
    assert len(lead) <= FIRST_SCREEN_CARDS


@pytest.mark.unit
def test_first_screen_is_not_the_whole_briefing_on_a_rich_day():
    """On a day with plenty of data the first screen must be a genuine SUBSET —
    if it swallowed everything, the two-minute promise would be the five-minute
    one wearing a different name."""
    b = _build(_rich_sources())
    assert len(_first_screen_cards(b)) < len(_cards(b))


@pytest.mark.unit
def test_a_container_is_never_split_across_the_first_screen_boundary():
    """A container is the unit a reader scans; half of 成本归因 above the fold
    and half below explains nothing. So the first screen ends on a container
    boundary, which is why it can hold FEWER than 6 cards but never more."""
    b = _build(_rich_sources())
    lead = _first_screen_cards(b)
    consumed = 0
    for container in b.containers:
        if consumed >= len(lead):
            break
        consumed += len(container.cards)
    assert consumed == len(lead), "first screen cut a container in half"


@pytest.mark.unit
def test_overflow_drops_whole_containers_not_individual_cards():
    """Trimming keeps containers intact: a 5-card container is published whole
    or not at all, never as a 2-card stump the reader cannot interpret."""
    published = {c.id: len(c.cards) for c in _build(_rich_sources()).containers}
    authored = {c.id: len(c.cards) for c in _untrimmed_containers()}
    for container_id, count in published.items():
        assert count == authored[container_id], (
            "a published container lost cards; containers are all-or-nothing"
        )


@pytest.mark.unit
def test_the_overview_survives_the_budget_on_a_rich_day():
    """ADR-23: the overview is the one guaranteed card. A crowded day must not
    be able to crowd it out."""
    titles = [c.title for c in _build(_rich_sources()).containers]
    assert titles[0] == "总览"


@pytest.mark.unit
def test_the_cross_signal_survives_a_crowded_day():
    """§design 3: the first screen must carry at least one outcome × resource
    cross signal. It is the highest-value card on the board, so a busy day is
    exactly when it must not be the one that gets trimmed."""
    b = _build(_rich_sources())
    assert _of_type(b, "relationship"), "the cross signal was trimmed away"


@pytest.mark.unit
def test_actions_are_capped():
    todo = _of_type(_build(_sources()), "todoList")
    assert todo, "the markdown TODO section must still produce a card"
    assert len(todo[0].payload["items"]) <= MAX_ACTIONS


@pytest.mark.unit
def test_actions_are_capped_on_a_rich_day_too():
    todo = _of_type(_build(_rich_sources()), "todoList")
    assert todo, "actions must survive the budget — they are the point"
    assert len(todo[0].payload["items"]) <= MAX_ACTIONS


@pytest.mark.unit
def test_actions_keep_the_highest_priority_items_when_capped():
    items = _of_type(_build(_sources()), "todoList")[0].payload["items"]
    assert items[0]["priority"] == "high", "P0 must survive the cap"


@pytest.mark.unit
def test_missing_sources_still_produce_a_valid_overview():
    """ADR-23: a total data outage yields a real briefing, not an empty one."""
    b = _build(_empty_sources(), md="# AI 使用日报 2026-07-09\n\n## ⚡ Trending\n- 数据缺失\n")
    assert b.containers
    assert _of_type(b, "digest"), "the overview digest is always present"
    for card in _cards(b):
        assert card.payload
        if "items" in card.payload:
            assert len(card.payload["items"]) >= 1


@pytest.mark.unit
def test_budget_is_deterministic():
    a = _build(_sources(rework_relationship=_matrix(3, 3)))
    b = _build(_sources(rework_relationship=_matrix(3, 3)))
    assert [c.id for c in _cards(a)] == [c.id for c in _cards(b)]


@pytest.mark.unit
def test_containers_stay_non_empty_after_budget_trimming():
    """A container whose every card lost the budget must be dropped, not left
    as an empty frame."""
    b = _build(_sources(rework_relationship=_matrix(3, 3)))
    assert all(c.cards for c in b.containers)


@pytest.mark.unit
def test_container_order_is_preserved_after_trimming():
    b = _build(_sources(rework_relationship=_matrix(2, 2)))
    orders = [c.order for c in b.containers]
    assert orders == sorted(orders)


# --------------------------------------------------------------------------- #
# Identity — the budget selects containers, so their ids must be unique
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_every_container_slot_is_unique():
    """`container put` upserts on id, so two containers sharing one id means the
    second silently REPLACES the first in the app. 成本归因 and 卡型兴趣 collided
    on slot 11 (fixed with MY-1395); this is the sentinel that keeps them apart.

    Checked over the builders directly rather than one rendered briefing, since
    no single briefing necessarily emits every container.
    """
    import inspect
    import re

    from L5_apps.digest import aidash

    source = inspect.getsource(aidash)
    slots = re.findall(r"_cuid\(mmdd,\s*(\d+)\)", source)
    duplicates = {s for s in slots if slots.count(s) > 1}
    assert not duplicates, f"container id slots reused: {sorted(duplicates)}"


@pytest.mark.unit
def test_every_card_slot_is_unique():
    import inspect
    import re

    from L5_apps.digest import aidash

    slots = re.findall(r"_kuid\(mmdd,\s*(\d+)\)", inspect.getsource(aidash))
    duplicates = {s for s in slots if slots.count(s) > 1}
    assert not duplicates, f"card id slots reused: {sorted(duplicates)}"
