# AIDash Constitution

> **Mission**: A personal AI briefing dashboard that auto-updates every morning.
> Agents complete tasks in the background and push content via CLI; the user
> only reads.

This constitution governs every spec, plan, task, and implementation in this
repository. It is intentionally short. When in doubt, re-read it.

---

## Core Principles

### I. Agent-Authored, User-Read (NON-NEGOTIABLE)

The app contains **no input fields, no chat, no compose surface**. Agents are
the sole authors of all displayed content. The user's only briefing-content
outbound channel is a small set of structured UI events (done / undone / star /
hide, plus Team Workflow Audit finding acknowledgement and remediation-approval
receipts) that are append-only and consumed by agents on their own schedule. An
audit approval records Owner intent only: it never authorizes AIDash to
remediate, mutate a source issue or run, create work, or dispatch an agent. The
optional, explicit-consent GUI product telemetry defined by §GUI Product
Telemetry is operational measurement, not briefing content or a new authoring
channel. The app never modifies or interprets briefing content — it only
renders what agents have published.

This principle constrains every design decision downstream. If a feature
requires the user to type content, it does not belong in this app.

### II. Strict Separation: CLI Writes, App Reads, Both Sync via CloudKit

There is exactly one write path into briefing content (the CLI) and exactly
one write path for user events (the app). The CLI lives only on macOS and is
the public API for agents — agents shell out to `aidash …`, they do not talk
to CloudKit, files, or any internal API directly.

```
Agent (Python/shell — in this repo, `aidata/`)
  └─> aidash CLI (Swift binary, macOS only)
        └─> CloudKit Private DB (briefings record type)

App (macOS / iPadOS / iPhone, SwiftUI)
  ├── reads briefings from CloudKit
  └── writes user events to CloudKit (events record type)

Agent (Python/shell)
  └─> aidash CLI
        └─> reads events from CloudKit (pulls user feedback async)
```

The two record types are independent. The app never writes briefings; the CLI
never writes events. This boundary is the most important one in the project —
violations are constitutional, not stylistic.

`aidata/` living in this repo does **not** soften that boundary. It is an agent
like any other: it holds no CloudKit credentials, opens no network path to
CloudKit, and reaches the app only by shelling out to `aidash`. Sharing a
repository buys atomic commits across the producer/renderer seam — it grants no
new privileges. Any change that lets Python touch CloudKit, the app's storage,
or an internal API directly is a constitutional violation.

### III. Glanceable Daily Briefing and Favorites (NON-NEGOTIABLE)

