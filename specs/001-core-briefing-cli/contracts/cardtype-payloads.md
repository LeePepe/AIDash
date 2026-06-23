# Contract: CardType Payload Schemas

> Per-CardType Codable struct definitions. The schema source of truth for
> what each card carries. Mirrors `AIDashCore/Models/Payloads/`.
> When in doubt: the Swift source file wins, this doc is a human-readable
> mirror.

---

## How to read

Each CardType has:
1. A Swift struct definition (the actual schema).
2. An example payload JSON.
3. Notes on how the renderer adapts the payload to different sizes.

---

## `metric`

A collection of named numeric values with optional trend indicators.

```swift
public struct MetricPayload: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let label: String
        public let value: Double
        public let unit: String?
        public let trend: Trend?

        public enum Trend: String, Codable, Sendable {
            case up, down, flat
        }
    }
    public let items: [Item]
}
```

**Example**:
```json
{
  "items": [
    {"label": "PRs merged", "value": 3, "trend": "up"},
    {"label": "Build time", "value": 124, "unit": "s", "trend": "down"},
    {"label": "Test coverage", "value": 87.5, "unit": "%", "trend": "flat"},
    {"label": "Active issues", "value": 12}
  ]
}
```

**Size-driven rendering**:
- `small`: show only `items[0]` (largest font, primary metric)
- `medium`: show `items[0...1]` side by side
- `wide`: show all items in a horizontal strip or grid
- `hero`: show all items prominently with trend chart sparkline (post-v1)

**Validation**: `items.count >= 1`.

---

## `insight`

A short prose insight with optional citations.

```swift
public struct InsightPayload: Codable, Sendable {
    public struct Citation: Codable, Sendable {
        public let label: String
        public let url: String
    }
    public let title: String
    public let body: String
    public let citations: [Citation]?
}
```

**Example**:
```json
{
  "title": "Sapphire test suite is the bottleneck",
  "body": "Over the past week, 64% of CI time was spent in Sapphire integration tests. Splitting these into a separate workflow would reduce average PR feedback time by ~40s.",
  "citations": [
    {"label": "PR #2104 timing", "url": "https://github.com/example/sapphire/pull/2104/checks"},
    {"label": "Workflow runs", "url": "https://github.com/example/sapphire/actions"}
  ]
}
```

**Size-driven rendering**:
- `small`: title only
- `medium`: title + truncated body (~150 chars)
- `wide`: title + full body, citations collapsed
- `hero`: title + body + expanded citations

**Validation**: `title` and `body` non-empty.

---

## `agentSummary`

What a specific agent did during some window.

```swift
public struct AgentSummaryPayload: Codable, Sendable {
    public struct Completed: Codable, Sendable {
        public let title: String
        public let ref: String?
    }
    public struct Stat: Codable, Sendable {
        public let label: String
        public let value: Double
    }
    public let agentName: String
    public let completed: [Completed]
    public let stats: [Stat]?
}
```

**Example**:
```json
{
  "agentName": "multica/sapphire",
  "completed": [
    {"title": "Fixed SAP-301 crash on launch", "ref": "https://example.com/pr/4521"},
    {"title": "Migrated Activity Tabs to new design system", "ref": "https://example.com/pr/4522"},
    {"title": "Added telemetry for tab switching", "ref": "https://example.com/pr/4530"}
  ],
  "stats": [
    {"label": "PRs", "value": 3},
    {"label": "Hours active", "value": 6.5},
    {"label": "Tokens used", "value": 1_200_000}
  ]
}
```

**Size-driven rendering**:
- `small`: agent name + total PR count from stats
- `medium`: agent name + completed[0...1] + most relevant stat
- `wide`: agent name + completed[0...4] + all stats
- `hero`: agent name + all completed + all stats + a small "spent the day on" pull-quote

**Validation**: `agentName` non-empty; `completed.count >= 1`.

---

## `todoList`

A list of tasks for the user (informational — user does not check off
in-app; spec D17 limits user actions to done/star at the card level).

```swift
public struct TodoListPayload: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let title: String
        public let priority: Priority?
        public let due: Date?
        public let ref: String?

        public enum Priority: String, Codable, Sendable {
            case low, medium, high
        }
    }
    public let items: [Item]
}
```

**Example**:
```json
{
  "items": [
    {"title": "Review Sapphire PRs from Multica overnight", "priority": "high"},
    {"title": "Reply to performance review feedback", "priority": "medium", "due": "2026-06-24T17:00:00Z"},
    {"title": "Update VitalStride changelog", "priority": "low"}
  ]
}
```

**Size-driven rendering**:
- `small`: count + highest-priority item title
- `medium`: top 3 by priority (high > medium > low)
- `wide`: all items
- `hero`: all items with expanded due-date / ref panel

**Validation**: `items.count >= 1`.

---

## `trending`

