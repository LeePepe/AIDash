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

    `provides` / `redundant_with` name SIGNALS, not cards. A raw token card
    declares `redundant_with=("outcome_x_tokens",)` — "I restate whatever says
    that, more weakly" — and the cross card declares it `provides` it. Naming
    the signal rather than the card id means the suppression survives a card
    being renamed, resized, or built by a different producer.
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
    provides: tuple[str, ...] = ()
    redundant_with: tuple[str, ...] = ()

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
    rich = (profile.item_count >= RELATIONSHIP_RICH_POINTS
            or (profile.row_count >= RELATIONSHIP_RICH_ROWS
                and profile.column_count >= RELATIONSHIP_RICH_COLUMNS))
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


def _is_superseded(candidate: CardCandidate,
                   supplied: dict[str, set[Any]]) -> bool:
    """True when a STRONGER card already carries every signal this one restates.

    An actionable card is never suppressed — "you already know this" is a fair
    thing to say about a description, not about something asking to be done.
    `supplied` maps each signal to the ids of the cards providing it, so a card
    naming a signal it also provides cannot suppress itself.
    """
    if candidate.requires_action or not candidate.redundant_with:
        return False
    return any(
        supplied.get(signal, set()) - {candidate.card.id}
        for signal in candidate.redundant_with
    )


def select_with_budget(candidates: Sequence[CardCandidate],
                       max_cards: int = MAX_CARDS,
                       first_screen: int = FIRST_SCREEN_CARDS,
                       ) -> list[CardCandidate]:
    """Apply the daily information budget to already-built cards.

    Four things happen, in order:

      1. **Redundancy suppression.** A card that restates a signal another card
         already carries more strongly is dropped — a weaker duplicate spends
         first-screen budget without adding anything.
      2. **Omission.** A stable detail card with no action, anomaly, or cross
         value is dropped outright.
      3. **Ranking + cap.** The rest are ranked by `_priority` and truncated to
         `max_cards`.
      4. **Lead/tail split.** The top `first_screen` keep their priority order —
         they are what a two-minute read gets. Everything after returns to the
         authored order, so the detail tail still reads as the author arranged
         it rather than as a second priority list.

    Pure and total: an empty input yields an empty list, and the result is
    identical regardless of the input's order.
    """
    supplied: dict[str, set[Any]] = {}
    for candidate in candidates:
        for signal in candidate.provides:
            supplied.setdefault(signal, set()).add(candidate.card.id)

    eligible = [
        c for c in candidates
        if (c.carries_signal or not c.is_detail) and not _is_superseded(c, supplied)
    ]
    ranked = sorted(eligible, key=_priority)
    selected = ranked[:max(0, max_cards)]
    lead = selected[:max(0, first_screen)]
    tail = sorted(selected[max(0, first_screen):],
                  key=lambda c: (c.order, c.card.id))
    return lead + tail