The product unit is a single day's briefing. Hierarchy is flat: `Briefing →
Container → Card`, exactly two levels of nesting, no deeper. Containers must
not contain other containers; if visual grouping is needed inside a container,
use a `sectionHeader` card, not a nested container. This matches Apple HIG
("no more than two levels of hierarchy"), Apple News, Apple Health, Apple
Fitness, and Google Discover.

The intended reading time is five minutes. Any feature that pushes users into
a navigation tree, search, history, detail page, or drill-down is suspect.

Favorites are a peer view to the daily briefing, not a deeper level of
briefing hierarchy. Favorites may show local card snapshots and their current
favorite state, but MUST NOT become an archive, search, or detail-navigation
surface.

### IV. Schema-Locked Card Types, Data-Driven Layout

Card content is partitioned into three independent dimensions:

- **type** — strongly typed enum (e.g. `metric`, `insight`, `agentSummary`,
  `todoList`, `trending`, `digest`, `sectionHeader`). Adding a new type
  requires a coordinated release of both app and CLI; the CLI must reject any
  unknown type.
- **size** — `small | medium | wide | hero`. Every type renders at every
  size; the renderer decides density (e.g. `metric` at `small` shows one
  number, at `wide` shows the top eight).
- **style** — `neutral | success | warning | accent`. Pure visual variant,
  no semantic constraint.

The CLI is the schema's authoritative source: `aidash --help`, `aidash card
put --help`, and `aidash schema list` are sufficient for an agent to write
correct payloads without reading code or docs. Hidden, undocumented, or
optional-but-required fields are forbidden.

### V. Container as Generic Render Slot

Containers carry no product semantics (no enum of "Yesterday", "Today",
"Trending"). Agents choose container `title`, `subtitle`, `order` (sparse int)
and `layout` (`auto | list | grid | hero`) per briefing. The app does not know
which container "means" yesterday's work — it just renders what arrives.

This is intentional: it pushes business logic out of the app and into the
agents, where it belongs. The same app build serves any agent strategy
(per-tab agents, single planner agent, mixed) without code changes.

### VI. Three Orthogonal Card Dimensions (NON-NEGOTIABLE)

The `type / size / style` trio (Principle IV) is **three independent visual
concerns**. Each dimension owns one thing and one thing only — they may not
overlap. A renderer that conflates two dimensions (e.g. uses `size` to drive
font scale, or uses `style` to mutate card chrome structure) is a
constitutional violation and the Reviewer MUST 🔴 FAIL.

- **`size` = physical geometry only.** It maps to grid columns / explicit
  height / corner radius / padding. It MUST NOT affect typography scale.
  `small` = 1 column, `medium` = 2 columns, `wide` = full row, `hero` =
  full row + double height. Corner radius and padding scale with size
  (see §Design System & Tokens) — that is geometry, not chrome. Density
  across sizes comes from how many items the type renderer chooses to
  show at that geometry, not from shrinking type.
- **`type` = leading icon badge + typography + content density.** Each
  `CardType` owns a 32×32 leading icon badge (SF Symbol + tint color),
  its own font configuration, and a content-density vocabulary. The icon
  badge is the primary type discriminator — a reader scanning the
  briefing tells `metric` from `digest` from `agentSummary` by icon
  glyph first, typography second. Two different types render visually
  distinct even at the same size and style. Type is the "what kind of
  card am I" channel.
- **`style` = semantic signal tint only.** `style` MUST NOT change card
  chrome structure (background material, padding) or the size-driven
  geometry (corner radius). The only permitted style affordance is a
  left-edge accent stripe (3pt hairline; success=`status.success`,
  warning=`status.warning`, accent=`brand.primary`; `neutral` = no stripe).
  Filling the whole card
  with a colored background tint is forbidden — it cannot be
  distinguished at low opacity and dominates the visual at high opacity.
  A colored status pill (`StatusPill`) is NOT a `style` affordance — it
  is a **content signal** (like a trend arrow), driven by payload fields,
  not by the `style` dimension. See §Content-Level Status Pills.

The type icon's tint color and the style stripe color are independent
channels and do not conflict by construction: the icon sits at the top
inside the card (always the same color per type), and the stripe sits
on the left edge (varies by status). A `success` `metric` card has a
green left stripe **and** a blue chart-bar icon — both signals coexist
because they're at different positions with different meanings.

A direct corollary: any single card is uniquely identified by (type,
size, style), and a viewer scanning the briefing MUST be able to tell
type apart by icon glyph + typography, size apart by physical
dimensions + corner radius, and style apart by stripe color —
independently, not jointly.

---

## Technical Constraints

### Platforms & Language

- **OS targets**: macOS 26+, iPadOS 26+, iOS 26+ for the app. macOS 26+ for
  the CLI. Older OS versions are out of scope; we use OS 26 features
  (FoundationModels, latest SwiftUI APIs) without back-compat shims.
- **Language**: Swift 6.0 with strict concurrency.
- **Concurrency**: `@MainActor` is the default for view-layer code. Cross-actor
  calls go through `async`. `@unchecked Sendable`, `nonisolated(unsafe)`, and
  similar escape hatches require an ADR with explicit justification.
- **Off-actor framework callbacks**: System frameworks that deliver delegate
  callbacks on internal queues MUST NOT be wrapped in classes annotated
  `@MainActor`. In particular:
  - `NSXPCListenerDelegate` (e.g. `XPCListener`) — `shouldAcceptNewConnection`
    runs on the listener's own internal serial queue, not the main actor.
    The conforming class MUST be left nonisolated. Per-connection work that
    actually needs main-actor isolation MUST be hopped via the exported
    handlers object (e.g. an `@MainActor XPCHandlers` that hops inside its
    own `execute(requestData:reply:)`), never via `MainActor.assumeIsolated`
    on the delegate callback path (that would trap, violating §D.2 graceful
    XPC failure).
  - Any historical task body (issue checklist) that demands `@MainActor` or
    a `MainActor.assumeIsolated` shim on such a delegate is **superseded by
    this clause** — Reviewer MUST treat the constitutional rule as the
    source of truth and not 🔴 FAIL a PR for omitting the unsafe annotation.
    Reviewer MAY still flag missing functional acceptance (Mach service
    name, exported interface, handlers wiring) — but the actor-isolation
    bullet is no longer a P0.

### Module Architecture

Three SwiftPM packages, two app/CLI targets, one Python data layer, one
workspace:

```
AIDash/
├── Packages/
│   ├── AIDashCore/       Models (Briefing/Container/Card), CloudKit client,
│   │                     schema validation. Zero UI deps. Used by both App
│   │                     and CLI to guarantee schema is sourced from one
│   │                     place.
│   ├── AIDashUI/         Cross-platform SwiftUI views: type renderers,
│   │                     container layouts, briefing scaffold. Depends on
│   │                     Core + shared-design-system.
│   └── shared-design-system/  Strata native products: NativeDesignKit and
│                              DesignTokens. Exact-pinned external dependency.
├── Apps/
│   └── AIDashApp/        macOS + iPadOS + iPhone app target (XcodeGen
│                         managed). Depends on UI + Core + shared-design-system.
├── CLI/
│   └── aidash/           Swift Argument Parser CLI, macOS-only.
│                         Depends on Core. Does not depend on UI.
├── aidata/               Python data layer (L1 collect → L2 normalize →
│                         L3 merge → L4 serve → L5 digest). The sole
│                         producer of briefing content. NOT a SwiftPM
│                         package; imports no Swift, is imported by none.
├── Configs/
│   └── Identity.xcconfig Bundle ID / CloudKit container / dev team —
│                         single source, with a git-ignored local override.
└── project.yml           XcodeGen config for app + CLI targets.
```

Dependency direction is unidirectional: `UI → Core`, `UI → shared-design-system`,
`App → UI + Core + shared-design-system`, `CLI → Core`. The shared design
system is an ADR-006-approved dependency pinned to an exact revision. Its
native products are `NativeDesignKit` and `DesignTokens`, and they are the
sole design-system source for the AIDash pilot. The CLI may never import UI.
The package boundary enforces this.

`aidata/` sits **outside** that graph. It couples to the Swift side by a
one-way **data flow**, not a compile-time dependency: it emits card payloads
(JSON) that reach the app through the `aidash` CLI's XPC seam. The contract is
the payload *shape*, defined by `AIDashCore/Models/Payloads/`. No compiler
checks it across the language boundary, so briefing-content changes MUST go
through the layer-through discipline in `.claude/skills/aidash-content/` and
its `contract_check.sh` lint.

### Persistence

- **Briefings**: CloudKit Private DB, custom record type `Briefing` containing
  serialized `Container[]` payload. Sync handled by `NSPersistentCloudKitContainer`
  or direct `CKDatabase` calls — decided in plan phase.
- **Events**: CloudKit Private DB, custom record type `UserEvent`, append-only.
- **App-local cache**: SwiftData mirror of the last fetched briefing for
  offline display. Cache is disposable; CloudKit is source of truth.
- **Favorite snapshots**: one independent local SwiftData store and storage
  file for cards explicitly favorited by the user. This local-only snapshot
  exception is not a mirror of previous briefings: it MUST NOT be included in
  any CloudKit schema or synchronized between devices. If unavailable, the
  Favorites view shows the item as unavailable; the underlying event remains
  authoritative.
- **No third-party storage**, except the isolated telemetry storage authorized
  by §GUI Product Telemetry (no Firebase, no Realm, and no local SQLite outside
  SwiftData or that exception).

### GUI Product Telemetry (explicit-consent exception)

AIDash MAY report a narrow, typed set of GUI action and performance events to
an isolated Azure Blob telemetry store only under all of these conditions:

- The sole consent authority is a GUI Settings toggle labelled **Send usage
  data**. Consent defaults to off and is persisted locally in `UserDefaults`.
  Existing installs also begin off. Missing or malformed consent is off.
- The first opt-in creates a random install UUID and persists it locally.
  Later launches and consent cycles reuse it for the app's lifetime. Version 1
  exposes no install-ID Reset or rotation. Adding one is a separate future SDK
  feature and product decision; it MUST NOT be approximated by parsing private
  telemetry storage.
- Turning consent off first persists the false value, closes new event
  admission immediately, disables/cancels active delivery, and only then awaits
  quiescence. No queued or later upload may start or continue while consent is
  off. Any in-flight request made ambiguous by cancellation remains retained
  and unconfirmed. The isolated local telemetry store and pending work remain
  intact. Turning the toggle on again is fresh consent and resumes eligible
  retained work under the same install UUID.
- Only GUI app composition may construct the service. CLI, headless/XPC, and
  test-host production composition never constructs the service, telemetry
  store, uploader, or timer. Hostless tests may construct isolated preference
  and coordinator fakes; they never use the user's defaults or data.
- Event names, triggers, typed property allowlists, sampling, and cardinality
  are product-local closed contracts. Free text, briefing/UserEvent content,
  user-entered values, device/hardware identity, file paths, and unknown or
  non-finite properties are forbidden. The whole unsafe event is rejected
  before accepted persistence or network transmission.
- The telemetry dependency's isolated queue/sidecars and the Azure Blob
  telemetry store are the sole third-party storage exception. They MUST NOT
  contain briefings or CloudKit `UserEvent` records, and they do not change the
  CLI-write/app-read/CloudKit rules in Principle II.
- No install identity, telemetry store, uploader, or network work exists before
  first opt-in. Invalid producer configuration may still leave the authorized
  local consent and install-ID preferences, but creates no telemetry service,
  store, uploader, timer, or network work.

### Dependencies

- **Default**: prefer Apple frameworks (CloudKit, SwiftUI, SwiftData,
  URLSession, Foundation).
- **Allowed without ADR**: `swift-argument-parser` (Apple-maintained, required
  for the CLI).
- **Any other third-party dependency** requires a short ADR (under
  `docs/adr/`) that answers: what problem, what alternatives, what binary-size
  / build-time / Swift 6 concurrency cost. ADR-006 approves the exact-pinned
  Strata shared-design-system dependency for the AIDash Goal C pilot; its
  native products are `NativeDesignKit` and `DesignTokens`. No floating range
  or additional design-system source is allowed. Do not introduce dependencies
  speculatively.
- **Networking**: `URLSession` + async/await for HTTP. The explicit-consent GUI
  telemetry channel in §GUI Product Telemetry is the app's only current HTTP
  requirement; CloudKit is not HTTP. Adding another HTTP purpose or an HTTP
  client (Alamofire or similar) requires an ADR.
- **App-side LLMs**: not implemented in v1. If we add on-device summarization
  later, use Apple's `FoundationModels` framework, not third-party SDKs.

### Error Handling

- No `fatalError`, no `try!`, no `as!` in production code. Use `Result`,
  `throws`, or graceful fallback.
- CloudKit failures degrade gracefully: app shows "last synced HH:MM" + cached
  briefing. The app never blocks the user on a network error.
- CLI failures exit non-zero with structured JSON on stderr that agents can
  parse: `{"error": "...", "code": "...", "field": "..."}`. Human-readable
  fallback is fine when `--json` is not set.

### Testing

Three gates, in priority order:

1. **Build gate** — the workspace builds for all platforms (macOS app +
   iPadOS app + iPhone app + CLI) on every PR. No exceptions.
2. **Core unit-test gate** — `AIDashCore` (models, schema validation, CLI
   argument parsing) has unit tests. Adding or changing a card type requires
   an updated test for its payload encode/decode round-trip.
3. **UI tests are not required.** SwiftUI views are exempt from automated
   UI-test gates. Manual or hardware smoke tests are not merge blockers;
   agents validate UI work with build gates, previews, contract checks, and
   reviewer inspection. The user will provide product feedback naturally while
   using the app; that feedback becomes follow-up issues, not a pre-ship gate.

#### Who runs tests (NON-NEGOTIABLE)

**The git hooks run the tests. A human or agent working locally does not.**

`scripts/hooks/pre-commit` and `pre-push` resolve changed paths and run the
owning leaves' declared **local** gates (SPM build/tests and focused repository
checks). Heavy App/CLI/XcodeWorkspace builds are CI-only. Running suites by
hand on top of the hook-driven gates adds no signal and is how the two worst
incidents in this repo happened.

- **Never run a host-based test target locally.** `AIDashAppTests` pins
  `TEST_HOST` to the real `AIDash.app`, so the bundle executes AS the
  production app: same bundle id, same real home, freshly re-signed each
  build. Two consequences, both observed for real:
  1. macOS re-prompts for TCC access (Contacts / iCloud — the app container
     symlinks to them) on EVERY run.
  2. Code that resolves the real home operates on the user's live data. A
     test once moved the developer's SwiftData store into a temp directory
     and deleted it on teardown.
- **Hook-owned local verification may use the hostless target**, which runs as
  `xctest` with no app launch and no access to the real home. The leaf gate
  declares `AIDashAppLogicTests`; humans and agents inspect the hook receipt and
  do not invoke its `xcodebuild` test command directly.
- **Host-based targets belong to CI** (and to an explicit, human-authorized
  local run). CI machines have nobody to prompt and no live user data.

The rule is deliberately about WHO, not about WHICH: "only run the safe
suites" degrades the moment someone wants to check one more thing. "Let the
hooks do it" has no such failure mode.

### Design System & Tokens

This section is the single source of truth for AIDash visual design. Card
views, container layouts, and any new SwiftUI surface MUST consume these
tokens. Inventing per-view padding/font/color constants is forbidden —
add to this table or amend the constitution first.

#### Two-Level Typography Hierarchy

The UI uses exactly two typography systems. They MUST be visually
distinguishable at a glance: a reader scanning the briefing must
instantly tell "section label" from "card content" without reading
words.

- **Overview tier** (container titles, section dividers, briefing date
  header). Configuration: `.system(.caption2, design: .rounded, weight:
  .semibold)`, color `.secondary`, letter spacing `+0.6pt` (acts as ALL
  CAPS for Latin while keeping CJK readable). This tier is for "where am
  I in the document" labels — never for content.
- **Detail tier** (card content). Each `CardType` declares its own
  typography recipe inside the detail tier (see "Per-Type Typography
  Recipes" below). The detail tier MUST NOT use the overview tier's
  font / color — they are not interchangeable.

The briefing's top-level date header is the one exception that uses
neither tier — it is the **masthead**. It renders once at the very top and
may use a terminal/monospaced treatment: `AIDashTypography.masthead`
(`.system(size: 34, weight: .bold, design: .monospaced)`) for the date, with
an optional status line (`AIDashTypography.mastheadStatus`, monospaced
caption) for the product mark + publish/sync state, closed by a 1px
`theme.neutrals.border` rule. This masthead exception does not license a
third *content* tier — card content stays in the detail tier. (Cockpit theme,
constitution 1.7.0.)

#### Per-Type Visual Recipes (icon badge + typography, detail tier)

`type` owns two visual signals: a leading 32×32 icon badge (primary
discriminator — reader sees the glyph first) AND the detail-tier
typography recipe. `size` MUST NOT mutate either; size only controls how
many items / how much of the payload the renderer chooses to show.

| CardType | Icon (SF Symbol) | Icon tint (transition: chart-family color + glyph; later Strata role) | Primary font | Secondary font | Notes |
|---|---|---|---|---|---|
| `metric` | `chart.bar.fill` | chart-family color + glyph (transition) | `largeTitle` with monospaced digits | `.caption` `.secondary` for label | Hero number always large; unit + trend arrow inline |
| `insight` | `sparkles` | chart-family color + glyph (transition) | `.title3.weight(.semibold)` | `.body` `.primary` for body | Title first, body wraps |
| `digest` | `doc.text.fill` | chart-family color + glyph (transition) | `.headline` for section heading | `.body` `lineSpacing: 4` for paragraphs | Prose; section list expands `body` paragraphs |
| `agentSummary` | `bubble.left.and.bubble.right.fill` | chart-family color + glyph (transition) | `.headline` for agent name | `.callout` for completed; `.caption.monospaced()` for refs | Refs render as capsule chips |
| `todoList` | `checklist` | chart-family color + glyph (transition) | `.body` per row | `.caption2` for priority dot label | Each row leads with a priority color dot |
| `trending` | `chart.line.uptrend.xyaxis` | chart-family color + glyph (transition) | `.callout.monospaced()` for score | `.body` for title | Scores right-aligned mono |
| `relationship` | `point.3.connected.trianglepath.dotted` | chart-family color + glyph (transition) | `.headline` for conclusion | `.caption.monospaced()` for axes/sample/window | Scatter/heatmap/slope; wide uses chart + evidence rail |
| `sectionHeader` | (no badge, no chrome) | — | `.title3.weight(.semibold)` | `.subheadline` `.secondary` | Renders with NO card chrome (raw header inside container) |

#### Relationship visualization

- `relationship` represents a typed relationship, not a chart-shaped CardType.
- `visualization` is `scatter | heatmap | slope` and must match the payload fields.
- Every relationship card carries `sampleSize`, `timeWindow`, and `metricDefinition`.
- A relationship card must never claim causation from observational association.
- Wide/hero may use chart + evidence rail; small/medium reduce visible marks/legend, never font size.

#### Icon badge specification

Every card type except `sectionHeader` renders a 32×32pt leading badge
in the card's top-left corner:

```
ZStack {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(type.iconTint.opacity(0.15))    // soft tinted container
    Image(systemName: type.icon)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(type.iconTint)        // full saturation glyph
}
.frame(width: 32, height: 32)
```

The icon tint colors above come from the Strata classification role
(one case per CardType, resolved via the injected `Theme`). Each is a
calibrated light/dark hex pair chosen to be visually distinguishable at a
glance, follow Apple Settings app icon coding conventions, and carry a
dark-mode variant. Views MUST read the tint from the token (never inline a
`.blue`/`Color(hex:)` literal). During the transition, the raw hex remains
owned by the current DesignKit implementation; the concrete Strata mapping
is a migration input, not an API assertion in this constitution.

Per north-star §11, the transition uses three chart-family colors plus the
type glyph. After the transition, the badge uses the applicable Strata
classification color role; the concrete role mapping is not defined here.
The 32×32 badge remains mandatory (P0.5).

#### Size = Geometry Only (geometry ladders)

`size` is a layout instruction, never a typography hint. Geometry
includes grid columns AND corner radius AND padding — they scale
together so a small card feels tight and a hero feels editorial.

| size | Grid span | Min height | Corner radius | Padding |
|---|---|---|---|---|
| `small` | 1 column (target 200-260pt) | 96pt | 16pt | 12pt |
| `medium` | 2 columns (target 400-520pt) | 140pt | 24pt | 16pt |
| `wide` | full row (all columns) | 140pt (intrinsic) | 24pt | 16pt |
| `hero` | full row, double height | 280pt | 24pt | 24pt |

Container grid columns adapt by viewport: iPhone = 1 col, iPad portrait
= 2 col, iPad landscape / Mac small window = 3 col, Mac large window = 4
col. The card's own size token tells the grid how many columns to span;
the grid itself decides total column count.

##### Content-derived effective size (downgrade-only)

The authored `size` is an **upper bound**, not an exact instruction.
Publishers (a cron, an agent) routinely tag short content with an
oversized `size` — a one-line digest as `hero`, a single-item to-do as
`wide` — which renders as a large, half-empty card (full-row span + a
tall min-height floor with nothing to fill it).

The renderer therefore computes an **effective size** from the payload's
content richness and renders at the smaller of (authored, justified):

- It only ever **shrinks** — an explicitly-`small` card stays small; a
  card is never grown past its authored size.
- It leaves the stored `size` **unchanged** (no schema change; the model
  is untouched).
- It applies the **same** effective size to both the grid column span and
  the card's own geometry (min-height, corner radius, padding), so width
  and height stay coherent — a downgrade is geometry chosen to fit
  content, never a semantic change and never a typography change (detail
  tier still governs type).
- `metric`, `trending`, and `sectionHeader` are **exempt** (their sizing
  is deliberate); `list` layout (`collapseToList`) disables it (list
  forces full-row by contract).

The single source of truth is `EffectiveCardSize.resolve(...)` in
AIDashCore; `TokenGrid` resolves once and feeds both the span and the
`CardRouter` render size. Richness thresholds (section count, body
length, item count) are heuristic and conservative — because the resolver
only ever shrinks, a wrong guess yields a slightly-too-small (or
unchanged) card, never a broken layout.

#### Style = Semantic Signal Only (left stripe, no background fill)

`style` does not change card chrome. It adds (or omits) a 3pt left-edge
accent stripe. Card background, corner radius, padding, and elevation
are identical across all four `style` values.

| style | Stripe color | When agents use it |
|---|---|---|
| `neutral` | none | default; informational |
| `success` | `status.success` | positive outcomes (PR merged, goal hit) |
| `warning` | `status.warning` | attention needed (PR stuck, deadline near) |
| `accent` | `brand.primary` | spotlight / call to action |

Trend arrows inside `metric` cards may still use red / green — these are
content (signal direction), not card chrome.

#### Content-Level Status Pills

Card **content** may express status with a colored pill (the current
DesignKit `StatusPill` during the transition; its concrete Strata mapping is
specified by spec 008 and the Goal B component specification): `Capsule()`
filled at `color.opacity(0.16)` with
full-saturation text/icon). This is the same "content, not chrome"
exception the trend arrow already carries — the pill is driven by
**payload fields**, never by the card's `style` dimension:

- `todoList` item `priority` → tone (high=danger, medium=warning,
  low=neutral).
- `metric` item `trend` → optional tone (up=success, down=danger,
  flat=neutral).
- `trending` item `score` → neutral tone.

Constraints so pills stay a content signal and not a second chrome
channel: the pill color comes from the semantic/primary **tokens**
(never an inlined hex or system color); a pill reflects a payload value,
so a card whose payload carries no status field renders none; and the
`style` dimension remains stripe-only (§Style). Payloads MUST NOT invent
a status field solely to draw a pill — only the fields above drive pills.

#### Metric Data-Viz (sparkline / bar-spark / ring / segmented gauge)

`metric` items may carry optional visualization data, rendered beside the
value to give numbers visual context (north-star §6/§7):

- `series: [Double]?` → a mini trend chart: either a **sparkline** (line +
  area gradient) or a **bar-spark** (`Sparkbars`, discrete bars normalized
  across the series' own min…max so a gentle slope still reads), axes hidden,
  colored from a chart/semantic token. The cockpit theme uses the bar-spark.
- `ratio: Double?` (0…1) → a ratio gauge — either a **ring gauge**
  (`RingGauge`) or a **segmented capacity gauge** (`SegmentedGauge`, a row of
  lit/unlit segments) — which **replaces** the trend chart for ratio-type
  metrics. The cockpit theme uses the segmented gauge.

Both are optional content: absent → nothing drawn. The chart's fixed
render height is geometry-neutral — it MUST NOT branch on the card's
`size` dimension (that would conflate size with type; §Size = Geometry
Only). The current DesignKit implementation supplies the data-viz components
during the transition; their concrete Strata mapping is specified by spec 008
and the Goal B component specification. Which trend/ratio form is drawn
remains a theme choice, not a payload or `size` concern. (Cockpit theme,
constitution 1.7.0.)

#### Card Chrome (shared structure, size-scaled geometry)

Every card view shares the same outer chrome structure and rendering
recipe. Per-card override is forbidden. The only values that change
across cards are geometry (corner radius, padding — both driven by
`size`), the optional left stripe (driven by `style`), and whether the
frame is drawn at all (driven by the container's card COUNT — see
§Container Chrome Modes below).

- Background: `theme.neutrals.card` — the middle luminance tier of the current
  DesignKit neutral system during the transition (page `bg` < card `card` <
  inner `inner`). Its concrete Strata mapping is specified by spec 008 and the
  Goal B component specification.
  Cards float via luminance tiers, not shadow. (Supersedes the earlier
  `.background.secondary` material approach; see 1.6.0 migration note.)
- Corner radius: per §Size = Geometry Only ladder (16 / 24 / 24 / 24).
- Inner padding: per §Size = Geometry Only ladder.
- Shadow: none (flat, luminance-tier depth).
- Border: 1px `theme.neutrals.border` overlay at `0.08` opacity for edge
  definition. No other borders. The left 3pt stripe at `0.9` opacity
  (when `style != .neutral`) sits inside the rounded shape, not as a
  separate border. Both are damped so a multi-card container separates
  its cards by SPACE rather than by contrast.

The single allowed structural variant is the `sectionHeader` card type,
which has **no chrome at all** — it renders as a typography-only
divider so containers can group cards with a sub-heading without
nesting containers (Principle III, spec D9). The `sectionHeader` also
omits the leading icon badge.

#### Container Chrome Modes (count-driven, never type-driven)

A container renders as "title layer + card layer". When it holds exactly
ONE card those two layers express the same grouping, so the reader sees a
frame inside a frame. The card frame is therefore keyed on the
container's effective card count — and on NOTHING else:

- **count == 1 → `bare`.** The card draws no background, no hairline, no
  corner radius, no padding, and no min height. Its content sits directly
  on the page background, left-aligned with the container title, and the
  header gap tightens from 12pt to 8pt. `style` is not lost: it moves to
  a 3pt vertical bar at the LEFT OF THE TITLE, the height of the title
  line. A card's whole-BODY inner panel (`InnerSurfaceRole.body`) also
  collapses here — keeping it would regrow the removed frame one level
  inward. Local `emphasis` panels (chip groups, embedded gauges) stay.
- **count >= 2 → `framed`.** The full §Card Chrome frame, damped as
  described above.

The decision function takes an `Int` and returns a mode. It MUST NOT
consult `CardType`, `CardSize`, or `CardStyle` — the three orthogonal
card dimensions stay unconflated (§Principle VI), and a degenerate count
(0, or negative) degrades to `framed` rather than trapping. The resolved
mode travels down the SwiftUI environment, defaulting to `framed` so a
card rendered outside any container keeps its frame.

#### Page Chrome (where cards sit)

Cards MUST visually float above a slightly darker page background — if
the page background and card background are identical, the cards
disappear into the canvas (the failure mode observed on 2026-06-29).

- Page background: `theme.neutrals.bg` — the lowest luminance tier, one
  step *below* the card's `theme.neutrals.card`, so cards appear elevated
  without a shadow. (Supersedes the earlier system `windowBackgroundColor`
  / `systemGroupedBackground`; see 1.6.0 migration note.)
- Content max width: page content is capped at `1200pt` and horizontally
  centered (`Space.contentMaxWidth`), so ultra-wide windows do not
  stretch cards into sparse strips.
- Page horizontal padding: 24pt (Mac) / 16pt (iOS / iPad).
- Page vertical padding (top of briefing, bottom of last container):
  24pt.

#### Container Chrome

Containers MUST NOT wrap their cards in their own colored panel. A
container is rendered as:

1. An overview-tier title line (and optional subtitle line), preceded by
   the 3pt `style` bar when the container is in `bare` mode.
2. 12pt vertical spacing (8pt in `bare` mode — no card padding is left
   to absorb the gap).
3. The cards laid out by the container's `layout` (auto/list/grid/hero).
4. 32pt vertical spacing before the next container.

This is intentional: nesting "card inside titled box inside scroll
view" produces the "everything looks the same" failure mode. Section
headers act as anchors; cards carry the content.

#### Spacing & Color Tokens

- Container vertical spacing: 32pt between containers; 12pt between
  container header and first card (8pt when the container is `bare`).
- Card vertical spacing inside a container: 12pt.
- Grid column gap: 16pt.
- Page horizontal padding: see §Page Chrome; iPhone/iPad use 16pt.
- **Colors MUST come from a package token source**, never inlined in a
  view. The canonical source is Strata's `DesignTokens` and
  `NativeDesignKit` role system, including semantic and classification roles;
  AIDashUI may define only aliases that resolve to those roles. The product
  brand role is `strata-blue`. Text uses the system semantic
  roles `.primary` / `.secondary` / `.tertiary` (these are roles, not
  literals, and remain allowed). **Raw hex (`Color(hex:)`,
  `Color(red:green:blue:)`) is permitted ONLY inside these token
  sources. There is no local copied DesignKit palette.** A view MUST NOT inline
  a hex literal, nor a system color
  (`.blue` / `.green` / …) as a signal channel — it consumes the token
  instead (Quality Bar §I P1.4).

---

## Cross-Cutting Quality Bars

These bars apply to **every** task in this repository. They are the
authoritative source of truth for what the AI Reviewer is allowed to flag.
Tasks SHOULD NOT restate these — they reference them by section. Reviewers
MUST NOT invent quality bars not listed here; if a bar is missing, amend the
constitution first.

Each bar declares a **severity tier**:

- **P0 (ship blocker)** — PR is `🔴 FAIL`, cannot merge.
- **P1 (must fix)** — PR is `🟡 CHANGES REQUESTED`. If the functional task
  is correct, the reviewer MAY approve the PR as `🟢 PASS WITH FOLLOW-UP`
  and require the issue to spawn a follow-up sub-issue covering only the P1
  finding (see §Scope Discipline).
- **P2 (nice to have)** — informational, never blocks merge.

### A. Scope Discipline (P0)

1. A PR may modify **only the files listed in the task's "Files in scope"
   section**, plus tests for those files. Any other file change is a
   constitutional violation and the reviewer MUST 🔴 FAIL.
2. Deleting a file is a scope change. Deleting a file that another task
   owns (e.g. T099 deletes `TodoListCardView.swift` owned by T100) is
   automatic 🔴 FAIL.
3. If the task description says a file is forbidden (`Files NOT to touch`),
   touching it = 🔴 FAIL.
4. Resolving a merge conflict that requires touching out-of-scope files
   requires a comment by the Fullstack Engineer naming the conflict file
   and the resolution. Reviewers accept this as long as the change is
   strictly the conflict resolution.

### B. CLI Surface (P0)

1. All `--json` success output MUST be wrapped in the envelope per
   `contracts/cli-surface.md`: `{ "ok": true, "data": <payload>, "requestId":
   "..." }`. Raw payload writes are 🔴 FAIL.
2. All errors MUST be written to stderr as JSON per
   `contracts/cli-surface.md` §"Error envelope" regardless of `--json` flag.
3. Exit codes follow `contracts/cli-surface.md` §"Exit codes" exactly.

### C. URL & Link Policy (P0)

1. Any `URL` constructed from agent-authored content (card refs, link
   targets, etc.) MUST be validated. The allowed scheme set is `https`
   only. `http`, `about:`, `javascript:`, `file:`, custom schemes → reject
   and render as plain text.
2. `URL` must have a non-empty host. URLs without a host (e.g.
   `https:///foo`) → reject.
