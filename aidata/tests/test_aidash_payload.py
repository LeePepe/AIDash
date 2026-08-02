"""Unit tests for the AIDash payload transform (pure half of aidash.py).

BUG 1 (metric card + sparkline series), BUG 2 (plain-text bodies, no markdown),
and BUG 3 (briefing keyed on the reported day) are all covered here. The frozen
source snapshot is shared with the golden test so the numbers are representative.
"""

import pytest

from L5_apps.digest.aidash import (
    Briefing, Container, Card, build_briefing, parse_sections,
)
from L5_apps.digest.sources import (
    DigestSources, RavenTrends, MulticaTrends, AdoPrTrends, AutomationTrends,
    SourceHealth,
)

from tests.test_digest_golden import (
    _FROZEN_TRENDS, _FROZEN_MULTICA, _FROZEN_ADO, _FROZEN_AUTOMATION,
)

# report_date is the RUN date; it reports on the CST day before (2026-07-09),
# which is the day present in the frozen fixtures.
REPORT_DATE = "2026-07-10"
REPORTED_DAY = "2026-07-09"

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
- 开了 4 个 PR（合并 3 个）

## 🔍 可改良
- 昨日 $262 花在极小输出/大上下文
"""

MUST_SEE = "> 💡 点评: 成本回落但请求下滑\n\n## ⚡ Trending\n- 成本: 2699$ ↑"


@pytest.fixture
def sources() -> DigestSources:
    return DigestSources(
        raven=_FROZEN_TRENDS, multica=_FROZEN_MULTICA,
        ado=_FROZEN_ADO, automation=_FROZEN_AUTOMATION,
    )


def _build(sources: DigestSources, full_md: str = FULL_MD,
           must_see: str = MUST_SEE) -> Briefing:
    return build_briefing(REPORT_DATE, sources, full_md, must_see)


def _cards_by_type(b: Briefing) -> dict[str, Card]:
    out = {}
    for c in b.containers:
        for card in c.cards:
            out[card.type] = card
    return out


@pytest.mark.unit
def test_parse_sections_splits_headings():
    sections = parse_sections(FULL_MD)
    assert any("Trending" in h for h in sections)
    assert any("今日 TODO" in h for h in sections)


@pytest.mark.unit
def test_build_briefing_maps_sections_to_cards(sources):
    b = _build(sources)
    assert isinstance(b, Briefing)
    types = _cards_by_type(b)
    assert "digest" in types      # 总览
    assert "metric" in types      # 趋势指标 (BUG 1: metric, not trending)
    assert "todoList" in types    # 今日规划
    assert "insight" in types     # 昨日汇总 / 可改良


@pytest.mark.unit
def test_trends_use_metric_card_not_trending(sources):
    """BUG 1: numeric trends must map to a `metric` card, never `trending`."""
    types = _cards_by_type(_build(sources))
    assert "metric" in types
    assert "trending" not in types


@pytest.mark.unit
def test_metric_items_carry_chronological_series(sources):
    """Every metric Item has a value + a sparkline series oldest→newest."""
    metric = _cards_by_type(_build(sources))["metric"]
    items = metric.payload["items"]
    assert len(items) >= 1
    cost = next(i for i in items if i["label"] == "成本")
    assert "series" in cost and len(cost["series"]) >= 2
    # chronological (oldest→newest): the last point is today's value.
    assert cost["series"][-1] == pytest.approx(2699.44)  # 2026-07-09 value
    # all plain floats
    assert all(isinstance(v, float) for v in cost["series"])
    assert cost["value"] == pytest.approx(2699.44)


@pytest.mark.unit
def test_metric_series_is_oldest_to_newest(sources):
    """The last two cost points are 2026-07-08 then 2026-07-09 (left→right)."""
    metric = _cards_by_type(_build(sources))["metric"]
    cost = next(i for i in metric.payload["items"] if i["label"] == "成本")
    assert cost["series"][-2] == pytest.approx(2180.19)  # 07-08
    assert cost["series"][-1] == pytest.approx(2699.44)  # 07-09 (newest)


@pytest.mark.unit
def test_metric_trend_and_higher_is_better(sources):
    items = _cards_by_type(_build(sources))["metric"].payload["items"]
    cost = next(i for i in items if i["label"] == "成本")
    assert cost["trend"] in ("up", "down", "flat")
    assert cost["trend"] == "up"           # 2699 > 2180
    assert cost["unit"] == "$"
    assert cost["higherIsBetter"] is False  # cost down is good
    sessions = next(i for i in items if i["label"] == "会话数")
    assert sessions["higherIsBetter"] is True


@pytest.mark.unit
def test_automation_ratio_is_ring_gauge(sources):
    """自动化占比 → ratio in 0..1 (ring gauge), not a sparkline series."""
    items = _cards_by_type(_build(sources))["metric"].payload["items"]
    ratio_item = next(i for i in items if i["label"] == "自动化占比")
    assert "ratio" in ratio_item
    assert 0.0 <= ratio_item["ratio"] <= 1.0
    assert ratio_item["ratio"] == pytest.approx(0.71)  # 2026-07-09
    assert "series" not in ratio_item


@pytest.mark.unit
def test_every_ratio_within_zero_one(sources):
    """Contract: each metric Item's ratio, when present, is within 0..1."""
    items = _cards_by_type(_build(sources))["metric"].payload["items"]
    for i in items:
        if "ratio" in i:
            assert 0.0 <= i["ratio"] <= 1.0


