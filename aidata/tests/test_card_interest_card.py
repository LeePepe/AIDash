"""Tests for the card-interest fetcher + insight-card producer (spec 005 T007).

Focus on the degrade-safe guards (ADR-23): fetch_card_interest degrades to an
empty/non-ok bundle when aidash_events was never collected or the query fails;
the insight card renders only when there IS a usable Top-N, and reuses the
existing `insight` CardType (spec 005 §I: no new CardType).
"""

import pytest

from L5_apps.digest.aidash import _card_interest_body, _card_interest_container
from L5_apps.digest.sources import CardInterest, CardTypeStar, SourceHealth

MMDD = "0727"


def _ok(name: str) -> SourceHealth:
    return SourceHealth(name, "ok")


def _bad(name: str) -> SourceHealth:
    return SourceHealth(name, "error", "boom")


# --------------------------------------------------------------------------- #
# fetch_card_interest — degrade-safe (ADR-23)
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_fetch_card_interest_skips_when_aidash_events_uncollected(monkeypatch):
    import L5_apps.digest.sources as s
    monkeypatch.setattr(s, "clean_path",
                        lambda name: type("P", (), {"exists": lambda self: False})())
    ci = s.fetch_card_interest("2026-07-20")
    assert ci.types == []
    assert ci.health.state == "skipped:未采集"


@pytest.mark.unit
def test_fetch_card_interest_maps_rows_in_query_order(monkeypatch):
    import serve
    import L5_apps.digest.sources as s
    monkeypatch.setattr(s, "clean_path",
                        lambda name: type("P", (), {"exists": lambda self: True})())
    rows = [("insight", 5), ("trending", 3)]
    monkeypatch.setattr(serve, "run_query",
                        lambda *a, **k: (rows, ["card_type", "star_count"]))
    ci = s.fetch_card_interest("2026-07-20")
    assert ci.health.state == "ok"
    assert ci.types == [CardTypeStar("insight", 5), CardTypeStar("trending", 3)]


@pytest.mark.unit
def test_fetch_card_interest_degrades_on_query_error(monkeypatch):
    import L5_apps.digest.sources as s
    monkeypatch.setattr(s, "clean_path",
                        lambda name: type("P", (), {"exists": lambda self: True})())

    def _boom(*a, **k):
        raise RuntimeError("query blew up")

    import serve
    monkeypatch.setattr(serve, "run_query", _boom)
    ci = s.fetch_card_interest("2026-07-20")
    assert ci.types == []
    assert ci.health.state == "error"


# --------------------------------------------------------------------------- #
# _card_interest_body / _card_interest_container
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_card_interest_body_lists_top_n_descending():
    ci = CardInterest(
        [CardTypeStar("insight", 8), CardTypeStar("trending", 5),
         CardTypeStar("todoList", 2), CardTypeStar("metric", 1)],
        _ok("aidash_events"))
    body = _card_interest_body(ci, top_n=3)
    assert body == "1. insight · 8 次\n2. trending · 5 次\n3. todoList · 2 次"


@pytest.mark.unit
def test_card_interest_body_empty_when_degraded():
    assert _card_interest_body(CardInterest([], _bad("aidash_events"))) == ""


@pytest.mark.unit
def test_card_interest_body_empty_when_no_data():
    assert _card_interest_body(CardInterest([], _ok("aidash_events"))) == ""


@pytest.mark.unit
def test_card_interest_container_reuses_insight_card_type():
    ci = CardInterest([CardTypeStar("insight", 4)], _ok("aidash_events"))
    c = _card_interest_container(MMDD, ci)
    assert c is not None
    assert c.title == "卡型兴趣"
    assert c.order == 55
    assert len(c.cards) == 1
    card = c.cards[0]
    assert card.type == "insight"                # spec 005 §I: no new CardType
    assert card.payload["title"] == "你最常收藏的卡型 Top-N"
    assert "insight · 4 次" in card.payload["body"]


@pytest.mark.unit
def test_card_interest_container_none_when_degraded():
    assert _card_interest_container(MMDD, CardInterest([], _bad("aidash_events"))) is None


@pytest.mark.unit
def test_card_interest_container_none_when_source_missing():
    assert _card_interest_container(MMDD, None) is None