3. Centralize validation in a single helper (`URLPolicy.validate(_:)` in
   AIDashCore). View code MUST NOT inline its own validation.

### D. Error Handling (P0)

Mirrors §Error Handling above and elevates to P0 for review purposes:

1. No `fatalError`, no `try!`, no `as!` in production code (test code
   excluded).
2. CloudKit / XPC / I/O failures degrade gracefully — no crash on the user
   path.
3. Throwing functions document their error contract in the doc-comment.

### E. Accessibility (P1)

Applies to every SwiftUI view in `AIDashUI` and `AIDashApp`:

1. **Dynamic Type**: all user-visible text uses semantic fonts
   (`.body`, `.headline`, `.caption`, etc.) or `.font(.system(...,
   design: ...))`. No hardcoded `.font(.system(size: 12))` for body text.
2. **Truncation**: in `hero` and `wide` sizes, body text MUST wrap, not
   truncate. `lineLimit(nil)` or size-aware lineLimit only.
3. **Hit targets**: any interactive element (Link, Button, tappable row)
   MUST have minimum 44pt hit area on iOS, 28pt on macOS. Use
   `.frame(minHeight: 44)` or `.contentShape` to enforce.
4. **Decorative icons**: SF Symbols used purely for visual decoration MUST
   be marked `.accessibilityHidden(true)` or combined into the parent's
   accessibility label via `.accessibilityElement(children: .combine)`.