@pytest.mark.unit
def test_digest_body_is_plain_text_no_markdown(sources):
    """BUG 2: the digest overview body must be clean prose — no ##/- /> ."""
    digest = _cards_by_type(_build(sources))["digest"]
    body = digest.payload["body"]
    assert "##" not in body
    assert "\n- " not in body
    assert not body.lstrip().startswith("#")
    assert not body.lstrip().startswith("- ")
    assert not body.lstrip().startswith("> ")
    assert digest.size == "hero"
    assert body  # non-empty


@pytest.mark.unit
def test_digest_carries_real_data_sections(sources):
    """The digest hero card must carry ≥2 real-data sections so the AIDash app
    keeps it at hero (sections>=2 ⇒ hero) instead of downgrading a body-only
    card to small — whose layout renders only the title and looks empty."""
    digest = _cards_by_type(_build(sources))["digest"]
    sections = digest.payload.get("sections")
    assert sections, "digest must have sections"
    assert len(sections) >= 2
    headings = [s["heading"] for s in sections]
    assert "昨日概况" in headings
    assert "趋势要点" in headings
    # sections carry real content, clean of markdown markers
    for s in sections:
        assert s["paragraphs"]
        for p in s["paragraphs"]:
            assert not p.lstrip().startswith("- ")
            assert not p.lstrip().startswith(">")
    # 昨日概况 mirrors the 昨日汇总 lines (real data, not padding)
    overview = next(s for s in sections if s["heading"] == "昨日概况")
    assert any("花费" in p or "请求" in p for p in overview["paragraphs"])
    # 趋势要点 surfaces cost as the lead signal
    trend = next(s for s in sections if s["heading"] == "趋势要点")
    assert any(p.startswith("成本") for p in trend["paragraphs"])


@pytest.mark.unit
def test_digest_sections_empty_when_no_source_sections():
    """A degraded digest (no 昨日汇总/Trending) stays section-less, not crashing."""
    from L5_apps.digest.aidash import _overview_sections
    assert _overview_sections({"": []}) == []


@pytest.mark.unit
def test_insight_bodies_have_no_markdown(sources):
    """BUG 2: insight card bodies (昨日汇总/可改良/健康) carry no markdown syntax."""
    b = _build(sources)
    for c in b.containers:
        for card in c.cards:
            body = card.payload.get("body", "")
            for line in body.splitlines():
                assert not line.lstrip().startswith("#")
                assert not line.lstrip().startswith("- ")
                assert not line.lstrip().startswith("> ")


