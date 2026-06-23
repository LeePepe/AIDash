# Implementation Plan: Core Briefing & CLI

**Branch**: `001-core-briefing-cli` | **Date**: 2026-06-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-core-briefing-cli/spec.md`

**Constitution**: v1.0.0

---

## Summary

Ship the AIDash v1 core loop: a long-running macOS menubar app hosts the
SwiftData + CloudKit store; a thin `aidash` Swift CLI binary talks to it over
XPC; iPadOS and iOS apps render the same briefings via CloudKit Private DB
auto-sync. Agents shell out to the CLI. The CLI never touches CloudKit
directly — that is the macOS app's exclusive responsibility.

This plan resolves all "how" questions left open by the spec. Architecture
decisions are recorded inline; deeper background lives in `research.md`.

---

## Technical Context

**Language/Version**: Swift 6.0 (strict concurrency, `@MainActor` default)

**Primary Dependencies**:
- Apple frameworks only by default: SwiftUI, SwiftData, CloudKit, XPC,
  ServiceManagement, Foundation, OSLog.
- `swift-argument-parser` (Apple-maintained; required for CLI).
- Any other dependency requires an ADR per Constitution §"Dependencies".

**Storage**:
- App: SwiftData (`@Model` classes) backed by
  `ModelContainer(..., cloudKitDatabase: .private(...))` — auto-syncs to
  CloudKit Private DB.
- CLI: no persistent storage. Stateless thin XPC client.

**Testing**: Swift Testing (`@Test` macro) for `AIDashCore` unit tests; no
UI tests in v1 per Constitution §Testing.

**Target Platform**:
- App: macOS 26+, iPadOS 26+, iOS 26+ (universal SwiftUI app).
- CLI: macOS 26+ only.

**Project Type**: macOS/iOS app + macOS CLI helper + shared SPM packages
(structure §"Source Code" below).

**Performance Goals**:
- CLI cold-start to XPC reply: ≤ 5s on a healthy machine, ≤ 200ms when
  app already running (per spec SC-001).
- App cold launch on iPhone 15 / iOS 26: ≤ 2s (per spec SC-007).
- CloudKit publish → cross-device visibility: ≤ 60s in 95% of runs
  (per spec SC-002).

**Constraints**:
- Offline-capable read on iPhone/iPad (SwiftData local cache).
- 100% schema validation at CLI boundary (per spec SC-005).
- Zero PII / user content leaves Apple infra (per spec FR-040).

**Scale/Scope**:
- One user, three personal devices.
- ~50 cards/day × 90-day retention ≈ 4500 records/account, < 5MB total.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Constitution Principle | Plan Compliance | Evidence |
|---|---|---|
| I. Agent-Authored, User-Read | ✅ Pass | CLI is the only write path for briefings; app has zero compose UI. UserEvents are user → agent signal, never user → content |
| II. CLI Writes / App Reads / CloudKit Sync | ⚠️ Refined | Plan refines: CLI writes via XPC to App, App writes to CloudKit. Direct CloudKit access from CLI removed. Constitution §II's intent (separation of authorship paths) is preserved; mechanism is more concentrated. See research §R-1 |
| III. Glanceable Daily Briefing | ✅ Pass | Plan does not add hierarchy beyond Briefing/Container/Card |
| IV. Schema-Locked Card Types | ✅ Pass | Plan introduces `CardType` enum + per-type Codable struct + dispatch (data-model §M-3); CLI validates locally before XPC |
| V. Generic Container | ✅ Pass | Container model has no product-semantic enum, only `title/subtitle/order/layout/style/cards` |
| Technical: macOS 26 / Swift 6 strict | ✅ Pass | Targets pinned, no escape hatches needed in v1 |
| Technical: Module Architecture | ✅ Pass | Source layout below matches Constitution §Module Architecture |
| Technical: Persistence (CloudKit Private DB) | ✅ Pass | NSPersistentCloudKitContainer in app target |
| Technical: Dependencies (case-by-case ADR) | ✅ Pass | Only `swift-argument-parser` introduced; no other deps |
| Technical: Error Handling | ✅ Pass | All XPC + CLI failures use structured `XPCError`; no `fatalError` in plan |
| Technical: Testing (build + Core test gate) | ✅ Pass | CI workflow §"Phase 1.5" enforces both |
| Workflow: Spec-driven, Multica-executed | ✅ Pass | Tasks phase will produce Multica-consumable issues |

**Re-check after Phase 1 design**: see end of this file.

---

## Project Structure

### Documentation (this feature)

```text
specs/001-core-briefing-cli/
├── spec.md              # Already exists (post-review)
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 — architecture rationale, alternatives
├── data-model.md        # Phase 1 — SwiftData @Model + Codable schemas
├── quickstart.md        # Phase 1 — onboarding for Multica agents
├── contracts/
│   ├── cli-surface.md   # Phase 1 — full aidash CLI surface + exit codes
│   ├── xpc-protocol.md  # Phase 1 — JSON-RPC envelope + error codes
│   └── cardtype-payloads.md  # Phase 1 — per-type Codable struct schemas
└── tasks.md             # Phase 2 (/speckit-tasks output, not in this PR)
```

### Source Code (repository root)

```text
AIDash/
├── project.yml                          # XcodeGen config
├── Package.swift                        # Workspace root (optional)
├── Packages/
│   ├── AIDashCore/                      # Models, Codable schemas, validator
│   │   ├── Package.swift
│   │   ├── Sources/AIDashCore/
│   │   │   ├── Models/
│   │   │   │   ├── Briefing.swift
│   │   │   │   ├── Container.swift
│   │   │   │   ├── Card.swift
│   │   │   │   ├── CardType.swift
│   │   │   │   ├── CardSize.swift
│   │   │   │   ├── CardStyle.swift
│   │   │   │   ├── UserEvent.swift
│   │   │   │   └── Payloads/
│   │   │   │       ├── MetricPayload.swift
│   │   │   │       ├── InsightPayload.swift
│   │   │   │       ├── AgentSummaryPayload.swift
│   │   │   │       ├── TodoListPayload.swift
│   │   │   │       ├── TrendingPayload.swift
│   │   │   │       ├── DigestPayload.swift
│   │   │   │       └── SectionHeaderPayload.swift
│   │   │   ├── Storage/
│   │   │   │   ├── BriefingModel.swift     # SwiftData @Model
│   │   │   │   ├── ContainerModel.swift
│   │   │   │   ├── CardModel.swift
│   │   │   │   └── UserEventModel.swift
│   │   │   ├── XPC/
│   │   │   │   ├── XPCProtocol.swift       # @objc protocol
│   │   │   │   ├── XPCRequest.swift        # JSON-RPC envelope
│   │   │   │   ├── XPCResponse.swift
│   │   │   │   └── XPCError.swift
│   │   │   ├── Validation/
│   │   │   │   └── SchemaValidator.swift   # CLI + App both use
│   │   │   └── DeviceID/
│   │   │       └── DeviceIdentifier.swift  # name + UUID prefix
│   │   └── Tests/AIDashCoreTests/
│   │       ├── BriefingRoundtripTests.swift
│   │       ├── CardPayloadRoundtripTests.swift
│   │       ├── SchemaValidatorTests.swift
│   │       └── XPCEnvelopeTests.swift
│   └── AIDashUI/                       # SwiftUI views
│       ├── Package.swift
│       └── Sources/AIDashUI/
│           ├── BriefingView.swift
│           ├── ContainerView.swift
│           ├── CardView/
│           │   ├── CardRouter.swift     # dispatch by CardType
│           │   ├── MetricCardView.swift
│           │   ├── InsightCardView.swift
│           │   ├── AgentSummaryCardView.swift
│           │   ├── TodoListCardView.swift
│           │   ├── TrendingCardView.swift
│           │   ├── DigestCardView.swift
│           │   └── SectionHeaderCardView.swift
│           ├── EventActions/
│           │   ├── DoneButton.swift
│           │   └── StarButton.swift     # prominent per FR-020
│           └── Layout/
│               ├── AutoLayout.swift
│               ├── ListLayout.swift
│               ├── GridLayout.swift
│               └── HeroLayout.swift
├── Apps/AIDashApp/                     # Universal macOS + iPadOS + iPhone
│   ├── Info.plist                      # LSUIElement=true on macOS
│   ├── AIDashApp.entitlements          # CloudKit, iCloud container
│   └── Sources/
│       ├── AIDashApp.swift             # @main App
│       ├── Menubar/
│       │   └── MenuBarController.swift # macOS only (#if os(macOS))
│       ├── XPCService/
│       │   ├── XPCListener.swift       # macOS only
│       │   └── XPCHandlers.swift       # macOS only
│       ├── LaunchdInstaller/
│       │   └── LaunchdAgentInstaller.swift  # macOS only, first-run
│       ├── Sync/
│       │   ├── CloudKitContainer.swift # NSPersistentCloudKitContainer
│       │   └── CleanupTask.swift       # 90-day retention
│       └── Scenes/
│           └── BriefingWindowScene.swift
└── CLI/aidash/                         # macOS only
    ├── Package.swift                   # (or part of root Package.swift)
    └── Sources/
        ├── main.swift                  # ArgumentParser entry
        ├── Commands/
        │   ├── BriefingPutCommand.swift
        │   ├── BriefingPublishCommand.swift
        │   ├── BriefingGetCommand.swift
        │   ├── ContainerPutCommand.swift
        │   ├── ContainerDeleteCommand.swift
        │   ├── CardPutCommand.swift
        │   ├── CardDeleteCommand.swift
        │   ├── EventsPullCommand.swift
        │   └── SchemaListCommand.swift
        ├── XPCClient/
        │   ├── XPCClient.swift
        │   └── AppLauncher.swift       # 5s poll fallback
        └── Output/
            ├── HumanOutput.swift
            └── JSONOutput.swift