5. **Repeated content** in lists: combine row content with
   `.accessibilityElement(children: .combine)` so VoiceOver announces one
   row at a time, not the bullet + the title + the timestamp as three
   separate elements.

### F. Internationalization (P1)

1. All user-visible string literals MUST be defined in a String Catalog
   (`.xcstrings`) and accessed via `Text("key", tableName: ...)` or
   `String(localized: "key")`.
2. Hardcoded UI literals (`Text("PRs")`, `Text("completed")`) in source
   files are 🟡 CHANGES REQUESTED. Strings in `#Preview` blocks and
   `Localizable.xcstrings` itself are exempt.
3. Layout uses leading/trailing alignment, not left/right. SwiftUI's
   default behavior is correct; this rule exists to catch manual
   `HStack(alignment: .left)` and similar.

### G. Test Coverage (P1)

1. For every new public API in `AIDashCore`, the PR MUST include at least
   one round-trip / behavior test, not just a smoke "this compiles" test.
2. For every new `CardView` in `AIDashUI`, the PR MUST include at least 2
   `#Preview` blocks covering different `CardSize` values.
3. For every new CLI subcommand, the PR MUST include at least 2 tests:
   one success path, one validation-failure path. JSON envelope assertion
   is part of the success-path test.
4. Tests that only assert `model.property == .someConstant` without
   exercising behavior are 🟡 CHANGES REQUESTED (test was the goal, not
   coverage).

