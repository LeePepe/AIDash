"""Pure card policy: data shape → CardType/size/visualization, and the daily
information budget.

Two decisions used to be implicit in `aidash.py`'s hand-written builders — what
CardType a bundle deserves, and how big it may be. Implicit meant unreviewable:
a card was `wide` because someone typed `"wide"`, not because the data was two-
dimensional. This module makes both decisions explicit, pure, and unit-testable,
and records the `reason` so a surprising card can be explained without rendering
the briefing.

Nothing here does I/O, reads a warehouse, or knows what a Card looks like beyond
its `id` — that keeps the rules assertable in isolation (§design 5: "L5 使用纯
函数选择 CardType/size/visualization，保留选择 reason 供测试与调试").

## Two invariants worth stating out loud

1. **`hero` is unreachable from data volume.** `hero` is editorial emphasis, and
   size is an author's ceiling rather than a quota to fill (§design 2.2). Letting
   a row count grant hero is precisely how the briefing grew big cards with
   little in them.
2. **`relationship` demands two real dimensions and an explicit kind.** A
   relationship inferred from a one-dimensional list is a chart that asserts a
   structure the data does not have.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Sequence

# ---- Information budget (§design 3) ---------------------------------------
# The first screen is a two-minute read; the whole page is five. Both numbers
# are ceilings, not targets — a thin day publishes fewer cards, never padding.
FIRST_SCREEN_CARDS = 6
MAX_CARDS = 10
MAX_ACTIONS = 3

# ---- Size thresholds (§design 2.2) ----------------------------------------
# A handful of related items reads at `medium`; past that the card needs the
# room. Named rather than inlined so the matrix tests pin the boundary itself.
MEDIUM_ITEM_CEILING = 4
RELATIONSHIP_RICH_POINTS = 5
RELATIONSHIP_RICH_ROWS = 2
RELATIONSHIP_RICH_COLUMNS = 2

_RELATIONSHIP_KINDS = ("scatter", "heatmap", "slope")


@dataclass(frozen=True)
class DataProfile:
    """What a dataset IS, independent of how it will be drawn.

    `semantic` is the shape's meaning, not a chart name: a time trend is a
    `timeseries` that happens to render as a metric series, and a two-dimensional
    cross-tab is a `relationship` whether it ends up a heatmap or a scatter.

    `dimensions` counts the *analytical* axes (1 for a ranking, 2 for a cross
    signal). `row_count` / `column_count` describe a matrix's extent and only
    matter for `heatmap`. `relationship_kind` is supplied by the producer that
    knows the data, never guessed here.
    """

    semantic: str
    item_count: int
    dimensions: int
    row_count: int = 0
    column_count: int = 0
    relationship_kind: str | None = None


@dataclass(frozen=True)
class CardDecision:
    """The published shape, plus why it was chosen."""

    card_type: str
    size: str
    visualization: str | None
    reason: str


@dataclass(frozen=True)
class CardCandidate:
    """One built card offered to the budget, with the signals that rank it.

    `card` is opaque here — only `card.id` is read, as the final deterministic
    tie-break. Keeping the policy ignorant of the payload is what lets it be
    tested without constructing briefings.

    `is_detail` marks a stable descriptive card: informative when there is room,
    but carrying no action, anomaly, or cross-source value. Those are *omitted*
    rather than demoted, because a card pushed to the bottom still costs the
    reader the scroll (§design 5: 低价值卡被省略而非只是排到底部).

    `weight` is how many PUBLISHED CARDS this candidate stands for. It is 1 for
    a single card and N for a section carrying N of them. The budget is spent
    in cards because that is what the reader's five minutes are spent on — a
    candidate that costs 1 while publishing 5 would let three sections report
    "3 of 10" while putting 15 cards on the page.
    """

    card: Any
    order: int
    requires_action: bool = False
    is_anomaly: bool = False
    cross_signal_strength: int = 0
    freshness: int = 0
    source_coverage: int = 0
    reading_cost: int = 0
    is_detail: bool = False
    weight: int = 1

    @property
    def carries_signal(self) -> bool:
        return (self.requires_action or self.is_anomaly
                or self.cross_signal_strength > 0)


def _numeric_size(item_count: int) -> str:
    if item_count == 1:
        return "small"
    return "medium" if item_count <= MEDIUM_ITEM_CEILING else "wide"


def _collection_size(item_count: int, medium_ceiling: int) -> str:
    return "medium" if item_count <= medium_ceiling else "wide"


def _relationship_is_rich(profile: DataProfile) -> bool:
    """Does this relationship have enough structure to earn a full chart?

    The answer differs by KIND, and conflating them was a real bug. A heatmap's
    richness is its EXTENT — both axes must carry at least two values, because a
    1×N strip has one row and therefore no second dimension at all. Cell count
    cannot substitute: a single workspace with five distinct failure root causes
    has five cells and one row, and publishing that as a wide heatmap asserts a
    dimension the data does not have — exactly what this module exists to stop.
    That shape is the normal one for a single-workspace user, not a corner case.

    Scatter and slope never populate row/column counts (their axes are
    continuous), so for them the number of marks IS the richness.
    """
    if profile.relationship_kind == "heatmap":
        return (profile.row_count >= RELATIONSHIP_RICH_ROWS
                and profile.column_count >= RELATIONSHIP_RICH_COLUMNS)
    return profile.item_count >= RELATIONSHIP_RICH_POINTS


def _relationship_decision(profile: DataProfile) -> CardDecision:
    """A relationship must prove it is two-dimensional before it is drawn."""
    if profile.dimensions != 2 or profile.relationship_kind is None:
        raise ValueError(
            "relationship requires two dimensions and an explicit kind; "
            f"got dimensions={profile.dimensions}, "
            f"kind={profile.relationship_kind!r}"
        )
    if profile.relationship_kind not in _RELATIONSHIP_KINDS:
        raise ValueError(
            f"unknown relationship kind {profile.relationship_kind!r}; "
            f"expected one of {_RELATIONSHIP_KINDS}"
        )
    rich = _relationship_is_rich(profile)
    return CardDecision(
        card_type="relationship",
        size="wide" if rich else "medium",
        visualization=profile.relationship_kind,
        reason=("two-dimensional relationship with enough marks to read"
                if rich else
                "two-dimensional relationship, too thin for a full chart"),
    )


def choose_card(profile: DataProfile) -> CardDecision:
    """Map a data profile onto the approved CardType/size/visualization matrix.

    Raises `ValueError` on a profile that cannot honestly be published — an
    empty dataset, or a `relationship` without two dimensions and a kind. That
    is deliberate: silently emitting an empty card is the failure mode this
    whole module exists to prevent, so the caller must decide to omit.
    """
    if profile.item_count < 1:
        raise ValueError("item_count must be positive")

    if profile.semantic in ("scalar", "timeseries"):
        return CardDecision(
            card_type="metric",
            size=_numeric_size(profile.item_count),
            visualization="series" if profile.semantic == "timeseries" else None,
            reason="numeric metric shape",
        )
    if profile.semantic == "ranking":
        return CardDecision(
            "barList", _collection_size(profile.item_count, MEDIUM_ITEM_CEILING),
            None, "ordered Top-N shape")
    if profile.semantic == "composition":
        return CardDecision(
            "stackedBar", _collection_size(profile.item_count, MEDIUM_ITEM_CEILING),
            None, "parts-of-whole shape")
    if profile.semantic == "relationship":
        return _relationship_decision(profile)
    if profile.semantic == "actions":
        return CardDecision(
            "todoList", _collection_size(profile.item_count, MAX_ACTIONS),
            None, "bounded action set")
    if profile.semantic == "narrative":
        many = profile.item_count > 1
        return CardDecision("digest" if many else "insight",
                            "wide" if many else "medium",
                            None, "narrative content")
    raise ValueError(f"unknown data semantic: {profile.semantic!r}")


def _priority(candidate: CardCandidate) -> tuple:
    """Deterministic rank: result → anomaly → cross value → recency → cost.

    Every component is inverted where "more is better" so a plain ascending
    sort reads highest-priority first, and the final `card.id` makes the order
    total — two otherwise identical candidates can never swap between runs.
    """
    return (
        -int(candidate.requires_action),
        -int(candidate.is_anomaly),
        -candidate.cross_signal_strength,
        -candidate.freshness,
        -candidate.source_coverage,
        candidate.reading_cost,
        candidate.order,
        candidate.card.id,
    )


@dataclass(frozen=True)
class BudgetResult:
    """What the budget admitted, and where the first screen ends.

    `lead_count` is returned rather than left to be re-derived, because it
    CANNOT be recovered from `selected` alone: the tail is re-sorted into
    authored order, so counting cards off the front of the result can sweep a
    low-priority tail container into the lead. That is not a cosmetic slip —
    the caller rewrites `order` from this boundary, so a miscount genuinely
    promotes the wrong container onto the reader's first screen.
    """

    selected: list[CardCandidate]
    lead_count: int

    @property
    def lead(self) -> list[CardCandidate]:
        return self.selected[:self.lead_count]

    @property
    def tail(self) -> list[CardCandidate]:
        return self.selected[self.lead_count:]

    def __iter__(self):
        """Iterating a result yields its candidates, so callers that only care
        about what was admitted can treat it as the list it replaced."""
        return iter(self.selected)

    def __len__(self) -> int:
        return len(self.selected)

    def __getitem__(self, index):
        return self.selected[index]


def _admit(candidates: Sequence[CardCandidate], max_cards: int,
           first_screen: int) -> tuple[list[CardCandidate], int]:
    """Rank, then admit while the card budget lasts. Returns (selected, lead).

    Admission is ALL-OR-NOTHING per candidate: one too heavy for the remaining
    budget is skipped and a lighter, lower-priority one may take its place. That
    keeps a multi-card section whole — half of it is not a smaller version of
    it, just an uninterpretable stump.

    The first screen is a CONTIGUOUS prefix in the same currency: it closes at
    the first candidate that would overrun it rather than skipping ahead to a
    smaller one further down, because a reader cannot jump a section.
    """
    selected: list[CardCandidate] = []
    spent = 0
    lead_count = 0
    lead_spent = 0
    lead_open = True
    for candidate in sorted(candidates, key=_priority):
        cost = max(1, candidate.weight)
        if spent + cost > max(0, max_cards):
            continue
        selected.append(candidate)
        spent += cost
        if lead_open and lead_spent + cost <= max(0, first_screen):
            lead_count += 1
            lead_spent += cost
        else:
            lead_open = False
    return selected, lead_count


def select_with_budget(candidates: Sequence[CardCandidate],
                       max_cards: int = MAX_CARDS,
                       first_screen: int = FIRST_SCREEN_CARDS,
                       ) -> BudgetResult:
    """Apply the daily information budget to already-built cards.

    Three things happen, in order:

      1. **Omission.** A stable detail card with no action, anomaly, or cross
         value is dropped outright — a card pushed to the bottom still costs
         the reader the scroll.
      2. **Ranking + admission.** The rest are ranked by `_priority` and
         admitted while the budget lasts, spent in `weight` (published cards),
         so a candidate standing for five cards costs five rather than one.
      3. **Lead/tail split.** `lead_count` marks where the first screen ends.
         The whole selection stays in PRIORITY order — including the tail —
         because the consumer renumbers from this sequence, so the order here
         IS the order the reader gets. A caller wanting authored order for the
         tail can sort `result.tail`, having been told where it starts.

    Returns a `BudgetResult` carrying the explicit `lead_count`. The boundary is
    part of the decision, not something a caller can recover afterwards: once
    weights differ, re-counting cards off the front cannot reconstruct where
    admission actually closed the screen.

    ## No cross-candidate redundancy suppression

    Deliberately absent. A candidate here stands for a whole container, but
    redundancy between cards is per card, so suppressing a candidate to remove
    one duplicated number deletes every unrelated card beside it. Attempting it
    in two passes (suppress against provisionally-admitted providers) is worse
    still, because admission is not monotone: `_admit` skips an over-budget
    candidate and lets a lighter one take its place, so removing a candidate can
    change WHICH others fit and evict the very provider that justified the
    suppression — losing both cards and the signal entirely. Card-level
    redundancy belongs to whoever builds both cards.

    Pure and total: an empty input yields an empty result, and it is identical
    regardless of the input's order.
    """
    eligible = [c for c in candidates if c.carries_signal or not c.is_detail]
    selected, lead_count = _admit(eligible, max_cards, first_screen)
    return BudgetResult(selected, lead_count)
