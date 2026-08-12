"""Pure card-policy tests: data shape → CardType/size/visualization, and the
briefing information budget.

`card_policy` is deliberately I/O-free: it takes a DataProfile (what the data
IS) and returns a CardDecision (how it should be published), plus a budget
selector over already-built candidates. Keeping it pure is what makes the
"why did this card become wide?" question answerable in a unit test rather
than by eyeballing a rendered briefing.

Two rules carry most of the weight and are asserted hardest:
  1. `hero` is NEVER reachable from item count alone — hero is an editorial
     emphasis decision, and letting a count grant it is how empty big cards
     appear (§design 2.2: "size 是作者上限，不是必须填满的目标").
  2. `relationship` requires two real dimensions AND an explicit kind — a
     relationship inferred from a one-dimensional list is a misleading chart.
"""

import pytest

from L5_apps.digest.card_policy import (
    CardCandidate,
    DataProfile,
    FIRST_SCREEN_CARDS,
    MAX_ACTIONS,
    MAX_CARDS,
    choose_card,
    select_with_budget,
)


class _Card:
    """Minimal stand-in for aidash.Card — the policy only reads `.id`."""

    def __init__(self, card_id: str) -> None:
        self.id = card_id


def _candidate(card_id: str, order: int, **kw) -> CardCandidate:
    return CardCandidate(
        card=_Card(card_id),
        order=order,
        requires_action=kw.get("requires_action", False),
        is_anomaly=kw.get("is_anomaly", False),
        cross_signal_strength=kw.get("cross_signal_strength", 0),
        freshness=kw.get("freshness", 1),
        source_coverage=kw.get("source_coverage", 1),
        reading_cost=kw.get("reading_cost", 1),
        is_detail=kw.get("is_detail", False),
        provides=kw.get("provides", ()),
        redundant_with=kw.get("redundant_with", ()),
        weight=kw.get("weight", 1),
    )


# --------------------------------------------------------------------------- #
# choose_card — the approved shape → card matrix
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_single_scalar_is_a_small_metric():
    d = choose_card(DataProfile(semantic="scalar", item_count=1, dimensions=1))
    assert (d.card_type, d.size, d.visualization) == ("metric", "small", None)
    assert d.reason


@pytest.mark.unit
def test_a_few_scalars_stay_medium_and_many_go_wide():
    assert choose_card(
        DataProfile(semantic="scalar", item_count=4, dimensions=1)).size == "medium"
    assert choose_card(
        DataProfile(semantic="scalar", item_count=5, dimensions=1)).size == "wide"


@pytest.mark.unit
def test_timeseries_is_a_metric_with_series_visualization():
    d = choose_card(DataProfile(semantic="timeseries", item_count=3, dimensions=1))
    assert d.card_type == "metric"
    assert d.visualization == "series", "a time trend stays a metric series, not a new CardType"


@pytest.mark.unit
def test_ranking_maps_to_barlist_sized_by_count():
    assert choose_card(
        DataProfile(semantic="ranking", item_count=3, dimensions=1)
    ) == choose_card(DataProfile(semantic="ranking", item_count=4, dimensions=1))
    assert choose_card(
        DataProfile(semantic="ranking", item_count=3, dimensions=1)).card_type == "barList"
    assert choose_card(
        DataProfile(semantic="ranking", item_count=3, dimensions=1)).size == "medium"
    assert choose_card(
        DataProfile(semantic="ranking", item_count=9, dimensions=1)).size == "wide"


@pytest.mark.unit
def test_composition_maps_to_stackedbar():
    d = choose_card(DataProfile(semantic="composition", item_count=6, dimensions=1))
    assert (d.card_type, d.size) == ("stackedBar", "wide")
    assert choose_card(
        DataProfile(semantic="composition", item_count=2, dimensions=1)).size == "medium"