@pytest.mark.unit
def test_briefing_keyed_on_reported_day(sources):
    """BUG 3: date/title/UUIDs key on the reported day, not the run date."""
    b = _build(sources)
    assert b.date == REPORTED_DAY
    digest = _cards_by_type(b)["digest"]
    assert REPORTED_DAY in digest.payload["title"]
    assert REPORT_DATE not in digest.payload["title"]
    # UUID mmdd segment reflects the reported day (0709), not run day (0710).
    for c in b.containers:
        assert c.id.split("-")[1] == "0709"


@pytest.mark.unit
def test_todo_priorities_mapped(sources):
    todo = _cards_by_type(_build(sources))["todoList"]
    items = todo.payload["items"]
    assert any(i["priority"] == "high" for i in items)
    assert any(i["priority"] == "medium" for i in items)
    assert len(items) == 2


@pytest.mark.unit
def test_health_line_becomes_card(sources):
    bodies = [card.payload.get("body", "")
              for c in _build(sources).containers for card in c.cards]
    assert any("数据源" in body for body in bodies)


@pytest.mark.unit
def test_stable_uuids_are_deterministic(sources):
    a = _build(sources)
    b = _build(sources)
    ids_a = [c.id for c in a.containers] + [k.id for c in a.containers for k in c.cards]
    ids_b = [c.id for c in b.containers] + [k.id for c in b.containers for k in c.cards]
    assert ids_a == ids_b
    for i in ids_a:
        assert len(i.split("-")) == 5


def _empty_sources() -> DigestSources:
    empty: list = []
    return DigestSources(
        raven=RavenTrends(empty, empty, empty, empty, empty, empty, empty,
                          SourceHealth("raven", "error", "boom")),
        multica=MulticaTrends(empty, {}, SourceHealth("multica", "error")),
        ado=AdoPrTrends(empty, empty, SourceHealth("ado_pr", "skipped:未采集")),
        automation=AutomationTrends(empty, empty, empty,
                                    SourceHealth("state_db", "skipped:未采集")),
    )


@pytest.mark.unit
def test_degraded_digest_still_valid_no_empty_metric():
    """A no-data digest yields a valid briefing: overview digest card present,
    and NO empty metric card (contract: metric items.count >= 1)."""
    degraded = "# AI 使用日报 2026-07-09\n\n## ⚡ Trending\n- 数据缺失（raven 未采到）\n"
    b = build_briefing(REPORT_DATE, _empty_sources(), degraded, "数据缺失")
    types = _cards_by_type(b)
    assert "digest" in types
    assert types["digest"].payload["body"] == "数据缺失"
    # no metric card at all (rather than an invalid empty one)
    assert "metric" not in types
    # every collection card that exists is non-empty
    for c in b.containers:
        for card in c.cards:
            assert card.payload
            if "items" in card.payload:
                assert len(card.payload["items"]) >= 1


# --- 今日工作 metric card readability (#3: "turns" 黑话 → 人话, 中性 delta 色) ---
@pytest.mark.unit
def test_work_container_uses_human_unit_and_neutral_direction():
    """The per-project effort card must read in plain language, not "turns", and
    must NOT color activity as good/bad (more interaction ≠ better — could be
    rework). Guards the #3 readability fix."""
    from L5_apps.digest.aidash import _work_container
    from L5_apps.digest.sources import WorkByProject, ProjectWork, SourceHealth

    work = WorkByProject(
        projects=[
            ProjectWork(project="WORKSPACEA", turns=3185, out_ktok=3265, sessions=6),
            ProjectWork(project="AIDASH", turns=267, out_ktok=290, sessions=5),
        ],
        health=SourceHealth("work", "ok"),
    )
    container = _work_container("0721", work)
    assert container is not None
    items = container.cards[0].payload["items"]
    # human-readable unit, not the internal "turns" jargon
    assert all(it["unit"] != "turns" for it in items)
    assert items[0]["unit"] == "次交互"
    # activity volume is neutral, not "higher is better"
    assert all(it["higherIsBetter"] is False for it in items)
    # value preserved
    assert items[0]["value"] == 3185
