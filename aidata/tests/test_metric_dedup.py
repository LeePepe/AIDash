"""Item-level de-duplication in the trend card (MY-1395 acceptance criterion 5).

The redundancy in this briefing is real but SMALLER than it first appears, and
getting its extent wrong deletes signal. The published spend-breakdown card
(slot 32, attribution/cost-by-project) renders `cost_usd` and nothing else —
`fetch_cost_by_project` selects only `project` / `cost_usd` / `cost_pct`, so the
query's `ktokens` and `requests` columns never reach a card. Therefore only the
`成本` row is genuinely restated. `Token`, `请求数` and `会话数` are covered by
nothing on the page and must always survive.

Two earlier attempts got the granularity wrong at the container level; a third
got the extent wrong by dropping `Token` as well. These tests pin both.
"""

import pytest

from L5_apps.digest.aidash import _SPEND_TOTAL_LABELS, _dedupe_metric_items

# Rows that must NEVER be removed by de-duplication: nothing else on the page
# reports them. `Token` is in this list on purpose — it was wrongly treated as
# redundant when the breakdown card publishes no token figure at all.
_MUST_SURVIVE = ("Token", "请求数", "会话数")


def _items(*labels: str) -> list[dict]:
    return [{"label": label, "value": 1.0, "trend": "flat"} for label in labels]


def _labels(items: list[dict]) -> list[str]:
    return [item["label"] for item in items]


# --------------------------------------------------------------------------- #
# Extent: exactly one row is redundant, and it is the cost row
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_only_the_cost_row_is_dropped_when_the_breakdown_is_published():
    kept = _dedupe_metric_items(
        _items("成本", "Token", "请求数", "会话数"), True)
    assert _labels(kept) == ["Token", "请求数", "会话数"]


@pytest.mark.unit
def test_the_token_row_always_survives():
    """The breakdown card publishes cost only. `ktokens` exists in the SQL but
    `fetch_cost_by_project` never selects it, so no published card reports a
    token figure — dropping this row deletes the signal outright."""
    for published in (True, False):
        kept = _labels(_dedupe_metric_items(_items("成本", "Token"), published))
        assert "Token" in kept, f"Token dropped (breakdown published={published})"


@pytest.mark.unit
def test_the_non_spend_rows_always_survive():
    kept = _dedupe_metric_items(
        _items("成本", "Token", "请求数", "浪费额", "完成任务", "会话数",
               "自动化占比"), True)
    assert _labels(kept) == ["Token", "请求数", "浪费额", "完成任务", "会话数",
                             "自动化占比"]


@pytest.mark.unit
def test_nothing_is_dropped_when_the_breakdown_is_absent():
    """Suppression is conditional on the stronger card actually being on the
    page. Without it, dropping the cost row removes the signal rather than
    de-duplicating it — the worse outcome of the two."""
    items = _items("成本", "Token", "请求数")
    assert _labels(_dedupe_metric_items(items, False)) == \
        ["成本", "Token", "请求数"]


@pytest.mark.unit
def test_row_order_is_preserved():
    kept = _dedupe_metric_items(
        _items("请求数", "成本", "会话数", "Token", "完成任务"), True)
    assert _labels(kept) == ["请求数", "会话数", "Token", "完成任务"]


# --------------------------------------------------------------------------- #
# Guards: de-duplication must never become deletion
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_an_all_duplicate_card_is_left_intact_rather_than_emptied():
    """MetricPayload requires items.count >= 1. Emptying the card makes the app
    reject it with schema.payload_decode_failed and the card vanishes silently
    — a de-duplication that deletes. With nothing left to thin, the card is kept
    and the budget decides its fate on rank instead."""
    items = _items("成本")
    assert _dedupe_metric_items(items, True) == items


@pytest.mark.unit
def test_an_empty_input_stays_empty():
    assert _dedupe_metric_items([], True) == []


@pytest.mark.unit
def test_the_result_is_never_empty_for_a_non_empty_input():
    """The invariant behind the guard above, over every window of the real
    label set — including the all-duplicate one."""
    labels = ["成本", "Token", "请求数", "会话数"]
    for size in range(1, len(labels) + 1):
        for start in range(len(labels) - size + 1):
            window = labels[start:start + size]
            for published in (True, False):
                kept = _dedupe_metric_items(_items(*window), published)
                assert kept, f"emptied the card for {window} (published={published})"


@pytest.mark.unit
def test_protected_rows_survive_every_window():
    """Stronger than "not empty": the rows nothing else covers survive every
    combination, not merely most of them."""
    labels = ["成本", "Token", "请求数", "会话数"]
    for size in range(1, len(labels) + 1):
        for start in range(len(labels) - size + 1):
            window = labels[start:start + size]
            for published in (True, False):
                kept = set(_labels(_dedupe_metric_items(_items(*window),
                                                        published)))
                expected = {lb for lb in window if lb in _MUST_SURVIVE}
                assert expected <= kept, (
                    f"{expected - kept} dropped from {window} "
                    f"(published={published})"
                )


@pytest.mark.unit
def test_de_duplication_does_not_mutate_its_input():
    """Immutability: the caller's list must survive unchanged (repo convention,
    and the same items feed the markdown renderer)."""
    items = _items("成本", "请求数")
    snapshot = [dict(item) for item in items]
    _dedupe_metric_items(items, True)
    assert items == snapshot


@pytest.mark.unit
def test_rows_without_a_label_are_never_dropped():
    """Absent-key tolerance: a row with no label cannot be proven a duplicate,
    and guessing would delete a signal."""
    items = [{"value": 1.0}, {"label": "成本", "value": 2.0}]
    kept = _dedupe_metric_items(items, True)
    assert kept == [{"value": 1.0}]


@pytest.mark.unit
def test_the_duplicate_label_set_is_exactly_the_cost_row():
    """Naming the set explicitly. The breakdown card renders `cost_usd` alone,
    so this is the only row it restates — widening it silently is how
    non-duplicate signals get deleted."""
    assert set(_SPEND_TOTAL_LABELS) == {"成本"}


@pytest.mark.unit
def test_no_protected_row_is_in_the_duplicate_set():
    """Structural guard: the two lists must never overlap, whatever either
    grows into later."""
    assert not (set(_SPEND_TOTAL_LABELS) & set(_MUST_SURVIVE))


# --------------------------------------------------------------------------- #
# Pair survival — the invariant the removed two-pass algorithm claimed
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_at_least_one_side_of_the_pair_always_survives():
    """For the (breakdown, cost total) pair, at least one side always reaches
    the reader — the guarantee the two-pass container algorithm asserted but
    could not keep, because admission is not monotone.

    Here it holds structurally rather than by construction: the cost row is only
    dropped in the branch where the breakdown is published, so no state exists
    in which both are gone.
    """
    items = _items("成本", "Token", "请求数")
    for breakdown_published in (True, False):
        kept = _labels(_dedupe_metric_items(items, breakdown_published))
        assert breakdown_published or "成本" in kept, (
            "the spend signal disappeared: no breakdown published AND the "
            "cost total was dropped"
        )