@pytest.mark.unit
def test_narrative_is_insight_when_single_and_digest_when_many():
    one = choose_card(DataProfile(semantic="narrative", item_count=1, dimensions=1))
    many = choose_card(DataProfile(semantic="narrative", item_count=3, dimensions=1))
    assert (one.card_type, one.size) == ("insight", "medium")
    assert (many.card_type, many.size) == ("digest", "wide")


@pytest.mark.unit
def test_actions_map_to_todolist_capped_at_three_before_growing():
    assert choose_card(
        DataProfile(semantic="actions", item_count=3, dimensions=1)).size == "medium"
    assert choose_card(
        DataProfile(semantic="actions", item_count=4, dimensions=1)).size == "wide"
    assert choose_card(
        DataProfile(semantic="actions", item_count=2, dimensions=1)).card_type == "todoList"


# --------------------------------------------------------------------------- #
# relationship — the new semantic, and the guards that keep it honest
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_two_by_two_matrix_is_a_wide_heatmap_relationship():
    d = choose_card(DataProfile(
        semantic="relationship", item_count=4, dimensions=2,
        row_count=2, column_count=2, relationship_kind="heatmap"))
    assert (d.card_type, d.size, d.visualization) == ("relationship", "wide", "heatmap")


@pytest.mark.unit
def test_thin_matrix_downgrades_to_medium_rather_than_claiming_richness():
    """One row is a ranking wearing a matrix's clothes — never wide."""
    d = choose_card(DataProfile(
        semantic="relationship", item_count=3, dimensions=2,
        row_count=1, column_count=3, relationship_kind="heatmap"))
    assert d.size == "medium"


@pytest.mark.unit
def test_five_or_more_scatter_points_earn_wide():
    d = choose_card(DataProfile(
        semantic="relationship", item_count=5, dimensions=2,
        relationship_kind="scatter"))
    assert (d.size, d.visualization) == ("wide", "scatter")


@pytest.mark.unit
def test_slope_kind_is_carried_through():
    d = choose_card(DataProfile(
        semantic="relationship", item_count=6, dimensions=2,
        relationship_kind="slope"))
    assert d.visualization == "slope"


@pytest.mark.unit
def test_relationship_rejects_wrong_dimension_count():
    with pytest.raises(ValueError):
        choose_card(DataProfile(
            semantic="relationship", item_count=4, dimensions=1,
            relationship_kind="heatmap"))


@pytest.mark.unit
def test_relationship_rejects_missing_kind():
    with pytest.raises(ValueError):
        choose_card(DataProfile(
            semantic="relationship", item_count=4, dimensions=2))


@pytest.mark.unit
def test_empty_data_is_rejected_rather_than_published_as_an_empty_card():
    with pytest.raises(ValueError):
        choose_card(DataProfile(semantic="scalar", item_count=0, dimensions=1))


@pytest.mark.unit
def test_hero_is_never_reachable_from_item_count_alone():
    """§design 2.2 / constitution §III: hero is editorial emphasis, not a
    consequence of having many rows. An automatic hero is how the briefing grew
    big empty cards in the first place."""
    profiles = [
        DataProfile(semantic=sem, item_count=n, dimensions=1)
        for sem in ("scalar", "timeseries", "ranking", "composition",
                    "narrative", "actions")
        for n in (1, 2, 5, 20, 200)
    ]
    profiles += [
        DataProfile(semantic="relationship", item_count=n, dimensions=2,
                    row_count=n, column_count=n, relationship_kind="heatmap")
        for n in (1, 2, 5, 20)
    ]
    assert all(choose_card(p).size != "hero" for p in profiles)


# --------------------------------------------------------------------------- #
# select_with_budget — the information budget
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_budget_caps_total_cards():
    candidates = [_candidate(f"c{i:02d}", i, cross_signal_strength=1)
                  for i in range(20)]
    assert len(select_with_budget(candidates)) == MAX_CARDS