### H. Design Fidelity (P2)

1. Card content rendering MUST match `contracts/cardtype-payloads.md` for
   the relevant CardType + CardSize cell. Missing fields the contract
   marks "required at this size" is 🟡 CHANGES REQUESTED.
2. Style tint application uses the constitution's 4-tier
   (`neutral/success/warning/accent`). Custom tints out of band are
   🟡 CHANGES REQUESTED unless an ADR exists.

### I. Design Token Discipline (P0 for dimension conflation; P1 for token drift)

This bar enforces Principle VI ("Three Orthogonal Card Dimensions") and
the §Design System & Tokens contract. The Reviewer reads card / layout
diffs against the token table, not aesthetic taste.

**P0 — Dimension Conflation (🔴 FAIL)**

These violate the Principle VI orthogonality guarantee:

1. A `CardView` whose `body` (or downstream switch) branches on `size`
   to choose a different `Font`, `FontWeight`, or `Font.Design`. `size`
   is geometry only.
2. A `CardView` whose `body` branches on `style` to mutate background
   material, padding, or shadow. `style` only controls the left stripe
   presence + color.
3. A `CardView` rendering its own `background(Color.X.opacity(N))`
   driven by `style`. Whole-card colored fills are forbidden. (A
   content-level `StatusPill` — a small `Capsule` driven by a payload
   field, not by `style` — is NOT a whole-card fill and is allowed per
   §Content-Level Status Pills.)