```

**Structure Decision**:
- **Three-layer SPM**: `AIDashCore` (zero UI deps, used by both app and CLI)
  → `AIDashUI` (SwiftUI views, used only by app) → app/CLI targets at the
  top.
- **App is universal**: macOS + iPadOS + iPhone from one target with
  `#if os(macOS)` guards for menubar, XPC service, and launchd installer.
- **CLI is its own target** inside the same XcodeGen project, depends only
  on `AIDashCore` (not UI).
- **Dependency direction strictly enforced** by SPM package boundaries —
  the CLI cannot accidentally import a SwiftUI view.

---

## Phase 0 — Research

The detailed research log lives in [research.md](./research.md). Summary of
resolved questions:

- **R-1 (CloudKit API choice)**: `NSPersistentCloudKitContainer` (SwiftData
  auto-sync) on the app side; CLI is a thin XPC client that does not talk
  to CloudKit. Alternatives (manual `CKDatabase`, dual API) considered and
  rejected — pivot to app-as-service eliminated dual-mapping cost.
- **R-2 (XPC protocol)**: Single `execute(Data) -> Data` method carrying a
  JSON-RPC envelope. Defers schema versioning to the Codable layer in
  `AIDashCore`. Per-method `@objc protocol` rejected (Obj-C type ceremony,
  breaks on every schema change).