External signal: what's hot in a particular topic.

```swift
public struct TrendingPayload: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let title: String
        public let url: String
        public let score: Double?
    }
    public let topic: String
    public let items: [Item]
}
```

**Example**:
```json
{
  "topic": "Swift / iOS news",
  "items": [
    {"title": "Swift 6.1 announces native macro caching", "url": "https://swift.org/blog/...", "score": 487},
    {"title": "SwiftData query builder refactor", "url": "https://...", "score": 312},
    {"title": "iOS 26.2 beta available", "url": "https://...", "score": 200}
  ]
}
```

**Size-driven rendering**:
- `small`: NOT recommended (topic + count only — too sparse)
- `medium`: NOT recommended
- `wide`: topic + items[0...4] with titles + scores
- `hero`: topic + items[0...7] with titles + scores + sparkline of score distribution

**Validation**: `topic` non-empty; `items.count >= 1`.

**Note**: Even though `small`/`medium` are not recommended in v1, the
renderer must still handle them (degrade gracefully) — spec FR-012 requires
every type render at every size.

---

## `digest`

A long-form AI-written narrative for the day. Typically one per briefing.

```swift
public struct DigestPayload: Codable, Sendable {
    public struct Section: Codable, Sendable {
        public let heading: String
        public let paragraphs: [String]
    }
    public let title: String
    public let body: String
    public let sections: [Section]?
}
```

**Example** (minimal):
```json
{
  "title": "Tuesday at a glance",
  "body": "Yesterday was a moderate-pace day. Multica handled three Sapphire PRs without intervention, including the SAP-301 crash that had been blocking the v9 release. The new design system migration is now 70% complete. Today's main blocker is the performance review feedback — your director needs the response by 5 PM."
}
```

**Example** (with structured sections):
```json
{
  "title": "Tuesday at a glance",
  "body": "Brief overview...",
  "sections": [
    {
      "heading": "What got shipped",
      "paragraphs": ["Sapphire merged 3 PRs overnight.", "The crash that was blocking v9 is fixed."]
    },
    {
      "heading": "What's blocking today",
      "paragraphs": ["Performance review feedback (due 5pm).", "Decision needed on Q3 priorities."]
    }
  ]
}
```

**Size-driven rendering**:
- `small`: title only
- `medium`: title + truncated body (~200 chars)
- `wide`: title + body + first section
- `hero`: title + body + all sections, full layout

**Validation**: `title` and `body` non-empty.

---

## `sectionHeader`

Visual grouping inside a container (the escape hatch for "I want a sub-
heading without nesting containers" — see spec D9).

```swift
public struct SectionHeaderPayload: Codable, Sendable {
    public let title: String
    public let subtitle: String?
}
```

**Example**:
```json
{
  "title": "Engineering",
  "subtitle": "Backend, infra, tooling"
}
```

**Size-driven rendering**: all sizes show the same header layout. Size
hint affects vertical spacing only (small = compact, hero = generous).

**Validation**: `title` non-empty.

---

## Validation summary

For every CardType, `SchemaValidator.validate(type:, payload:)` performs:

1. JSON decode into the typed payload struct — failures map to
   `schema.payload_decode_failed` with `field` set to the first failing
   key.
2. Type-specific invariants (e.g. `items.count >= 1` for collections).
3. Payload size check (`<= 256 KB`).

The CLI runs this check locally before XPC dispatch (per `research.md`
§R-2 fast-feedback design). The app re-runs it server-side as defense in
depth.

---

## Forward-compatibility notes

- Adding a new optional field to any payload struct: zero migration. Old
  records lack the field, JSONDecoder yields `nil`, app renders without
  it.
- Adding a new required field: requires a default value supplied by the
  decoder (`@Default`-style initializer); plan a 2-release rollout
  (release 1: write old + new; release 2: require new).
- Adding a new CardType: see plan.md §"Adding a new card type" (post-v1
  workflow doc).
- Removing a field: never do this in a patch release. Mark deprecated,
  ignore, then remove in a major release.

---

## Quick reference: which types make sense at which sizes

| type \ size | small | medium | wide | hero |
|---|:---:|:---:|:---:|:---:|
| metric | ✓ main | ✓ main | ✓ | ✓ |
| insight | ⚠ thin | ✓ main | ✓ main | ✓ |
| agentSummary | ⚠ thin | ✓ | ✓ main | ✓ |
| todoList | ⚠ thin | ✓ | ✓ main | ✓ |
| trending | ⚠ degrade | ⚠ degrade | ✓ main | ✓ main |
| digest | ⚠ degrade | ⚠ degrade | ✓ | ✓ main |
| sectionHeader | ✓ | ✓ | ✓ | ✓ |

✓ = renders well, ⚠ = renders but doesn't shine. This is a hint to
agents, **not enforced** — spec FR-012 requires all combinations work.
