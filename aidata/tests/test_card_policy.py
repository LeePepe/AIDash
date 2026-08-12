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
def test_a_single_row_heatmap_is_thin_no_matter_how_many_cells():
    """A 1×5 matrix has five cells and ONE row: the second axis carries no
    information, so cell count must not buy it richness.

    Entirely reachable in production — one workspace with five distinct failure
    root causes (the SQL has eight buckets) is the normal shape for a
    single-workspace user, and it was publishing a wide heatmap asserting a
    dimension the data does not have.
    """
    d = choose_card(DataProfile(
        semantic="relationship", item_count=5, dimensions=2,
        row_count=1, column_count=5, relationship_kind="heatmap"))
    assert d.size == "medium"


@pytest.mark.unit
def test_a_single_column_heatmap_is_thin_no_matter_how_many_cells():
    d = choose_card(DataProfile(
        semantic="relationship", item_count=5, dimensions=2,
        row_count=5, column_count=1, relationship_kind="heatmap"))
    assert d.size == "medium"


@pytest.mark.unit
def test_a_large_single_axis_heatmap_is_still_thin():
    """Scale does not create a second dimension."""
    for rows, cols in ((1, 40), (40, 1)):
        d = choose_card(DataProfile(
            semantic="relationship", item_count=rows * cols, dimensions=2,
            row_count=rows, column_count=cols, relationship_kind="heatmap"))
        assert d.size == "medium", f"{rows}x{cols} claimed richness"


@pytest.mark.unit
def test_heatmap_richness_needs_both_axes():
    """Both axes at 2+ is the whole test for a heatmap — no cell-count escape."""
    d = choose_card(DataProfile(
        semantic="relationship", item_count=4, dimensions=2,
        row_count=2, column_count=2, relationship_kind="heatmap"))
    assert d.size == "wide"


@pytest.mark.unit
def test_scatter_and_slope_keep_point_count_richness():
    """Scatter/slope do not populate row/column counts — their richness is the
    number of marks, so the point-count branch must survive for them."""
    for kind in ("scatter", "slope"):
        rich = choose_card(DataProfile(
            semantic="relationship", item_count=5, dimensions=2,
            relationship_kind=kind))
        thin = choose_card(DataProfile(
            semantic="relationship", item_count=4, dimensions=2,
            relationship_kind=kind))
        assert rich.size == "wide", f"{kind} with 5 marks should be wide"
        assert thin.size == "medium", f"{kind} with 4 marks should be medium"


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
    assert list(select_with_budget([])) == []


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
def test_admission_is_not_monotone_which_is_why_suppression_was_removed():
    """Evidence for the retired assumption, kept as an executable record.

    The removed two-pass algorithm rested on "dropping a candidate can only ever
    admit more, never fewer". That is FALSE here: `_admit` skips an over-budget
    candidate and lets a lighter one take its place, so removing a candidate can
    change WHICH others fit and evict one that was previously admitted.

    Below, dropping `dependent` (weight 2) frees room for `heavy` (weight 9),
    which then crowds out `provider` (weight 3) — the very card whose presence
    would have justified suppressing `dependent`. Both sides gone, signal lost.
    That is the failure mode the suppression could not avoid, and the reason
    de-duplication now happens per item in the producer instead.
    """
    dependent = _weighted("dependent", 0, 2, cross_signal_strength=9)
    heavy = _weighted("heavy", 1, 9, cross_signal_strength=8)
    provider = _weighted("provider", 2, 3, cross_signal_strength=7)

    with_dependent = [c.card.id for c in
                      select_with_budget([dependent, heavy, provider])]
    without_dependent = [c.card.id for c in
                         select_with_budget([heavy, provider])]

    assert "provider" in with_dependent, "fixture no longer admits the provider"
    assert "provider" not in without_dependent, (
        "removing a candidate must be able to EVICT another for this to be "
        "the counterexample it documents"
    )
    # Hence the two-pass scheme would publish neither side of the pair.
    assert "dependent" not in without_dependent


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


# --------------------------------------------------------------------------- #
# The first-screen boundary is returned, not left to be re-derived
# --------------------------------------------------------------------------- #
@pytest.mark.unit
def test_the_result_reports_its_own_lead_boundary():
    high = _weighted("high", 20, 3, cross_signal_strength=5)
    mid = _weighted("mid", 30, 4, cross_signal_strength=4)
    low = _weighted("low", 15, 1, cross_signal_strength=0)
    result = select_with_budget([high, mid, low], max_cards=8, first_screen=4)
    assert [c.card.id for c in result.lead] == ["high"]
    assert "low" not in [c.card.id for c in result.lead]


@pytest.mark.unit
def test_the_selection_stays_in_priority_order_throughout():
    """Including the tail. Re-sorting the tail into authored order let a light,
    low-priority candidate with an early authored number render above a
    higher-priority one — the consumer renumbers from this sequence, so the
    order here IS the order the reader gets."""
    high = _weighted("high", 20, 3, cross_signal_strength=5)
    mid = _weighted("mid", 30, 4, cross_signal_strength=4)
    low = _weighted("low", 15, 1, cross_signal_strength=0)
    ids = [c.card.id for c in select_with_budget([high, mid, low],
                                                 max_cards=8, first_screen=4)]
    assert ids == ["high", "mid", "low"], (
        "authored order overrode the budget's ranking"
    )


@pytest.mark.unit
def test_the_lead_boundary_is_not_a_card_count_off_the_front():
    """The boundary must be reported, not re-derived: with mixed weights, the
    screen closes on a candidate too heavy to fit, and the count alone cannot
    say where that happened."""
    high = _weighted("high", 20, 3, cross_signal_strength=5)
    mid = _weighted("mid", 30, 4, cross_signal_strength=4)
    low = _weighted("low", 15, 1, cross_signal_strength=0)
    result = select_with_budget([high, mid, low], max_cards=8, first_screen=4)
    assert [c.card.id for c in result.lead] == ["high"]
    assert [c.card.id for c in result.tail] == ["mid", "low"]


@pytest.mark.unit
def test_lead_and_tail_partition_the_selection():
    pool = [_weighted(f"c{i:02d}", i, (i % 3) + 1, cross_signal_strength=i % 4)
            for i in range(10)]
    result = select_with_budget(pool)
    assert result.lead + result.tail == result.selected
    assert len(result) == len(result.selected)


@pytest.mark.unit
def test_an_empty_budget_result_is_still_iterable():
    result = select_with_budget([])
    assert list(result) == []
    assert result.lead == [] and result.tail == []
