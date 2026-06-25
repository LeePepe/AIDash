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

**Version**: 1.2.0 | **Ratified**: 2026-06-23 | **Last Amended**: 2026-06-25
