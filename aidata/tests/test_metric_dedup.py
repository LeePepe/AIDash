"""Item-level de-duplication in the trend card (MY-1395 acceptance criterion 5).

The redundancy in this briefing is real but small and precise: when 成本归因
publishes the per-project spend split, the bare 成本 / Token rows in 趋势指标
report the same spend with less information. Everything else in that card —
requests, sessions, completed work, the automation ratio — is restated by
nothing, anywhere.

Two earlier attempts suppressed the whole CONTAINER on that basis and deleted
the non-duplicate rows as collateral. These tests pin the granularity that
actually matches the redundancy, and the guards that keep the fix from becoming
a deletion.
"""

import pytest

from L5_apps.digest.aidash import _SPEND_TOTAL_LABELS, _dedupe_metric_items


def _items(*labels: str) -> list[dict]:
    return [{"label": label, "value": 1.0, "trend": "flat"} for label in labels]


def _labels(items: list[dict]) -> list[str]:
    return [item["label"] for item in items]


# --------------------------------------------------------------------------- #
# The two required outcomes, asserted directly on the transform
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_duplicate_spend_rows_are_dropped_when_the_breakdown_is_published():
    kept = _dedupe_metric_items(
        _items("成本", "Token", "请求数", "会话数"), True)
    assert _labels(kept) == ["请求数", "会话数"]


@pytest.mark.unit
def test_non_duplicate_rows_are_untouched():
    """The distinction the container-level attempts could not express."""
    kept = _dedupe_metric_items(
        _items("成本", "请求数", "浪费额", "完成任务", "会话数", "自动化占比"), True)
    assert _labels(kept) == ["请求数", "浪费额", "完成任务", "会话数", "自动化占比"]


@pytest.mark.unit
def test_nothing_is_dropped_when_the_breakdown_is_absent():
    """Suppression is conditional on the stronger card actually being on the
    page. Without it, dropping the totals removes the signal rather than
    de-duplicating it — the worse outcome of the two."""
    items = _items("成本", "Token", "请求数")
    assert _labels(_dedupe_metric_items(items, False)) == \
        ["成本", "Token", "请求数"]


@pytest.mark.unit
def test_row_order_is_preserved():
    kept = _dedupe_metric_items(
        _items("请求数", "成本", "会话数", "Token", "完成任务"), True)
    assert _labels(kept) == ["请求数", "会话数", "完成任务"]


# --------------------------------------------------------------------------- #
# Guards: de-duplication must never become deletion
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_an_all_duplicate_card_is_left_intact_rather_than_emptied():
    """MetricPayload requires items.count >= 1. Emptying the card makes the app
    reject it with schema.payload_decode_failed and the card vanishes silently
    — a de-duplication that deletes the whole signal. With nothing left to thin,
    the card is kept and the budget decides its fate on rank instead."""
    items = _items("成本", "Token")
    assert _dedupe_metric_items(items, True) == items


@pytest.mark.unit
def test_an_empty_input_stays_empty():
    assert _dedupe_metric_items([], True) == []


@pytest.mark.unit
def test_the_result_is_never_empty_for_a_non_empty_input():
    """The invariant behind the guard above, over every subset of the real
    label set — including the ones that are entirely duplicates."""
    labels = ["成本", "Token", "请求数", "会话数"]
    for size in range(1, len(labels) + 1):
        for start in range(len(labels) - size + 1):
            window = labels[start:start + size]
            for published in (True, False):
                kept = _dedupe_metric_items(_items(*window), published)
                assert kept, f"emptied the card for {window} (published={published})"


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
def test_the_duplicate_label_set_is_exactly_the_spend_totals():
    """Naming the set explicitly: only the two rows 成本归因 genuinely restates.
    Widening this silently is how non-duplicate signals get deleted."""
    assert set(_SPEND_TOTAL_LABELS) == {"成本", "Token"}


# --------------------------------------------------------------------------- #
# Pair survival — the invariant the removed two-pass algorithm claimed
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_at_least_one_side_of_the_pair_always_survives():
    """For the (breakdown, totals) pair, at least one side always reaches the
    reader — the guarantee the two-pass container algorithm asserted but could
    not keep, because admission is not monotone.

    Here it holds structurally rather than by construction: the totals are only
    dropped in the branch where the breakdown is published, so no state exists
    in which both are gone.
    """
    items = _items("成本", "Token", "请求数")
    for breakdown_published in (True, False):
        kept = _labels(_dedupe_metric_items(items, breakdown_published))
        totals_survive = bool({"成本", "Token"} & set(kept))
        assert breakdown_published or totals_survive, (
            "the spend signal disappeared: no breakdown published AND the "
            "totals were dropped"
        )
