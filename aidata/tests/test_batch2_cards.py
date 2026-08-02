"""Tests for the batch-2 (L5 数据接入批2) producers: AI 效能 / 时间与产出 /
新闻雷达 / 模型分层 → barList / stackedBar / metric / trending / insight cards.

Focus on the pure transform + the degrade-safe guards (ADR-23): a card/container
appears only when its source is healthy AND non-empty, and the payloads match the
AIDash barList/stackedBar/metric/trending schemas (label/value, segments, etc.).
"""

import pytest

from L5_apps.digest.aidash import (
    _ai_efficiency_container, _time_output_container, _news_container,
    _model_tier_card, _bar_items, _segments, _series_metric_item,
)
from L5_apps.digest.sources import (
    AiEfficiency, RankBundle, RankItem, SegmentBundle, Segment,
    NewsRadar, NewsItem, ModelTier, SourceHealth,
)

MMDD = "0727"


def _ok(name: str) -> SourceHealth:
    return SourceHealth(name, "ok")


def _bad(name: str) -> SourceHealth:
    return SourceHealth(name, "error", "boom")


# --------------------------------------------------------------------------- #
# barList / stackedBar payload shapes
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_bar_items_emit_semantic_only_when_set():
    bundle = RankBundle(
        [RankItem("runtime-offline", 300, "39%", "warning"),
         RankItem("codex-init-fail", 98, "13%", None)],
        _ok("multica_run"))
    items = _bar_items(bundle)
    assert items[0] == {"label": "runtime-offline", "value": 300.0,
                        "valueText": "39%", "semantic": "warning"}
    # neutral row carries NO semantic key (absent-safe for Codable)
    assert "semantic" not in items[1]
    assert items[1]["valueText"] == "13%"


@pytest.mark.unit
def test_segments_emit_semantic_only_when_set():
    bundle = SegmentBundle(
        [Segment("end_turn", 11, "good"), Segment("tool_use", 283, None)],
        _ok("claude_jsonl"))
    segs = _segments(bundle)
    assert segs[0] == {"label": "end_turn", "value": 11.0, "semantic": "good"}
    assert "semantic" not in segs[1]


# --------------------------------------------------------------------------- #
# _series_metric_item: latest-bucket headline + trend from last two buckets
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_series_metric_item_uses_latest_bucket_and_trend_down():
    # newest-first input; latest bucket (W30) is 9.1, prev (W29) 13.1 → down
    series = [("2026-W30", 9.1), ("2026-W29", 13.1), ("2026-W28", 3.0)]
    item = _series_metric_item("返工率", series, "%", False, "本周")
    assert item["value"] == 9.1
    assert item["trend"] == "down"
    assert item["unit"] == "%"
    assert item["higherIsBetter"] is False
    assert item["context"] == "本周"
    # sparkline is oldest→newest
    assert item["series"] == [3.0, 13.1, 9.1]


@pytest.mark.unit
def test_series_metric_item_none_on_empty():
    assert _series_metric_item("x", [], "%", True) is None


# --------------------------------------------------------------------------- #
# 🧠 AI 效能 container
# --------------------------------------------------------------------------- #
def _full_ai() -> AiEfficiency:
    return AiEfficiency(
        cache=[("2026-07-27", 88.4), ("2026-07-28", 89.8)],
        cache_savings=[("2026-07-27", 79.5), ("2026-07-28", 80.8)],
        cache_health=_ok("state_db"),
        rework=[("2026-W30", 9.1), ("2026-W29", 13.1)],
        rework_health=_ok("multica_run"),
        failure=RankBundle([RankItem("runtime-offline", 300, "39%", "warning")],
                           _ok("multica_run")),
        quality=SegmentBundle([Segment("end_turn", 11, "good"),
                               Segment("max_tokens", 2, "warning")],
                              _ok("claude_jsonl")),
        planner_gap_count=50, planner_gap_health=_ok("multica_comment"),
    )


@pytest.mark.unit
def test_ai_efficiency_full_container():
    c = _ai_efficiency_container(MMDD, _full_ai())
    assert c is not None
    assert c.title == "AI 效能"
    assert c.order == 25
    assert c.subtitle  # differentiation subtitle present
    types = [card.type for card in c.cards]
    assert types == ["metric", "barList", "stackedBar", "insight"]
    # cache metric carries the savings context
    metric = c.cards[0].payload["items"]
    assert metric[0]["label"] == "缓存命中率"
    assert "省 81% token 成本" in metric[0]["context"]
    assert metric[1]["label"] == "返工率"
    # planner-gap insight surfaces the count
    assert "50 个 issue" in c.cards[3].payload["body"]