- **R-3 (App lifecycle)**: LaunchAgent + LSUIElement menubar app; KeepAlive
  with `SuccessfulExit=false` so user can quit. App first-run installs its
  own launchd plist via `ServiceManagement.SMAppService`.
- **R-4 (CLI fallback)**: 5-second hard-coded poll after launching the app;
  4 exit codes (0/1/2/3) signal retry-strategy to the agent.
- **R-5 (Card payload polymorphism)**: SwiftData `@Model` stores `payloadJSON:
  Data`; per-type Codable structs in `AIDashCore` define schema; CardType
  enum dispatches decode at use site.
- **R-6 (Project generation)**: XcodeGen — your existing pattern, YAML
  configuration. Tuist and plain Package.swift rejected (former: heavier;
  latter: cannot configure entitlements / signing).
- **R-7 (Test framework)**: Swift Testing (`@Test`) for `AIDashCore`.
- **R-8 (Device identifier)**: `"\(deviceName) [\(idForVendor.prefix(8))]"`
  — human-readable for agent reports, stable suffix for joining across
  device renames.
- **R-9 (CI)**: GitHub Actions hosted macOS runner is the primary path
  (free under 200 min/month); self-hosted runner on user's Mac documented
  as fallback if CI usage ever spikes.
- **R-10 (Retention)**: 90 days hard-coded in v1, app does the cleanup on
  launch + every 24h.

---

## Phase 1 — Design Artifacts

Three artifacts produced this phase:

- [`data-model.md`](./data-model.md) — full SwiftData `@Model` schema +
  per-CardType Codable payload structs + relationships.
- [`contracts/cli-surface.md`](./contracts/cli-surface.md) — every CLI
  subcommand: flags, exit codes, JSON output schema.
