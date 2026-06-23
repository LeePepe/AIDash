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
   tests. Manual smoke-test on macOS + iPad simulator + iPhone simulator
   before merging UI changes.

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

**Version**: 1.0.0 | **Ratified**: 2026-06-23 | **Last Amended**: 2026-06-23