@pytest.mark.unit
def test_ai_efficiency_partial_degrade_keeps_healthy_cards():
    ai = _full_ai()
    # break cache + quality + planner; only rework(metric) + failure(barList) live
    ai = AiEfficiency(
        cache=[], cache_savings=[], cache_health=_bad("state_db"),
        rework=ai.rework, rework_health=ai.rework_health,
        failure=ai.failure,
        quality=SegmentBundle([], _bad("claude_jsonl")),
        planner_gap_count=0, planner_gap_health=_bad("multica_comment"),
    )
    c = _ai_efficiency_container(MMDD, ai)
    assert c is not None
    assert [card.type for card in c.cards] == ["metric", "barList"]


@pytest.mark.unit
def test_ai_efficiency_none_when_all_degraded():
    assert _ai_efficiency_container(MMDD, AiEfficiency.empty()) is None


@pytest.mark.unit
def test_ai_efficiency_omits_planner_insight_when_zero_gap():
    ai = _full_ai()
    ai = AiEfficiency(
        cache=ai.cache, cache_savings=ai.cache_savings, cache_health=ai.cache_health,
        rework=ai.rework, rework_health=ai.rework_health,
        failure=ai.failure, quality=ai.quality,
        planner_gap_count=0, planner_gap_health=_ok("multica_comment"),
    )
    c = _ai_efficiency_container(MMDD, ai)
    assert "insight" not in [card.type for card in c.cards]


# --------------------------------------------------------------------------- #
# ⏱ 时间与产出 container
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_time_output_container_two_barlists():
    focus = RankBundle([RankItem("cmux", 4.4, "4.4 min", None)], _ok("gecko"))
    commit = RankBundle([RankItem("aidata", 4, "4", None)], _ok("local_git"))
    c = _time_output_container(MMDD, focus, commit)
    assert c is not None
    assert c.title == "时间与产出"
    assert c.order == 28
    assert [card.type for card in c.cards] == ["barList", "barList"]


@pytest.mark.unit
def test_time_output_container_none_when_both_degraded():
    empty_g = RankBundle([], _bad("gecko"))
    empty_l = RankBundle([], _bad("local_git"))
    assert _time_output_container(MMDD, empty_g, empty_l) is None


@pytest.mark.unit
def test_time_output_container_survives_one_source():
    focus = RankBundle([RankItem("cmux", 4.4, "4.4 min", None)], _ok("gecko"))
    empty_l = RankBundle([], _bad("local_git"))
    c = _time_output_container(MMDD, focus, empty_l)
    assert c is not None
    assert len(c.cards) == 1


# --------------------------------------------------------------------------- #
# 📰 新闻雷达 container
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_news_container_one_card_per_topic_in_design_order():
    news = NewsRadar([
        NewsItem("world", "W1", "u1", "s1"),
        NewsItem("ai-tech", "A1", "u2", "s2"),
        NewsItem("ai-tech", "A2", "u3", "s3"),
    ], _ok("news"))
    c = _news_container(MMDD, news)
    assert c is not None
    assert c.title == "新闻雷达"
    assert c.order == 80
    topics = [card.payload["topic"] for card in c.cards]
    # ai-tech (design order 0) before world (order 4)
    assert topics == ["AI · 科技", "国际"]
    # each item carries a category pill + the required title/url
    a = c.cards[0].payload["items"]
    assert len(a) == 2
    assert a[0]["title"] == "A1" and a[0]["url"] == "u2"
    assert a[0]["category"] == "AI · 科技"


@pytest.mark.unit
def test_news_container_none_when_degraded():
    assert _news_container(MMDD, NewsRadar([], _bad("news"))) is None


# --------------------------------------------------------------------------- #
# 🔍 可改良 · 模型分层 stackedBar (pure category, no semantic)
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_model_tier_card_pure_category():
    mt = ModelTier([Segment("opus-4.6-1m", 73.5), Segment("opus-4.7", 23.8)],
                   _ok("state_db"))
    card = _model_tier_card(MMDD, mt)
    assert card is not None
    assert card.type == "stackedBar"
    assert card.payload["title"] == "模型分层占比"
    # NO semantic on any segment (pure category)
    assert all("semantic" not in s for s in card.payload["segments"])


@pytest.mark.unit
def test_model_tier_card_none_when_degraded():
    assert _model_tier_card(MMDD, ModelTier([], _bad("state_db"))) is None