- [`contracts/xpc-protocol.md`](./contracts/xpc-protocol.md) — XPC
  envelope, error codes, request/reply for each operation.
- [`contracts/cardtype-payloads.md`](./contracts/cardtype-payloads.md) —
  per-type payload struct definitions (the schema source of truth).
- [`quickstart.md`](./quickstart.md) — minimal recipe for an agent to
  publish a briefing, ready-to-copy.

---

## Phase 1.5 — Build & Test Gate (CI Workflow)

`.github/workflows/ci.yml` runs on every push and PR:

1. `actions/checkout@v4`
2. Select Xcode 26 (`xcodes select 26.0` or `sudo xcode-select -s`).
3. `brew install xcodegen` (or `mise install xcodegen`).
4. `xcodegen generate`.
5. `swift test --package-path Packages/AIDashCore` — Core unit test gate.
6. `xcodebuild -scheme AIDashApp -destination "platform=macOS" build` —
   macOS app build gate.
7. `xcodebuild -scheme AIDashApp -destination "platform=iOS Simulator,name=iPhone 17,OS=26.0" build`
8. `xcodebuild -scheme AIDashApp -destination "platform=iPadOS Simulator,name=iPad Pro,OS=26.0" build`
9. `xcodebuild -scheme aidash -destination "platform=macOS" build` — CLI
   build gate.

**Estimated runtime**: 4–5 minutes per PR. Free GitHub Actions allotment
(200 macOS minutes/month) sustains ~40 PRs/month — far more than this
project will see.

**Fallback documented in `research.md` §R-9**: switch to self-hosted runner
on user's own Mac if free quota ever exhausted. No code change needed,
only update `runs-on:`.

---

## Phase 2 — Tasks (Out of Scope for This Plan)

Per Constitution §Workflow, `/speckit-tasks` will translate this plan +
spec into Multica-ready issues. Each task references:
- This plan by section (e.g. "implements §R-5 polymorphic payload").
- Spec functional requirements satisfied (e.g. "FR-004 schema validation").
- Files touched (paths from §"Source Code" above).
- Dependencies on prior tasks.

Tasks **will not be executed via** `/speckit-implement`. Tasks flow to
Multica using the `multica-quick-issue` skill.

---

## Constitution Re-Check (Post-Design)

| Risk | Evaluation |
|---|---|
| Does Phase 1 introduce hierarchy beyond Briefing/Container/Card? | No |
| Does CLI now contain UI imports? | No (enforced by SPM package boundary; CLI depends only on `AIDashCore`) |
| Does the app gain a compose surface? | No |
| Does the schema allow agent-defined card types? | No (CardType enum locked; adding requires app+CLI release) |
| Does the design reduce or break the Section-Hardcoded → Container-Generic refactor (D8)? | No (Containers remain free-form, no enum) |
| Does any new dependency require an ADR that isn't yet written? | No (only `swift-argument-parser` introduced — Apple-maintained, allowed by Constitution without ADR) |

**Plan complies with Constitution v1.0.0.** No amendments needed.

---

## Complexity Tracking

| Apparent Complexity | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| XPC layer between CLI and app | Eliminates dual schema (SwiftData + manual CKRecord) and dual sync (two processes hitting CloudKit). Single process owns CloudKit identity | "CLI writes CloudKit directly" rejected because (a) two SwiftData containers fight for CloudKit subscriptions, (b) schema lives in two formats, (c) CLI cold start adds 1–2s per call |
| Per-CardType Codable struct + payloadJSON Data on SwiftData model | SwiftData `@Model` cannot persist `enum` with associated values; would force one of: huge model with all optional fields, or one @Model per type with cascading complexity | "Single CardModel with discriminator + raw JSON" preserves type safety at use site while letting SwiftData store a single Data field. Two `@Model`-per-type alternatives rejected (rationale in research §R-5) |
| LaunchAgent + LSUIElement menubar app | App must be running for CLI to reach XPC. Auto-start + invisible-by-default is the Apple-blessed shape for "background helper with on-demand UI" | "App that user must manually open every time" was rejected — agents writing at 06:30 would silently fail unless app is awake |
| App-self-installs LaunchAgent plist on first run | Constitution forbids zero-touch install rituals; this is the closest we can get to "launch app → it just works forever" | "User runs `make install`" rejected as friction for an app that auto-runs anyway |