4. A renderer that uses overview-tier typography for card content, or
   detail-tier typography for container titles / section dividers. The
   two tiers are not interchangeable.
5. A `CardView` for any type other than `sectionHeader` that omits the
   leading 32×32 icon badge per the §Per-Type Visual Recipes table.
   The icon is the primary type discriminator and is mandatory.

**P1 — Token Drift (🟡 CHANGES REQUESTED)**

These violate the §Design System & Tokens table but do not break the
orthogonality contract:

1. Hardcoded numeric font sizes (`.font(.system(size: 12))`) when a
   semantic alias is available, OR a size that disagrees with the
   per-type recipe table for that CardType.
2. Hardcoded padding / spacing values that disagree with the
   §Size = Geometry Only ladder or the §Spacing & Color Tokens list.
3. Corner radius that disagrees with the §Size = Geometry Only ladder
   (small=16 / medium=24 / wide=24 / hero=24), or shadow added to a
   card.
4. A **view** that inlines a color literal — raw hex (`Color(hex:)`,
   `Color(red:green:blue:)`) OR a system color (`.blue`, `.green`,
   `.accentColor`, …) used as a signal channel — instead of consuming a
   package token. A local AIDashUI alias is compliant only when it references
   an actual Strata role and token ID; it MUST NOT define or contain a new
   color value. Inlining in a `CardView` / layout is the violation. Type icon
   tints MUST come from the actual Strata classification role and token ID per
   the §Per-Type Visual Recipes table, not freshly chosen. Per north-star §11,
   the transition uses three chart-family colors plus the type glyph. After
   the transition, the badge uses the applicable Strata classification color
   role; the concrete role mapping is not defined here. The 32×32 badge
   remains mandatory (P0.5). (Text roles
   `.primary` / `.secondary` / `.tertiary` are allowed.)
5. `Container` view wrapping its child cards in its own
   `RoundedRectangle` / `background` — containers are typography +
   spacing only, not chrome.
6. Page background that equals card background (no hierarchical
   contrast). Pages MUST use a one-step-darker background per
   §Page Chrome so cards visually float.

**Reviewer workflow for this bar**

For any PR touching `Packages/AIDashUI/Sources/AIDashUI/**`:

1. Open the diff against `.specify/memory/constitution.md` §Design
   System & Tokens.
2. For each modified view, walk the per-type recipe table and confirm
   typography matches the CardType row.
3. Confirm the view consumes the actual Strata role and token ID required by
   the recipe; an AIDashUI alias may reference that role/ID but may not define
   a color value of its own.
4. Confirm size-switches do not change font / padding / chrome.
5. Confirm style-switches only toggle the left stripe. (Content-level
   `StatusPill`s and `metric` sparkline/ring data-viz are driven by
   payload fields, not `style` — they are content signals, not chrome;
   see §Content-Level Status Pills, §Metric Data-Viz.)
6. Confirm spacing constants come from the §Spacing & Color Tokens
   list, not freshly-invented numbers.

### Verdict Aggregation Rules

Reviewer MUST aggregate per-bar findings into an overall verdict:

- Any P0 finding → 🔴 FAIL. PR cannot merge.
- No P0, any P1 finding, but functional task is correct → 🟢 PASS WITH
  FOLLOW-UP. Reviewer creates a sub-issue per P1 finding via
  `multica issue create --parent <current>` and lists the new issue keys
  in the verdict comment. The current PR ships.
- No P0, any P1 finding, AND functional task is incorrect → 🟡 CHANGES
  REQUESTED. Loop back to Fullstack.
- Only P2 findings or none → 🟢 PASS.

The "PASS WITH FOLLOW-UP" verdict is the new default for UI tasks with
a11y / i18n gaps. It exists to prevent the >10-round review loops that
burn run-count guards on stylistic findings.

---

## Development Workflow

### Spec-Driven, Multica-Executed

This project uses Spec Kit (`/speckit-constitution`, `/speckit-specify`,
`/speckit-plan`, `/speckit-tasks`) inside Hermes for spec and plan authoring.
The Strata × AIDash Goal C pilot is the bounded exception: its implementation
is executed by assigned GTT CLI writers and MUST NOT create Multica issues.
That exception applies only until Goal C is closed; all other work remains on
the normal Multica path.

For the normal Multica path, `tasks.md` must be written for Multica
consumption:

- Every task is self-contained and lists touched files, acceptance criteria,
  and dependencies on other tasks.
- Tasks reference this constitution by section number rather than restating
  rules. Multica agents read the constitution as project context.
- The `/speckit-implement` command is **not** used here. Tasks flow to
  Multica via the `multica-quick-issue` skill.

### Git Workflow

- **Worktree-per-feature**: `~/Development/AIDash-wt-<feature>/`. Worktrees
  isolate parallel agent work and prevent branch contamination.