# --------------------------------------------------------------------------- #
# fetcher-level: Other-fold, infra-warning tagging, degrade-safe (ADR-23)
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_fold_top_n_folds_tail_into_other():
    from L5_apps.digest.sources import _fold_top_n
    ranked = [(f"c{i}", 100 - i, 10.0 - i) for i in range(9)]  # 9 categories
    items = _fold_top_n(ranked, 6, value_text=lambda p: f"{p:.0f}%",
                        semantic=lambda _l: None)
    assert len(items) == 7                       # 6 head + 1 Other
    assert items[-1].label == "Other"
    # Other's value + pct are the summed remainder (truthful bar)
    assert items[-1].value == sum(100 - i for i in range(6, 9))


@pytest.mark.unit
def test_fold_top_n_no_other_when_within_limit():
    from L5_apps.digest.sources import _fold_top_n
    ranked = [("a", 2, 50.0), ("b", 1, 50.0)]
    items = _fold_top_n(ranked, 6, value_text=lambda p: f"{p:.0f}%",
                        semantic=lambda _l: None)
    assert [i.label for i in items] == ["a", "b"]  # no Other appended


@pytest.mark.unit
def test_failure_rootcause_flags_only_infra_rows(monkeypatch):
    import serve
    rows = [("runtime-offline", 300, 39.0), ("codex-init-fail", 98, 13.0),
            ("daemon-restart", 52, 7.0), ("other", 95, 12.0)]
    monkeypatch.setattr(serve, "run_query",
                        lambda *a, **k: (rows, ["root_cause", "runs", "pct"]))
    from L5_apps.digest.sources import fetch_failure_rootcause
    b = fetch_failure_rootcause()
    tagged = {i.label: i.semantic for i in b.items}
    assert tagged["runtime-offline"] == "warning"
    assert tagged["daemon-restart"] == "warning"
    assert tagged["codex-init-fail"] is None
    assert tagged["other"] is None           # SQL catch-all is NOT flagged


@pytest.mark.unit
def test_app_focus_skips_when_gecko_uncollected(monkeypatch):
    import L5_apps.digest.sources as s
    monkeypatch.setattr(s, "clean_path",
                        lambda name: type("P", (), {"exists": lambda self: False})())
    b = s.fetch_app_focus("2026-07-27", "2026-07-28")
    assert b.items == []
    assert b.health.state.startswith("skipped")


@pytest.mark.unit
def test_finish_reason_dist_drops_zero_reasons(monkeypatch):
    import serve
    # all-clean day: max_tokens=0, other=0 → those segments dropped
    cols = ["day", "turns_with_reason", "end_turn", "tool_use", "max_tokens",
            "other", "max_tokens_pct"]
    rows = [("2026-07-28", 294, 11, 283, 0, 0, 0.0)]
    monkeypatch.setattr(serve, "run_query", lambda *a, **k: (rows, cols))
    from L5_apps.digest.sources import fetch_finish_reason_dist
    b = fetch_finish_reason_dist()
    labels = [s.label for s in b.segments]
    assert labels == ["end_turn", "tool_use"]   # no empty max_tokens/other
    assert b.segments[0].semantic == "good"


@pytest.mark.unit
def test_model_tier_folds_tail_into_other(monkeypatch):
    import serve
    rows = [("opus-1m", 100, 73.5), ("opus", 50, 23.8), ("gpt", 10, 1.4),
            ("gpt-mini", 8, 0.2), ("a", 6, 0.1), ("b", 4, 0.05)]
    cols = ["model", "sessions", "billable_tokens", "token_share_pct",
            "avg_output_per_session"]
    # only 4 of these cols matter; pad rows to match cols
    rows = [(m, 1, 1, share, 1) for (m, _, share) in
            [("opus-1m", 0, 73.5), ("opus", 0, 23.8), ("gpt", 0, 1.4),
             ("gpt-mini", 0, 0.2), ("a", 0, 0.1), ("b", 0, 0.05)]]
    monkeypatch.setattr(serve, "run_query", lambda *a, **k: (rows, cols))
    import L5_apps.digest.sources as s
    monkeypatch.setattr(s, "clean_path",
                        lambda name: type("P", (), {"exists": lambda self: True})())
    mt = s.fetch_model_tier(top_n=5)
    labels = [seg.label for seg in mt.segments]
    assert labels[-1] == "Other"
    assert len(labels) == 6                        # 5 head + Other