@pytest.mark.unit
def test_first_screen_slice_is_bounded():
    candidates = [_candidate(f"c{i:02d}", i, cross_signal_strength=1)
                  for i in range(20)]
    selected = select_with_budget(candidates)
    assert FIRST_SCREEN_CARDS <= MAX_CARDS
    assert len(selected[:FIRST_SCREEN_CARDS]) == FIRST_SCREEN_CARDS


@pytest.mark.unit
def test_action_and_anomaly_outrank_a_stale_reference_card():
    reference = _candidate("ref", 0, freshness=0, reading_cost=4)
    anomaly = _candidate("anom", 9, is_anomaly=True)
    action = _candidate("act", 8, requires_action=True)
    ranked = [c.card.id for c in select_with_budget([reference, anomaly, action])]
    assert ranked[:2] == ["act", "anom"]


@pytest.mark.unit
def test_cross_signal_outranks_a_single_dimension_card():
    cross = _candidate("cross", 5, cross_signal_strength=4)
    single = _candidate("single", 1, cross_signal_strength=0, freshness=9)
    assert [c.card.id for c in select_with_budget([cross, single])][0] == "cross"


@pytest.mark.unit
def test_cheaper_reading_cost_breaks_an_otherwise_equal_tie():
    cheap = _candidate("cheap", 7, reading_cost=1)
    dear = _candidate("dear", 2, reading_cost=5)
    assert [c.card.id for c in select_with_budget([cheap, dear])][0] == "cheap"


@pytest.mark.unit
def test_selection_is_deterministic_and_stable():
    candidates = [_candidate(f"c{i:02d}", i, cross_signal_strength=i % 3)
                  for i in range(15)]
    first = [c.card.id for c in select_with_budget(candidates)]
    second = [c.card.id for c in select_with_budget(list(reversed(candidates)))]
    assert first == second, "ordering must not depend on input order"


@pytest.mark.unit
def test_stable_detail_cards_without_signal_are_omitted_not_just_demoted():
    """§design 5: 低价值卡被省略而非只是排到底部."""
    detail = _candidate("detail", 1, is_detail=True)
    kept = _candidate("kept", 2, cross_signal_strength=1)
    ids = [c.card.id for c in select_with_budget([detail, kept])]
    assert ids == ["kept"]


@pytest.mark.unit
def test_a_detail_card_that_carries_a_signal_survives():
    for kw in ({"requires_action": True}, {"is_anomaly": True},
               {"cross_signal_strength": 1}):
        candidate = _candidate("detail", 1, is_detail=True, **kw)
        assert [c.card.id for c in select_with_budget([candidate])] == ["detail"]


@pytest.mark.unit
def test_empty_candidate_set_is_not_an_error():
    assert select_with_budget([]) == []


# --------------------------------------------------------------------------- #
# Redundancy suppression — a weaker restatement of a stronger signal
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_raw_token_card_is_suppressed_when_a_stronger_cross_signal_exists():
    raw = _candidate("raw-tokens", 1, redundant_with=("outcome_x_tokens",))
    cross = _candidate("cross", 5, cross_signal_strength=3,
                       provides=("outcome_x_tokens",))
    ids = [c.card.id for c in select_with_budget([raw, cross])]
    assert ids == ["cross"]


@pytest.mark.unit
def test_raw_card_survives_when_the_stronger_signal_is_absent():
    """Suppression must be conditional — with no cross card, the raw one is
    the only thing saying anything, and dropping it loses the signal."""
    raw = _candidate("raw-tokens", 1, redundant_with=("outcome_x_tokens",))
    unrelated = _candidate("other", 5, cross_signal_strength=3,
                           provides=("something_else",))
    ids = [c.card.id for c in select_with_budget([raw, unrelated])]
    assert set(ids) == {"raw-tokens", "other"}


@pytest.mark.unit
def test_a_suppressed_card_that_demands_action_is_still_kept():
    """An actionable card is never silently dropped as a duplicate."""
    raw = _candidate("raw-tokens", 1, requires_action=True,
                     redundant_with=("outcome_x_tokens",))
    cross = _candidate("cross", 5, cross_signal_strength=3,
                       provides=("outcome_x_tokens",))
    ids = [c.card.id for c in select_with_budget([raw, cross])]
    assert set(ids) == {"raw-tokens", "cross"}


