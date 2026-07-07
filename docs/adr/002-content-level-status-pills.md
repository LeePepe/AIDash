# ADR-002: Content-Level Status Pills and Metric Data-Viz

## Status

Accepted (constitution 1.6.0)

## Context

`design/north-star.md` defines the target visual language: a modern
dashboard with colored status pills, per-KPI sparklines / ring gauges, and
luminance-tier card elevation. DesignKit already **ships** the components
for this — `StatusPill`, `Sparkline`, `RingGauge`, `theme.neutrals` tiers,
`Space.contentMaxWidth` — and DesignKit's own tech-context red_line already
states "status uses colored pills, never grey text."

But the constitution's Principle VI ("Three Orthogonal Card Dimensions")
restricted `style` to a 3pt left stripe and forbade any other colored
affordance, and its Quality Bar §I P0 mechanically fails a `CardView` that
renders a colored `background(...)` fill. Read literally, that rule also
forbids a `StatusPill` capsule — putting the constitution in direct tension
with both DesignKit and north-star, and blocking the UI modernization the
user asked for.

The tension is really a category error: the rule was written to stop
`style` from becoming a whole-card color channel that competes with the
type icon. A status pill is not a `style` affordance at all — it is a
**content** signal, exactly like the trend arrow that Principle VI already
exempts as "content, not card chrome."

## Decision

Amend the constitution (1.6.0) to name a `style` / content boundary
explicitly:

- The `style` dimension stays **stripe-only** — unchanged. No colored
  card fills driven by `style`.
- A new §Content-Level Status Pills sanctions `StatusPill` as a
  payload-driven content signal (todo `priority`, metric `trend`,
  trending `score`), colored from semantic/primary tokens. A card whose
  payload has no status field renders no pill. Payloads may not invent a
  status field solely to draw a pill.
- A new §Metric Data-Viz sanctions optional `series` (sparkline) and
  `ratio` (ring gauge) on metric items, with a size-neutral render height
  so the chart never conflates `size` with `type`.
- Quality Bar §I P0.3 and reviewer step 4 are clarified so pills and
  data-viz are not flagged as forbidden `style`-driven fills.

## Rationale

- Reuses the exact precedent already in the constitution (the trend-arrow
  "content not chrome" exception), so orthogonality of (type, size, style)
  is preserved: pills and charts vary by **payload**, not by any of the
  three chrome dimensions.
- Legitimizes what DesignKit already exports and what its frontmatter
  red_line already mandates, removing a standing contradiction rather than
  adding a new one.
- Colors still come only from tokens, so the "no inlined hex / system
  color in a view" rule is untouched.

## Alternatives considered

1. **Whole-card colored background tint for status** — rejected by the
   original Principle VI reasoning: indistinguishable at low opacity,
   dominating at high opacity. Not revisited.
2. **A second stripe color / thicker stripe for status** — overloads the
   one channel `style` already owns; can't express per-row status inside a
   list card (e.g. a todo list with mixed priorities).
3. **Grey text for status** — the failure mode north-star and DesignKit's
   red_line explicitly reject; low signal, reads as "everything the same."
4. **Leave the constitution as-is and skip pills** — keeps a permanent
   contradiction with DesignKit and abandons the requested modernization.

## Consequences

- The AIDashUI implementation may render `StatusPill`s from payload fields
  and metric sparkline/ring data-viz without tripping the AI Reviewer.
- The existing AIDashUI compliance tests pin the old chrome/spacing
  literals; they are updated in lockstep with the implementation PR (noted
  in the 1.6.0 migration note).
- Card and page backgrounds move from system materials to
  `theme.neutrals.card` / `theme.neutrals.bg`; this is a visual change
  reviewers should confirm on macOS (where system material carried
  vibrancy) and in dark mode.