- **Conventional commits**: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`,
  `test:`. The CI auto-reviewer parses these.
- **PR is the unit of merge**. `main` is protected. Each normal-work PR
  closes one Multica issue. A PR belonging to the Strata × AIDash Goal C
  instead cites its GTT Goal/Target/Task ID and does not create or close a
  Multica issue. CI runs the build gate and the Core test gate; both must
  pass.
- **CI auto-review** is enabled — review comments come from GitHub Actions,
  not human reviewers. Per personal-project convention, no human reviewer is
  assigned unless explicitly requested.

### Quality Gates

Every PR must pass before merge:

1. Workspace builds for all four platform/target combinations (macOS app,
   iPadOS app, iPhone app, CLI).
2. The CI-owned `AIDashCore` Swift unit-test gate passes.
3. If the PR introduces a new third-party dependency, it includes the
   corresponding ADR under `docs/adr/`.
4. If the PR adds or changes a card type, both the strongly-typed payload
   struct and the round-trip test exist.
5. The `aidata (pytest + ruff)` CI job passes — pytest, `ruff check`, and a
   degrade-not-crash probe that imports every source with no `config_local.py`
   present. Local verification is owned by the resolver-selected pre-commit and
   pre-push hooks; agents inspect those receipts rather than invoking pytest
   directly.
   Integration tests needing the gitignored `warehouse.db` skip themselves in
   CI; the hermetic unit tests — including the digest golden — must pass.

### No Identity in Version Control (NON-NEGOTIABLE)

This is a **public** repository. Account, employer, and machine identifiers MUST
NOT be committed — not in code, tests, fixtures, docs, or plan/spec prose.
Concretely: work email addresses, employer project/repo codenames, Apple
Developer Team IDs, provisioning-profile UUIDs, account GUIDs, workspace IDs.

Each such value belongs in a git-ignored local override, with a committed
`.example` template and an empty/placeholder default in the tracked file:

| Layer | Tracked default | Local override |
|---|---|---|
| Python (`aidata/`) | `config.py` (empty defaults) | `config_local.py` |
| Swift build config | `Configs/Identity.xcconfig` | `Configs/Identity.local.xcconfig` |

Two invariants follow:

- **A fresh clone with no override must build and pass tests.** Every source
  that needs an identifier degrades to a no-op (ADR-23) rather than crashing.
  Tests MUST be hermetic — identical results with and without the override.
- **Sample data is neutral.** Preview payloads, fixtures, and doc examples use
  invented names (`Atlas`, `ABC-123`, `me@example.com`), never real project
  codenames or issue keys.

Bundle IDs are exempt: an app's bundle identifier is public by nature, and the
XPC mach-service name must match it literally (it lives in a SwiftPM package
that cannot read xcconfig, so it is a hand-synced constant).

A redaction commit does not clean git history. If an identifier has already
been pushed, removing it requires a history rewrite, and GitHub still serves
the old objects from cache for a while.

### User Feedback, Not Manual Test Gates

AIDash is validated by shipping agent-completed increments and letting the
user report issues while using the app. Multica MUST NOT create, require, or
wait on dedicated manual smoke-test issues (for example T120/T150/T190). If a
flow needs real-device or iCloud confirmation, agents should ship the best
automated evidence available, mark any uncertainty in the handoff, and let the
user's later feedback create bug-fix follow-up issues. User feedback is an
input signal for the next agent cycle, not a blocking phase checkpoint.

---

## Governance

The constitution supersedes spec, plan, task, and code conventions. If a
spec or task conflicts with the constitution, the constitution wins and the
spec or task must be amended.

Amending the constitution requires:

1. A PR titled `constitution: <change>` that updates this file and bumps the
   version below.
2. A migration note in the PR description for any in-flight work affected by
   the change.

The constitution version follows MAJOR.MINOR.PATCH:
- **MAJOR** — a core principle is removed or its meaning inverts.
- **MINOR** — a new principle, section, or material expansion is added.
- **PATCH** — wording clarification, no semantic change.

---

**Version**: 1.15.0 | **Ratified**: 2026-06-23 | **Last Amended**: 2026-10-21

<!--
Sync Impact Report — 1.15.0 (MINOR):
- §Persistence authorizes the local-only SwiftData favorite snapshot store
  and keeps it outside CloudKit synchronization.
- Principle III makes Favorites a peer view and preserves the no-history,
  no-search, no-detail, no-drill-down boundary.
- §Dependencies and §Design System & Tokens adopt the exact-pinned Strata
  shared-design-system products NativeDesignKit and DesignTokens, with the
  strata-blue brand role and token-role/token-ID compliance evidence.
- §Design System & Tokens now follows north-star §11 (source sha256
  `6c57b00d42201426fa8e9df5e2a4b73c956721e08dbd0408721e7b533c197ab3`):
  16/24/24/24 geometry, 12/8/16/24 spacing, the three chart-family-color
  badge transition, semantic stripe roles, monospaced large-title metrics,
  neutral low-priority pills, and Strata token-source ownership.
- §Quality Bar I requires checking the actual Strata roles and token IDs used;
  aliases may reference those roles/IDs but may not define colors, and
  compliance is not established by merely avoiding hard-coded hex values.
- §Spec-Driven Multica-Executed and §Git Workflow record the bounded Goal C
  GTT CLI execution exception and GTT Task ID PR reference.

Migration note: in-flight Goal C work must use ADR-006, migrate the package
and theme dependency in AP2, and update affected UI specs, design references,
token-compliance tests, and GTT execution records. During the transition,
existing DesignKit consumers retain only the explicitly documented transition
behavior until their layer-owned task lands; no mixed source may be introduced
in a migrated surface. Favorite snapshots are newly local-only and require no
CloudKit data migration. The north-star §11 row-level transition notes are
now incorporated in the Design System & Tokens section and ADR-006.
-->

<!--
1.15.0 — MINOR (material governance and product-scope expansion; no core
principle removed or inverted). See the Sync Impact Report immediately above.
-->

<!--
1.14.0 — MINOR (material expansion with no principle removed or inverted).
Authorizes one explicit-consent GUI action/performance telemetry channel and
isolated telemetry storage exception. Consent defaults off in UserDefaults;
the first opt-in creates a random install UUID; disable stops admission/upload
while retaining pending state; re-enable resumes with the same lifetime-stable
identity, and version 1 has no install-ID Reset or rotation. CLI,
headless, and test-host composition remain excluded. Briefing/UserEvent
CloudKit and SwiftData rules are unchanged.

Migration note: no Briefing, UserEvent, CloudKit, or existing app-cache data is
migrated. Existing installs start with telemetry off, and no install ID,
telemetry store, or network work may exist before first opt-in. In-flight spec
007 must adopt the consent/identity lifecycle and hook-owned verification
contract, including same-ID relaunch and disable/re-enable evidence. Its
implementation remains blocked until the constitution amendment
is published and merged through a PR titled
`constitution: authorize explicit-consent GUI telemetry`.
-->

<!--
1.13.0 — MINOR (material expansion of Principle I's structured feedback
allowlist; no core principle removed or inverted). Adds append-only Team
Workflow Audit finding acknowledgement and remediation-approval receipts.
Approval records Owner intent only and grants no authority to remediate,
mutate source issues/runs, create work, or dispatch agents. Also records the
already-shipped `undone` counterpart to `done` so the allowlist matches the
current append-only latest-wins event model.

Migration note: no stored-data migration. Existing event records remain valid.
The new audit actions are additive enum cases targeting a stable finding
fingerprint; consumers that do not understand them must preserve or visibly
ignore them rather than treating them as `done`/`star`. Implementation is
governed by `specs/006-team-workflow-audit/` and must keep audit invocation and
remediation outside AIDash.
-->

<!--
1.12.0 — MINOR (material quality-gate execution change; no core principle
removed or inverted). Local hooks no longer run the heavy
AIDashApp/aidashCLI/XcodeWorkspace build and generation gates. Those gates are
CI-only; the required macOS app, iOS app (shared iPhone/iPad target), and CLI
CI builds remain mandatory. Local hooks continue to run resolver-selected SPM,
Python, repository, lint, and test gates.

Migration note: no code or stored-data migration. In-flight work must not
expect pre-commit or pre-push to run App/CLI/XcodeWorkspace heavy builds and
must not weaken or remove the corresponding required CI gates. Existing local
SPM and focused repository/data checks remain hook-driven.
-->

<!--
1.11.1 — PATCH. The module table records AIDashApp's existing direct DesignKit
dependency used for theme injection, matching project.yml and source imports.

Migration note: no code or stored data migration. In-flight work should not
remove the existing AIDashApp → DesignKit manifest edge.
-->

<!--
1.11.0 — MINOR (new `relationship` CardType recipe and visualization
contract; no principle removed or inverted).

Changes:
- §Per-Type Visual Recipes adds the `relationship` CardType and its icon,
  classification token, typography, and responsive chart/evidence-rail recipe.
- New §Relationship visualization locks the `scatter | heatmap | slope`
  vocabulary, required evidence fields, observational-language constraint, and
  size behavior.

Migration note: In-flight Core, aidata, DesignKit, and AIDashUI work that
introduces `relationship` MUST migrate in coordinated layer commits: lock the
payload and validation, produce only supported visualizations with evidence,
provide the classification token, and render the responsive recipe. Stored
briefings without the new CardType are unaffected.
-->

<!--
1.10.0 — MINOR (new section + material expansion of §Card Chrome /
§Container Chrome / §Spacing & Color Tokens; no principle removed or
inverted). Removes the "title + single card" double frame (MY-1306): a
container's title layer and a lone card's frame expressed the SAME
grouping, so every single-card container ("昨日汇总" and friends) read as a
box inside a box.

Changes:
- New §Container Chrome Modes — the card frame is keyed on the container's
  effective card COUNT: 1 → `bare` (no background / hairline / radius /
  padding / min height; content flush with the title; `style` moves to a
  3pt title-side bar; a whole-body inner panel collapses), ≥2 → `framed`.
  The decision function takes an `Int` and MUST NOT consult
  `CardType`/`CardSize`/`CardStyle`; a degenerate count degrades to
  `framed`. Resolved mode travels the environment, default `framed`.
- §Card Chrome: hairline gains `0.08` opacity, stripe gains `0.9` — the
  frame becomes a boundary HINT, so cards separate by space, not contrast.
- §Container Chrome / §Spacing & Color Tokens: card vertical spacing
  12 → 14; header-to-first-card gains a 10pt `bare` variant.

Migration note: AIDashUI tests that pinned `cardVertical == 12` were
updated in lockstep with the implementation PR; the damped hairline /
stripe and the new `bare` branch are covered by
`ContainerChromeModeTests`. Stored briefings are unaffected — no schema
change, and the mode is derived at render time from the card count a
container already carries.
-->

<!--
1.9.0 — MINOR (new section + material expansions; no principle removed or
inverted). Records aidata's move into this repo and the public-repo hygiene it
forced:
  · §Module Architecture — tree was stale (missing DesignKit); adds `aidata/`
    (Python data layer, outside the SwiftPM dependency graph, coupled only by a
    one-way data flow through the CLI's XPC seam) and `Configs/`.
  · §II — names aidata as the agent in the data-flow diagram, and states
    explicitly that co-locating it grants NO new privileges: it still holds no
    CloudKit identity and reaches the app only via `aidash`. Same boundary,
    now harder to misread.
  · §Quality Gates — adds gate 5 (aidata pytest) and states plainly that the
    Swift CI gates do not cover `aidata/**` at all.
  · §No Identity in Version Control (NEW, NON-NEGOTIABLE) — this repo is public;
    identifiers live in git-ignored local overrides with committed `.example`
    templates. Two invariants: a fresh clone with no override must build and
    test green, and sample data must be neutral. Bundle IDs exempt (public by
    nature, and the XPC mach-service name must match literally from a SwiftPM
    package that cannot read xcconfig).
-->
1.8.0 — MINOR (material addition to §Size = Geometry Only; no principle
removed or inverted). Adds "Content-derived effective size (downgrade-only)":
the authored `size` becomes an upper bound and the renderer may shrink it to
fit thin content, so oversized-but-empty prose cards render compact. Stored
`size` is untouched (no schema change); existing briefings re-render more
compactly for thin oversized cards. Single source of truth is
`EffectiveCardSize.resolve` in AIDashCore, consumed by TokenGrid (span) and
CardRouter (render). Metric/trending/sectionHeader exempt; list layout
disabled. Keeps design/north-star.md's size ladder in sync.

1.7.0 — MINOR (material expansion of §Design System & Tokens; no principle
removed or inverted). Introduces the "Dark Cockpit" theme: the same
data-driven card system, re-skinned via the theme/token layer to read as a
terminal/instrument console. Keeps design/north-star.md's "Cockpit theme"
section in sync.

Changes:
- §Two-Level Typography Hierarchy: the single top-level date-header exception
  is respecified as the **masthead**, which may use a monospaced terminal
  treatment (`AIDashTypography.masthead` / `mastheadStatus`) + a 1px rule. No
  third *content* tier is created — card content stays in the detail tier, so
  "exactly two typography systems" for content is preserved.
- §Metric Data-Viz: the allowed trend/ratio viz forms are expanded — `series`
  may render a **bar-spark** (`Sparkbars`) as well as a sparkline; `ratio`
  may render a **segmented capacity gauge** (`SegmentedGauge`) as well as a
  ring. Which form is drawn is a theme choice, still size-neutral.
- Theme seed: the app now injects `Seed.lime` (electric-lime cockpit accent),
  a DesignKit `ColorSystem` token add within the existing seed-derived-primary
  rule. The fixed `neutral/success/warning/accent` semantics are UNCHANGED, so
  §Style and §Design Fidelity §H.2 are unaffected; the accent stripe still
  resolves to `theme.primary.primary`.

Migration note: AIDashUI compliance/unit tests that pin the metric numeral
font (`.rounded`→`.monospaced`) and the trend glyphs (`↑↓→`→`▲▼▬`) were
updated in lockstep with the implementation PR. DesignKit gained `Seed.lime`,
`Sparkbars`, and `SegmentedGauge` (additive; `Sparkline`/`RingGauge` retained).
Stored briefings are unaffected (no schema change; new viz forms read the same
optional `series`/`ratio` fields).
-->

<!--
1.6.0 — MINOR (material expansion of existing §Design System & Tokens
constraints; no principle removed or inverted). Aligns the constitution
with design/north-star.md so the briefing UI can realize the modern
dashboard language DesignKit already ships.

Changes:
- §Card Chrome: card background `.background.secondary` → `theme.neutrals.card`;
  border 0.5pt `.separator` → 1px `theme.neutrals.border` (luminance-tier
  elevation, no shadow).
- §Page Chrome: page background system color → `theme.neutrals.bg`; add a
  1200pt centered content max width; page vertical padding 24 → 28.
- §Spacing & Color Tokens / §Container Chrome: container spacing 24 → 32;
  grid column gap 12 → 16.
- New §Content-Level Status Pills: colored `StatusPill` allowed as a
  payload-driven content signal (extends the trend-arrow "content not
  chrome" exception); `style` stays stripe-only. Quality Bar §I P0.3 and
  reviewer step 4 clarified so pills are not flagged as style-driven fills.
- New §Metric Data-Viz: optional `series`→sparkline / `ratio`→ring gauge
  on metric items; render height is size-neutral.

Migration note: existing AIDashUI compliance tests pin the old chrome/
spacing literals and MUST be updated in lockstep with the AIDashUI
implementation PR. Stored briefings are unaffected (new metric fields are
optional and decode to nil on old records).
-->
