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
the sole authors of all displayed content. The user's only outbound channel is
a small set of UI events (done / star / hide) that are append-only and consumed
by agents on their own schedule. The app never modifies or interprets briefing
content — it only renders what agents have published.

This principle constrains every design decision downstream. If a feature
requires the user to type content, it does not belong in this app.

### II. Strict Separation: CLI Writes, App Reads, Both Sync via CloudKit

There is exactly one write path into briefing content (the CLI) and exactly
one write path for user events (the app). The CLI lives only on macOS and is
the public API for agents — agents shell out to `aidash …`, they do not talk
to CloudKit, files, or any internal API directly.

```
Agent (Python/shell)
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

### III. Glanceable Daily Briefing (NON-NEGOTIABLE)

The product unit is a single day's briefing. Hierarchy is flat: `Briefing →
Container → Card`, exactly two levels of nesting, no deeper. Containers must
not contain other containers; if visual grouping is needed inside a container,
use a `sectionHeader` card, not a nested container. This matches Apple HIG
("no more than two levels of hierarchy"), Apple News, Apple Health, Apple
Fitness, and Google Discover.

The intended reading time is five minutes. Any feature that pushes users into
a navigation tree, search, or drill-down is suspect.

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
  height. It MUST NOT affect typography scale, padding, or card chrome.
  `small` = 1 column, `medium` = 2 columns, `wide` = full row, `hero` =
  full row + double height. Density across sizes comes from how many items
  the type renderer chooses to show at that geometry, not from shrinking
  type.
- **`type` = typography + content density + iconography.** Each `CardType`
  owns its own font configuration and content-density vocabulary (a
  `metric` is a giant number, a `digest` is body prose, a `todoList` is a
  row list with priority dots). Two different types render visually
  distinct even at the same size and style. Type is the "what kind of
  card am I" channel.
- **`style` = semantic signal tint only.** `style` MUST NOT change card
  chrome structure (corner radius, padding, background material). The
  only permitted style affordance is a left-edge accent stripe (3pt
  hairline; success=green, warning=orange, accent=accentColor;
  `neutral` = no stripe). Filling the whole card with a colored
  background tint is forbidden — it cannot be distinguished at low
  opacity and dominates the visual at high opacity.

A direct corollary: any single card is uniquely identified by (type, size,
style), and a viewer scanning the briefing MUST be able to tell type
apart by typography, size apart by geometry, and style apart by stripe
color — independently, not jointly.

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

Two SwiftPM packages, two app/CLI targets, one workspace:

```
AIDash/
├── Packages/
│   ├── AIDashCore/       Models (Briefing/Container/Card), CloudKit client,
│   │                     schema validation. Zero UI deps. Used by both App
│   │                     and CLI to guarantee schema is sourced from one
│   │                     place.
│   └── AIDashUI/         Cross-platform SwiftUI views: type renderers,
│                         container layouts, briefing scaffold. Depends on
│                         Core.
├── Apps/
│   └── AIDashApp/        macOS + iPadOS + iPhone app target (XcodeGen
│                         managed). Depends on UI + Core.
├── CLI/
│   └── aidash/           Swift Argument Parser CLI, macOS-only.
│                         Depends on Core. Does not depend on UI.
└── project.yml           XcodeGen config for app + CLI targets.
```

Dependency direction is unidirectional: `UI → Core`, `App → UI + Core`,
`CLI → Core`. The CLI may never import UI. The package boundary enforces this.

### Persistence

- **Briefings**: CloudKit Private DB, custom record type `Briefing` containing
  serialized `Container[]` payload. Sync handled by `NSPersistentCloudKitContainer`
  or direct `CKDatabase` calls — decided in plan phase.
- **Events**: CloudKit Private DB, custom record type `UserEvent`, append-only.
- **App-local cache**: SwiftData mirror of the last fetched briefing for
  offline display. Cache is disposable; CloudKit is source of truth.
- **No third-party storage** (no Firebase, no Realm, no local SQLite outside
  SwiftData).

### Dependencies

- **Default**: prefer Apple frameworks (CloudKit, SwiftUI, SwiftData,
  URLSession, Foundation).
- **Allowed without ADR**: `swift-argument-parser` (Apple-maintained, required
  for the CLI).
- **Any other third-party dependency** requires a short ADR (under
  `docs/adr/`) that answers: what problem, what alternatives, what binary-size
  / build-time / Swift 6 concurrency cost. Do not introduce dependencies
  speculatively.
- **Networking**: `URLSession` + async/await for any HTTP, if needed. The app
  has no current HTTP requirements; CloudKit is not HTTP. Adding an HTTP
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
neither tier — it uses `.largeTitle.bold()` once at the very top.

#### Per-Type Typography Recipes (detail tier)

`type` owns typography. `size` MUST NOT mutate these recipes; size only
controls how many items / how much of the payload the renderer chooses
to show.

| CardType | Primary | Secondary | Notes |
|---|---|---|---|
| `metric` | `.system(size: 36, weight: .bold, design: .rounded)` | `.caption` `.secondary` for label | Hero number always large; unit + trend arrow inline |
| `insight` | `.title3.weight(.semibold)` | `.body` `.primary` for body | Title first, body wraps |
| `digest` | `.headline` for section heading | `.body` `lineSpacing: 4` for paragraphs | Prose; section list expands `body` paragraphs |
| `agentSummary` | `.headline` for agent name | `.callout` for completed; `.caption.monospaced()` for refs | Refs render as capsule chips |
| `todoList` | `.body` per row | `.caption2` for priority dot label | Each row leads with a priority color dot |
| `trending` | `.callout.monospaced()` for score | `.body` for title | Scores right-aligned mono |
| `sectionHeader` | `.title3.weight(.semibold)` | `.subheadline` `.secondary` | Renders with NO card chrome (raw header inside container) |

#### Size = Geometry Only

`size` is a layout instruction, never a typography hint.

- `small` → `.gridCellColumns(1)`, target width 200-260pt, fixed height 120pt
- `medium` → `.gridCellColumns(2)`, target width 400-520pt, fixed height 160pt
- `wide` → full row inside container (spans all columns), height = intrinsic
- `hero` → full row, minimum height 280pt, padding bumped one step

Container grid columns adapt by viewport: iPhone = 1 col, iPad portrait
= 2 col, iPad landscape / Mac small window = 3 col, Mac large window = 4
col. The card's own size token tells the grid how many columns to span;
the grid itself decides total column count.

#### Style = Semantic Signal Only (left stripe, no background fill)

`style` does not change card chrome. It adds (or omits) a 3pt left-edge
accent stripe. Card background, corner radius, padding, and elevation
are identical across all four `style` values.

| style | Stripe color | When agents use it |
|---|---|---|
| `neutral` | none | default; informational |
| `success` | `.green` | positive outcomes (PR merged, goal hit) |
| `warning` | `.orange` | attention needed (PR stuck, deadline near) |
| `accent` | `.accentColor` | spotlight / call to action |

Trend arrows inside `metric` cards may still use red / green — these are
content (signal direction), not card chrome.

#### Card Chrome (shared, immutable across type/size/style)

Every card view shares the same outer chrome. Per-card override is
forbidden.

- Background: `.regularMaterial` (macOS / iPadOS) / `.secondarySystemGroupedBackground` (iOS)
- Corner radius: 16pt
- Inner padding: 16pt (all sides). `hero` size uses 20pt.
- Shadow: none (flat design with material depth)
- Border: none, except the left 3pt stripe when `style != .neutral`

The single allowed structural variant is the `sectionHeader` card type,
which has **no chrome at all** — it renders as a typography-only
divider so containers can group cards with a sub-heading without
nesting containers (Principle III, spec D9).

#### Container Chrome

Containers MUST NOT wrap their cards in their own colored panel. A
container is rendered as:

1. An overview-tier title line (and optional subtitle line).
2. 12pt vertical spacing.
3. The cards laid out by the container's `layout` (auto/list/grid/hero).
4. 24pt vertical spacing before the next container.

This is intentional: nesting "card inside titled box inside scroll
view" produces the "everything looks the same" failure mode. Section
headers act as anchors; cards carry the content.

#### Spacing & Color Tokens

- Container vertical spacing: 24pt between containers; 12pt between
  container header and first card.
- Card vertical spacing inside a container: 12pt.
- Grid column gap: 12pt.
- Page horizontal padding: 20pt (iOS/iPad) / 24pt (Mac).
- Only semantic colors: `.primary`, `.secondary`, `.tertiary` for
  text; `.green` / `.orange` / `.red` / `.accentColor` for signal
  channels. Hardcoded `Color(red:..., green:..., blue:...)` literals
  are 🟡 CHANGES REQUESTED (Quality Bar §I).

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
2. A `CardView` whose `body` branches on `style` to mutate corner
   radius, background material, padding, or shadow. `style` only
   controls the left stripe presence + color.
3. A `CardView` rendering its own `background(Color.X.opacity(N))`
   driven by `style`. Whole-card colored fills are forbidden.
4. A renderer that uses overview-tier typography for card content, or
   detail-tier typography for container titles / section dividers. The
   two tiers are not interchangeable.

**P1 — Token Drift (🟡 CHANGES REQUESTED)**

These violate the §Design System & Tokens table but do not break the
orthogonality contract:

1. Hardcoded numeric font sizes (`.font(.system(size: 12))`) when a
   semantic alias is available, OR a size that disagrees with the
   per-type recipe table for that CardType.
2. Hardcoded padding / spacing values that disagree with the
   §Spacing & Color Tokens list (16pt card padding, 12pt card spacing,
   24pt container spacing, 20/24pt page padding).
3. Corner radius other than 16pt on a card, or shadow added to a card.
4. Hardcoded color literals (`Color(red:, green:, blue:)`,
   `Color(hex:)`) when a semantic color (`.primary`, `.secondary`,
   `.green`, `.accentColor`, etc.) covers the case.
5. `Container` view wrapping its child cards in its own
   `RoundedRectangle` / `background` — containers are typography +
   spacing only, not chrome.

**Reviewer workflow for this bar**

For any PR touching `Packages/AIDashUI/Sources/AIDashUI/**`:

1. Open the diff against `.specify/memory/constitution.md` §Design
   System & Tokens.
2. For each modified view, walk the per-type recipe table and confirm
   typography matches the CardType row.
3. Confirm size-switches do not change font / padding / chrome.
4. Confirm style-switches only toggle the left stripe.
5. Confirm spacing constants come from the §Spacing & Color Tokens
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
`/speckit-plan`, `/speckit-tasks`) inside Hermes for spec and plan
authoring. **Implementation is handed off to Multica**: each task from
`tasks.md` becomes a Multica issue, dispatched to the TL → Planner →
Fullstack → Reviewer pipeline.

This means `tasks.md` must be written for Multica consumption:

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
- **PR is the unit of merge**. `main` is protected. Each PR closes one
  Multica issue. CI runs the build gate and the Core test gate; both must
  pass.
- **CI auto-review** is enabled — review comments come from GitHub Actions,
  not human reviewers. Per personal-project convention, no human reviewer is
  assigned unless explicitly requested.

### Quality Gates

Every PR must pass before merge:

1. Workspace builds for all four platform/target combinations (macOS app,
   iPadOS app, iPhone app, CLI).
2. `swift test` on `AIDashCore` passes.
3. If the PR introduces a new third-party dependency, it includes the
   corresponding ADR under `docs/adr/`.
4. If the PR adds or changes a card type, both the strongly-typed payload
   struct and the round-trip test exist.

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

**Version**: 1.4.0 | **Ratified**: 2026-06-23 | **Last Amended**: 2026-06-29