@pytest.mark.unit
def test_suppression_does_not_apply_to_a_card_against_itself():
    solo = _candidate("solo", 1, provides=("outcome_x_tokens",),
                      redundant_with=("outcome_x_tokens",))
    assert [c.card.id for c in select_with_budget([solo])] == ["solo"]


@pytest.mark.unit
def test_action_budget_constant_matches_the_design():
    assert MAX_ACTIONS == 3
    assert FIRST_SCREEN_CARDS == 6
    assert MAX_CARDS == 10


# --------------------------------------------------------------------------- #
# The budget is spent in CARDS, not candidates
# --------------------------------------------------------------------------- #
def _weighted(card_id: str, order: int, weight: int, **kw) -> CardCandidate:
    return _candidate(card_id, order, weight=weight, **kw)


@pytest.mark.unit
def test_budget_charges_a_candidate_for_every_card_it_publishes():
    """Three five-card sections must not report "3 of 10" while publishing 15."""
    heavy = [_weighted(f"h{i}", i, 5, cross_signal_strength=1) for i in range(3)]
    selected = select_with_budget(heavy)
    assert sum(c.weight for c in selected) <= MAX_CARDS
    assert len(selected) == 2, "only two five-card sections fit inside ten"


@pytest.mark.unit
def test_a_candidate_too_heavy_for_the_remaining_budget_is_skipped():
    """Admission is all-or-nothing: half a section is an uninterpretable stump,
    so an over-budget candidate yields to a lighter one behind it."""
    big = _weighted("big", 0, 9, cross_signal_strength=5)
    huge = _weighted("huge", 1, 8, cross_signal_strength=4)
    small = _weighted("small", 2, 1, cross_signal_strength=1)
    ids = [c.card.id for c in select_with_budget([big, huge, small])]
    assert ids == ["big", "small"], "the 8-card section could not fit in 1"


@pytest.mark.unit
def test_weight_defaults_to_one_card():
    assert _candidate("c", 0).weight == 1


@pytest.mark.unit
def test_zero_or_negative_weight_still_costs_one():
    """A malformed weight must not buy free admission."""
    cheats = [_weighted(f"z{i:02d}", i, 0, cross_signal_strength=1)
              for i in range(30)]
    assert len(select_with_budget(cheats)) <= MAX_CARDS


@pytest.mark.unit
def test_first_screen_is_charged_in_cards_too():
    lead_heavy = _weighted("lead", 0, 6, cross_signal_strength=5)
    follower = _weighted("follow", 1, 1, cross_signal_strength=4)
    selected = select_with_budget([lead_heavy, follower])
    # The 6-card section fills the first screen exactly; the follower is tail.
    assert [c.card.id for c in selected] == ["lead", "follow"]


@pytest.mark.unit
def test_first_screen_is_a_contiguous_prefix_not_a_cherry_pick():
    """Once a candidate overruns the first screen, the screen is closed — a
    lighter candidate further down does not get promoted past it, because a
    reader cannot skip a section."""
    heavy = _weighted("heavy", 0, 5, cross_signal_strength=9)
    also_heavy = _weighted("also", 1, 4, cross_signal_strength=8)
    light = _weighted("light", 2, 1, cross_signal_strength=1)
    selected = select_with_budget([heavy, also_heavy, light])
    assert [c.card.id for c in selected][0] == "heavy"
    assert sum(c.weight for c in selected) <= MAX_CARDS


@pytest.mark.unit
def test_weighted_selection_is_deterministic():
    pool = [_weighted(f"c{i:02d}", i, (i % 4) + 1, cross_signal_strength=i % 3)
            for i in range(12)]
    first = [c.card.id for c in select_with_budget(pool)]
    second = [c.card.id for c in select_with_budget(list(reversed(pool)))]
    assert first == second
