---
description: "AIDash Core Briefing & CLI — task breakdown for Multica execution"
---

# Tasks: Core Briefing & CLI

**Input**: Design documents from `/specs/001-core-briefing-cli/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/cli-surface.md`, `contracts/xpc-protocol.md`,
`contracts/cardtype-payloads.md`, `quickstart.md`

**Tests**: Spec requires unit tests for `AIDashCore` (Constitution
§Testing). UI tests not required. Tests are included throughout.

**Organization**: Tasks are grouped by user story (US1/US2/US3) to enable
independent implementation and incremental MVP delivery.

**Execution**: Each task becomes one Multica issue. Multica TL routes to
Planner → Fullstack → Reviewer. The `[Story]` tag, exact file paths,
and dependency declarations let TL parallelize correctly.

---

## Format: `[ID] [P?] [Story] Description`

- **[P]** = can run in parallel with other [P] tasks at the same checkpoint
  (different files, no logical dependencies).
- **[Story]** = US1 / US2 / US3 / FOUND (foundational) / SETUP / POLISH.
- File paths refer to the layout in `plan.md` §"Source Code".

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project scaffolding, repo hygiene, tool prerequisites.

- [ ] **T001 [SETUP]** Create root directory layout per `plan.md` §"Source Code":
  `Packages/AIDashCore/`, `Packages/AIDashUI/`, `Apps/AIDashApp/`,
  `CLI/aidash/`, `.github/workflows/`. Add empty `.keep` files where SPM
  / XcodeGen need a placeholder. Commit only structure, no code.

- [ ] **T002 [SETUP]** Write `project.yml` for XcodeGen with 4 targets:
  - `AIDashApp` — universal macOS 26 / iPadOS 26 / iOS 26 SwiftUI app,
    references `AIDashCore` + `AIDashUI` SPM packages, `LSUIElement=true`
    on macOS, entitlements file linked.
  - `aidash` — macOS-only command-line tool, depends on `AIDashCore` only.
  - Add `Info.plist`, `AIDashApp.entitlements`, `AIDashCore` /
    `AIDashUI` package references.
  - Verify with `xcodegen generate && xcodebuild -list`.

- [ ] **T003 [P] [SETUP]** Create `Packages/AIDashCore/Package.swift`:
  Swift 6.0 tools-version, `AIDashCore` library product, dependencies on
  `swift-argument-parser` (only for CLI consumers, expressed via target
  conditionals), no other deps. Test target `AIDashCoreTests` using
  Swift Testing.

- [ ] **T004 [P] [SETUP]** Create `Packages/AIDashUI/Package.swift`:
  Swift 6.0, depends on `AIDashCore`. Single `AIDashUI` library product.
  No test target (UI tests not required per Constitution §Testing).

- [ ] **T005 [P] [SETUP]** Create `Apps/AIDashApp/Info.plist` with
  `LSUIElement = YES` (macOS only — use `INFOPLIST_KEY_LSUIElement` in
  XcodeGen so iOS targets ignore it), `CFBundleIdentifier =
  com.tianpli.aidash`, supported platforms macOS 26 / iOS 26.

- [ ] **T006 [P] [SETUP]** Create `Apps/AIDashApp/AIDashApp.entitlements`:
  - `com.apple.developer.icloud-container-identifiers` =
    `iCloud.com.tianpli.aidash`
  - `com.apple.developer.icloud-services` = `CloudKit`
  - `com.apple.developer.ubiquity-kvstore-identifier` not needed
  - App Sandbox: enabled (required for App Store, also for XPC peer
    validation), Network Client / Outgoing Connections enabled.

- [ ] **T007 [P] [SETUP]** Create `.gitignore`: standard Swift /
  Xcode (`*.xcodeproj/`, `DerivedData/`, `.build/`, `Packages/*/.build/`,
  `*.swp`), plus `xcodegen` artefacts.

- [ ] **T008 [P] [SETUP]** Author root `README.md`: 1-paragraph product
  description, link to `specs/001-core-briefing-cli/spec.md` and
  `quickstart.md`, build instructions (`brew install xcodegen &&
  xcodegen generate && open AIDash.xcodeproj`).

**Checkpoint**: `xcodegen generate` succeeds, `xcodebuild -list` shows
all 4 targets, no source code files yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: All shared types, schemas, enums, and validator. Every
subsequent story imports these. **No user-story work begins until this
phase completes.**

### Data layer (Codable structs and enums)

- [ ] **T010 [P] [FOUND]** Implement enums in `Packages/AIDashCore/Sources/AIDashCore/Models/`:
  `CardType.swift`, `CardSize.swift`, `CardStyle.swift`,
  `ContainerLayout.swift`, `UserEventAction.swift`. Exactly the enums
  in `data-model.md` §"Enums". All `Codable, Sendable, CaseIterable,
  RawRepresentable<String>`.

- [ ] **T011 [P] [FOUND]** Implement Codable structs in
  `Packages/AIDashCore/Sources/AIDashCore/Models/`: `Briefing.swift`,
  `Container.swift`, `Card.swift`, `UserEvent.swift` exactly per
  `data-model.md` §"Codable structs". `public`, `Sendable`. No
  business logic, just shapes.

- [ ] **T012 [P] [FOUND]** Implement per-CardType payload structs in
  `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/`:
  `MetricPayload.swift`, `InsightPayload.swift`,
  `AgentSummaryPayload.swift`, `TodoListPayload.swift`,
  `TrendingPayload.swift`, `DigestPayload.swift`,
  `SectionHeaderPayload.swift`. Conform to
  `CardPayloadProtocol` (a Codable + Sendable marker protocol defined in
  same dir). Schemas exactly per `contracts/cardtype-payloads.md`.

- [ ] **T013 [FOUND]** Add `CardType.decode(_:)` dispatch method in
  `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`
  (extends T010). Returns `any CardPayloadProtocol`. See `data-model.md`
  §"CardType → payload dispatch". Depends on T010 + T012.

- [ ] **T014 [P] [FOUND]** Implement `SchemaValidator` in
  `Packages/AIDashCore/Sources/AIDashCore/Validation/SchemaValidator.swift`:
  - Validate enum raw values
  - Validate UUID format (RFC 4122)
  - Validate date strings
  - Decode-and-validate payloads via `CardType.decode`
  - Size check (`<= 256 KB`)
  - Map all failures to typed `XPCError` instances (code, field, got,
    allowed). Depends on T010+T011+T012+T013 but `SchemaValidator`
    itself is one file. Use Swift 6 `Result<Void, XPCError>` or
    throws style.

### XPC envelope

- [ ] **T015 [P] [FOUND]** Implement XPC envelope structs in
  `Packages/AIDashCore/Sources/AIDashCore/XPC/`:
  `XPCRequest.swift`, `XPCResponse.swift`, `XPCError.swift` exactly per
  `contracts/xpc-protocol.md` §"Request/Response envelope". All
  `Codable, Sendable`.

- [ ] **T016 [P] [FOUND]** Implement per-command Params/Result structs in
  `Packages/AIDashCore/Sources/AIDashCore/XPC/Commands/`. One file per
  command pair from `contracts/xpc-protocol.md` §"Command names":
  `BriefingPutParams.swift`, `ContainerPutParams.swift`,
  `CardPutParams.swift`, `EventsPullParams.swift`, etc. All `Codable,
  Sendable`. Empty Result structs allowed where no data is returned
  (e.g. `ContainerDeleteResult: Codable {}`).

- [ ] **T017 [P] [FOUND]** Implement `@objc AIDashXPCServiceProtocol` in
  `Packages/AIDashCore/Sources/AIDashCore/XPC/XPCProtocol.swift`.
  Single method `execute(requestData:reply:)` exactly per
  `contracts/xpc-protocol.md` §"Obj-C protocol". No business logic.

### Device identifier

- [ ] **T018 [P] [FOUND]** Implement
  `Packages/AIDashCore/Sources/AIDashCore/DeviceID/DeviceIdentifier.swift`
  per `research.md` §R-8. `public static func current() -> String`
  returning `"<deviceName> [<UUID8>]"`. Use `#if os(macOS)` /
  `#if os(iOS)` / `#if os(visionOS)` branches.

### SwiftData @Model classes

- [ ] **T020 [P] [FOUND]** Implement
  `Packages/AIDashCore/Sources/AIDashCore/Storage/BriefingModel.swift`
  exactly per `data-model.md` §"SwiftData @Model classes". Include
  `publishedAt: Date?` extension noted there.

- [ ] **T021 [P] [FOUND]** Implement
  `Packages/AIDashCore/Sources/AIDashCore/Storage/ContainerModel.swift`
  with computed `layout` / `style` typed accessors.

- [ ] **T022 [P] [FOUND]** Implement
  `Packages/AIDashCore/Sources/AIDashCore/Storage/CardModel.swift`
  with computed `type` / `size` / `style` typed accessors and
  `payloadJSON: Data` storage.

- [ ] **T023 [P] [FOUND]** Implement
  `Packages/AIDashCore/Sources/AIDashCore/Storage/UserEventModel.swift`
  per `data-model.md`.

### Core unit tests

- [ ] **T030 [P] [FOUND]** Write `Tests/AIDashCoreTests/EnumRoundtripTests.swift`:
  parametric `@Test(arguments: CardType.allCases)` for every enum,
  verify `JSONEncoder + JSONDecoder` round-trip preserves rawValue.
  Run with `swift test`. Depends on T010.

- [ ] **T031 [P] [FOUND]** Write `Tests/AIDashCoreTests/CardPayloadRoundtripTests.swift`:
  for every CardType, construct a representative payload, encode →
  decode → assert equality. Use Swift Testing `@Test(arguments:)` for
  parametric coverage. Depends on T012+T013.

- [ ] **T032 [P] [FOUND]** Write `Tests/AIDashCoreTests/SchemaValidatorTests.swift`:
  positive cases (valid input → no error) and negative cases (each
  XPCError code listed in `contracts/xpc-protocol.md` §"Error taxonomy"
  must have at least one failing-input test). Depends on T014.

- [ ] **T033 [P] [FOUND]** Write `Tests/AIDashCoreTests/XPCEnvelopeTests.swift`:
  build XPCRequest with each command's Params struct, round-trip via
  Codable, verify shape. Build XPCResponse for success and error cases.
  Depends on T015+T016.

**Checkpoint**: `swift test --package-path Packages/AIDashCore` passes
all tests. CI workflow §Phase 1.5 passes the Core test gate. No app or
CLI code yet — both will build on these foundations.

---

## Phase 3: User Story 1 — Agent Publishes, Owner Reads on Mac (Priority: P1) 🎯 MVP

**Goal**: An agent scripts `aidash` commands, briefing appears on Mac
within 30s.

**Independent Test**: Run the test script from spec User Story 1
"Independent Test" against a fresh install; verify 2 containers + 3 cards
of different types render correctly in the macOS app.

### Legacy scope interpretation for Phase 3 child issues

The currently-open Multica child issues for T040-T110 were created before the
`Files in scope` template existed. For those already-created issues, apply the
following scope rules when reviewing or implementing them:

1. **Review only the true PR diff** — compare the branch to its merge-base with
   the PR base branch (three-dot diff / actual PR diff), not a two-dot drift
   against the latest `main`. Main-branch changes that landed after the task
   branch was cut are not scope violations by themselves.
2. **Named file = scope anchor** — the file path(s) named in the task bullet are
   the primary files in scope.
3. **Compile/test wiring is allowed when strictly necessary** — package/workspace
   wiring, target registration, and tests that directly exercise the scoped
   file(s) are in scope when required to make the named file buildable and
   verifiable.
4. **Explicit dependency stubs are allowed only when the task text says so** — if
   a task/issue says a dependency stub or placeholder is acceptable until its
   owning task merges (for example CardRouter depending on T097-T103), that
   stub is in scope for the dependency boundary only; it must not replace or
   delete another task's owned implementation file.

### CLI binary scaffolding (US1)

- [ ] **T040 [US1]** Implement `CLI/aidash/Sources/main.swift` with
  ArgumentParser top-level command structure: subcommands `briefing`,
  `container`, `card`, `events`, `schema`, each with their own
  subcommands per `contracts/cli-surface.md`. Stub all command bodies
  with `fatalError("not yet implemented in TXXX")`. Verify `aidash
  --help` works. Depends on Phase 2 complete.

- [ ] **T041 [P] [US1]** Implement
  `CLI/aidash/Sources/XPCClient/XPCClient.swift`: wrap
  `NSXPCConnection(machServiceName: "com.tianpli.aidash.xpc.v1")`,
  expose `async func execute(_ request: XPCRequest) throws ->
  XPCResponse`. Activate connection, send `execute(requestData:reply:)`,
  await reply, decode. Handle invalidation via continuation.

- [ ] **T042 [P] [US1]** Implement
  `CLI/aidash/Sources/XPCClient/AppLauncher.swift`: on XPC failure,
  call `NSWorkspace.shared.openApplication(at:configuration:)` for
  `/Applications/AIDash.app`, then poll XPC every 500ms for 10
  attempts. Return success or `xpc.app_unavailable` error per
  `research.md` §R-4.

- [ ] **T043 [P] [US1]** Implement output formatters in
  `CLI/aidash/Sources/Output/`: `HumanOutput.swift` (default) +
  `JSONOutput.swift` (when `--json`). Both write success to stdout,
  errors to stderr. Stderr always JSON per `contracts/cli-surface.md`
  §"Error envelope".

- [ ] **T044 [US1]** Wire CLI exit codes per
  `contracts/cli-surface.md` §"Exit codes": 0 success, 1 local
  validation, 2 transport, 3 remote error. Map XPCError → exit code
  via central `ExitCodeMapper`. Depends on T040+T041+T043.

### CLI: briefing & container & card put (US1)

- [ ] **T050 [US1]** Implement `briefing put` subcommand in
  `CLI/aidash/Sources/Commands/BriefingPutCommand.swift`:
  - Parse `--date`, `--generated-by`, optional `--published` flag
  - Local validate via `AIDashCore.SchemaValidator`
  - Build `BriefingPutParams`, send via XPCClient
  - Output result via Output formatter, exit appropriately.

- [ ] **T051 [US1]** Implement `briefing publish` subcommand in
  `CLI/aidash/Sources/Commands/BriefingPublishCommand.swift`.

- [ ] **T052 [US1]** Implement `briefing get` subcommand in
  `CLI/aidash/Sources/Commands/BriefingGetCommand.swift`. Decode full
  Briefing reply, pretty-print or JSON-emit.

- [ ] **T053 [US1]** Implement `container put` in
  `CLI/aidash/Sources/Commands/ContainerPutCommand.swift`.

- [ ] **T054 [US1]** Implement `card put` in
  `CLI/aidash/Sources/Commands/CardPutCommand.swift`. Handle
  `--payload @file.json` reading: if argument starts with `@`, read
  file and use its content as payload. Local-validate payload via
  `CardType.decode` before XPC dispatch (per `research.md` §R-2).

- [ ] **T055 [US1]** Implement `schema list` in
  `CLI/aidash/Sources/Commands/SchemaListCommand.swift`. Returns all
  enums + per-CardType JSON Schema. Generates JSON Schema at runtime
  from Codable struct via reflection (or hand-curate per type — TL
  decides in planner; spec just requires the output document, not its
  generation method).

### App: XPC listener (US1, macOS only)

- [ ] **T060 [US1]** Implement
  `Apps/AIDashApp/Sources/XPCService/XPCListener.swift` (macOS only,
  `#if os(macOS)`):
  - Register `NSXPCListener(machServiceName: "com.tianpli.aidash.xpc.v1")`
  - Set delegate that creates a connection serving
    `AIDashXPCServiceProtocol`
  - Wire connection's `exportedObject` to `XPCHandlers` instance.

- [ ] **T061 [US1]** Implement
  `Apps/AIDashApp/Sources/XPCService/XPCHandlers.swift` (macOS only):
  - Conform to `AIDashXPCServiceProtocol`
  - In `execute(requestData:reply:)`: decode `XPCRequest`, dispatch by
    `command` field to per-command handler
  - Each handler validates via `SchemaValidator` (defense-in-depth),
    performs SwiftData mutation on `@MainActor`, returns
    `XPCResponse`.
  - Handlers: `briefingPut`, `briefingPublish`, `briefingGet`,
    `containerPut`, `containerDelete`, `cardPut`, `cardDelete`,
    `eventsPull`, `schemaList`. Each implemented per
    `contracts/xpc-protocol.md`.

### App: SwiftData + CloudKit container (US1, all platforms)

- [ ] **T070 [US1]** Implement
  `Apps/AIDashApp/Sources/Sync/CloudKitContainer.swift`:
  - `ModelContainer` factory using `ModelConfiguration(schema:,
    cloudKitDatabase: .private("iCloud.com.tianpli.aidash"))`
  - Singleton accessor + graceful error path per spec FR-041 (return
    an error scene marker, not crash). Use Constitution-mandated
    Result-style error handling — **not fatalError**.

### App: menubar shell (US1, macOS only)

- [ ] **T080 [US1]** Implement
  `Apps/AIDashApp/Sources/AIDashApp.swift`: `@main App` struct with
  `Settings { ... }` or `WindowGroup` scene; injects `modelContainer`
  from T070. Universal across macOS / iOS — uses
  `#if os(macOS)` to add MenuBarController.

- [ ] **T081 [US1]** Implement
  `Apps/AIDashApp/Sources/Menubar/MenuBarController.swift` (macOS only):
  - `NSStatusItem` with icon
  - Menu items: "Open Briefing", "About", "Quit AIDash"
  - "Open Briefing" foregrounds the `BriefingWindowScene` (or opens it
    if not already created)
  - Closing the window only hides it (no quit).

- [ ] **T082 [US1]** Implement
  `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`:
  `WindowGroup` (or `Window` on macOS) rendering `BriefingView` from
  AIDashUI. Window stays alive after close on macOS (set
  `defaultWindowVisibility(.visible)` / use `WindowDelegate`).

### UI: render today's briefing (US1)

- [ ] **T090 [US1]** Implement `BriefingView` in
  `Packages/AIDashUI/Sources/AIDashUI/BriefingView.swift`:
  - `@Query` for today's `BriefingModel` (predicate `date == today &&
    publishedAt != nil`)
  - Fallback: if today empty, query latest published briefing of any
    date, show "No new briefing today" banner above
  - Renders ContainerView for each container in order.

- [ ] **T091 [US1]** Implement `ContainerView` in
  `Packages/AIDashUI/Sources/AIDashUI/ContainerView.swift`:
  - Receives a `ContainerModel`
  - Renders title + subtitle
  - Dispatches to layout component per `container.layout`:
    `AutoLayout`, `ListLayout`, `GridLayout`, `HeroLayout` (defined in
    next tasks).

- [ ] **T092 [P] [US1]** Implement `AutoLayout` in
  `Packages/AIDashUI/Sources/AIDashUI/Layout/AutoLayout.swift`:
  smart-packs cards by size — hero takes a full row, wide takes a
  row, small/medium pack into grid rows.

- [ ] **T093 [P] [US1]** Implement `ListLayout` in
  `Packages/AIDashUI/Sources/AIDashUI/Layout/ListLayout.swift`:
  one card per row regardless of size.

- [ ] **T094 [P] [US1]** Implement `GridLayout` in
  `Packages/AIDashUI/Sources/AIDashUI/Layout/GridLayout.swift`:
  equal-width 2/3/4 column grid based on horizontal size class.

- [ ] **T095 [P] [US1]** Implement `HeroLayout` in
  `Packages/AIDashUI/Sources/AIDashUI/Layout/HeroLayout.swift`:
  first card takes hero treatment, rest follow as small cards.

- [ ] **T096 [US1]** Implement `CardRouter` in
  `Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift`:
  switches on `CardModel.type`, decodes `payloadJSON` via
  `CardType.decode`, dispatches to the corresponding type-specific view.
  Failure to decode → render generic "card unavailable" placeholder
  (spec FR-032).

- [ ] **T097 [P] [US1]** Implement `MetricCardView` in
  `Packages/AIDashUI/Sources/AIDashUI/CardView/MetricCardView.swift`:
  receive `MetricPayload` + `CardSize`, render per
  `contracts/cardtype-payloads.md` §"metric" size rules.

- [ ] **T098 [P] [US1]** Implement `InsightCardView` (per spec rules).

- [ ] **T099 [P] [US1]** Implement `AgentSummaryCardView`.

- [ ] **T100 [P] [US1]** Implement `TodoListCardView`.

- [ ] **T101 [P] [US1]** Implement `TrendingCardView`.

- [ ] **T102 [P] [US1]** Implement `DigestCardView`.

- [ ] **T103 [P] [US1]** Implement `SectionHeaderCardView`.

### App: LaunchAgent self-install (US1, macOS only)

- [ ] **T110 [US1]** Implement
  `Apps/AIDashApp/Sources/LaunchdInstaller/LaunchdAgentInstaller.swift`
  (macOS only) per `research.md` §R-3:
  - Use `SMAppService.agent(plistName: "com.tianpli.aidash.plist")`
  - Bundle the plist in app Resources with `KeepAlive` dict +
    `SuccessfulExit=false`
  - Call `service.register()` on app launch if not yet registered
  - Surface errors to a log file in `~/Library/Logs/AIDash/`. Constitution
    forbids `fatalError`; surface to user via menubar status.

### User-feedback validation (US1)

No dedicated manual smoke-test task exists for US1. Multica agents validate
US1 with automated build/test evidence, contract checks, and PR review. The
user will give feedback while using AIDash; discrepancies become follow-up
bug issues and do not block declaring US1 implementation complete.

---

## Phase 4: User Story 2 — Cross-Device Sync (Priority: P2)

**Goal**: Briefing published on Mac appears on iPad and iPhone within
60s.

**Independent Test**: Spec US2 "Independent Test" — publish on Mac, open
app on signed-in iPad / iPhone, content appears within 60s without manual
refresh.

### App: iOS/iPadOS app target verification (US2)

- [ ] **T130 [US2]** Verify `Apps/AIDashApp` target builds + runs on
  iOS and iPadOS simulators with the menubar/XPC code guarded out
  via `#if os(macOS)`. UI shells reuse `BriefingView`. Depends on
  Phase 3 complete (BriefingView already exists from T090).

- [ ] **T131 [P] [US2]** Implement iOS/iPad scene setup in
  `Apps/AIDashApp/Sources/AIDashApp.swift`:
  - On iOS, no menubar; `WindowGroup` is the only scene.
  - On macOS, both menubar + window scene coexist.

- [ ] **T132 [P] [US2]** Add "last synced HH:MM" indicator to
  `BriefingView` (per spec US2 acceptance scenario 2 and "no new
  briefing today" UI hint). Read from a SwiftData-tracked
  `lastSyncedAt` timestamp updated by CloudKit container's
  `eventChangedPublisher` (or similar).

- [ ] **T133 [P] [US2]** Implement "iCloud unavailable" error scene
  per spec FR-041. Shown when CloudKit container init fails (no iCloud
  account, container error). Replace the placeholder fatalError from T070.

### Adaptive layout (US2)

- [ ] **T140 [US2]** Verify (and fix where needed)
  `BriefingView` / `ContainerView` / layout files for adaptive widths:
  - iPhone (single column always)
  - iPad (2 cols ≥ 768pt)
  - Mac (3+ cols depending on window width)
  Use `@Environment(\.horizontalSizeClass)` + `GeometryReader` as
  appropriate. Add `#Preview` blocks for each size class.

### User-feedback validation (US2)

No dedicated manual sync-test task exists for US2. Agents validate cross-device
sync with automated build evidence, CloudKit integration checks where feasible,
and clear handoff notes for any real-device uncertainty. The user will report
real-device sync feedback during normal use; feedback becomes follow-up bugs,
not a blocking checkpoint.

**Checkpoint**: Stories 1+2 are implementation-complete when their code, build
gates, and review gates pass.

---

## Phase 5: User Story 3 — User Events & Agent Pull (Priority: P3)

**Goal**: Owner can tap done/star on cards; agents pull these events
via CLI.

**Independent Test**: Spec US3 "Independent Test" — simulate user actions
in app, run `aidash events pull --since`, verify expected JSON output.

### UI: event action buttons (US3)

- [ ] **T160 [P] [US3]** Implement `DoneButton` in
  `Packages/AIDashUI/Sources/AIDashUI/EventActions/DoneButton.swift`:
  small inline checkmark control. On tap:
  - Optimistic state update within 100ms (per spec SC-006)
  - Insert `UserEventModel` into the SwiftData store (CloudKit sync is
    automatic)
  - Cross-device sync follows (per spec US3 acceptance scenario 2).

- [ ] **T161 [P] [US3]** Implement `StarButton` in
  `Packages/AIDashUI/Sources/AIDashUI/EventActions/StarButton.swift`:
  **prominent** treatment per spec FR-020 — larger hit target
  (≥ 44×44 pt), `accent` color, dedicated animation on tap (transition
  from outline → filled with brief scale + glow). Same event-recording
  behavior as DoneButton.

- [ ] **T162 [US3]** Integrate Done + Star buttons into all
  CardView implementations (T097–T103). Bind to the parent `CardModel`'s
  ID. Default position: bottom-trailing inside the card; renderer can
  override per type if a different placement reads better (e.g.
  `sectionHeader` has no actions).

- [ ] **T163 [US3]** Implement event visual state sync: query
  `UserEventModel` joined by `cardId` in `CardRouter` (or pass down via
  `@Query`); show done strikethrough + star filled per existing events.

### CLI: events pull (US3)

- [ ] **T170 [US3]** Implement `events pull` in
  `CLI/aidash/Sources/Commands/EventsPullCommand.swift`:
  - Parse `--since`, `--until`, `--card-id`, `--action` flags
  - Send `EventsPullParams` via XPC
  - Default output: newline-delimited JSON per
    `contracts/cli-surface.md` §"events pull"
  - With `--json`: wrap in array under `data.events`.

- [ ] **T171 [US3]** Implement `eventsPull` handler in
  `Apps/AIDashApp/Sources/XPCService/XPCHandlers.swift` (extends T061):
  - Query `UserEventModel` with predicate
    `timestamp >= since && (until == nil || timestamp < until) && ...`
  - Sort by `(timestamp, device, cardId)` lexicographic per spec FR-024
  - Encode as `[UserEvent]` (Codable structs from T011)
  - Return `EventsPullResult { events: [UserEvent], count: Int }`.

### CLI: card delete (US3 supporting)

- [ ] **T175 [P] [US3]** Implement `container delete` in
  `CLI/aidash/Sources/Commands/ContainerDeleteCommand.swift`.

- [ ] **T176 [P] [US3]** Implement `card delete` in
  `CLI/aidash/Sources/Commands/CardDeleteCommand.swift`.

### App: 90-day cleanup (US3 polish, related to data hygiene)

- [ ] **T180 [US3]** Implement
  `Apps/AIDashApp/Sources/Sync/CleanupTask.swift` per `research.md`
  §R-10: on app launch + every 24h, delete BriefingModels with `date <
  today - 90 days`. UserEventModels cascade via SwiftData relationship.
  Use a background `Task.detached(priority: .background)`.

### User-feedback validation (US3)

No dedicated manual end-to-end test task exists for US3. Agents validate event
recording/pull behavior with unit/integration-style checks and build gates.
The user's normal use of done/star actions is the acceptance signal; issues
reported later become follow-up bugs.

**Checkpoint**: All three user stories are implementation-complete once code,
build gates, and review gates pass. v1 MVP completeness is not blocked on a
manual test issue.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Cross-story improvements + CI setup + docs hygiene.

### CI workflow (POLISH)

- [ ] **T200 [POLISH]** Implement `.github/workflows/ci.yml` per
  `plan.md` §"Phase 1.5 — Build & Test Gate":
  - Runs on push + pull_request
  - macos-15 / macos-26 runner
  - `xcodegen generate`
  - `swift test --package-path Packages/AIDashCore`
  - `xcodebuild` for macOS app, iOS simulator, iPad simulator, CLI
  - Status badge added to README. Note: self-hosted runner fallback
    documented in `research.md` §R-9 — not implemented in this task
    (only swap `runs-on:` if needed later).

- [ ] **T201 [POLISH]** Add CI status badge + build instructions to
  root `README.md`.

### Documentation polish (POLISH)

- [ ] **T210 [P] [POLISH]** Move `docs/agent-ops-redo-backlog.md`
  cross-reference into root README.md (so future readers know
  agent-ops-dashboard rework is tracked separately).

- [ ] **T211 [P] [POLISH]** Generate `aidash --help` output snapshot
  into `docs/cli-help-snapshot.txt` (regenerated by CI; commit when
  CLI surface changes). Verifies parity with
  `contracts/cli-surface.md`.

- [ ] **T212 [P] [POLISH]** Add architecture diagram to
  `docs/architecture.svg` showing: App + CLI + CloudKit + iCloud sync
  arrows. Reference from README and `plan.md`.

### Performance verification (POLISH)

- [ ] **T220 [POLISH]** Performance smoke test:
  - Measure CLI cold start to XPC reply when app is already running
    (spec SC-001 target: < 200ms)
  - Measure full briefing publish (3 containers, 6 cards, 4 types)
    (spec SC-001 target: < 5s)
  - Measure iPhone app cold launch with cached 7-day data (spec
    SC-007 target: < 2s)
  - Document numbers in `docs/perf-baseline-v1.md`. Failures =
    follow-up issues, not v1 blockers (spec SC-002 caveat).

### Schema discovery test (POLISH)

- [ ] **T230 [POLISH]** Verify `aidash schema list` output is
  sufficient for an unaided agent to write a valid `card put` for
  every CardType (spec SC-004). Simulate: hand the JSON output to
  one Multica agent that has never seen the project, ask it to
  write each card-type publish command, score success rate. 100% =
  pass.

---

## Dependencies & Execution Order

### Phase dependencies

```
Phase 1 SETUP    (T001-T008)
   │
   ▼
Phase 2 FOUND    (T010-T033) — blocks all user stories
   │
   ├─────────────┬─────────────┬
   ▼             ▼             ▼
Phase 3 US1   Phase 4 US2   Phase 5 US3
(T040-T110)  (T130-T140)  (T160-T180)
   │             │             │
   └─────────────┴─────────────┘
                 │
                 ▼
           Phase 6 POLISH (T200-T230)
```

US2 depends on US1 (BriefingView from T090 is reused). US3 mostly
parallel to US2, but if a contention arises with `XPCHandlers.swift`
(both T061 and T171 modify it), serialize via Multica TL's task
sequencing.

### Critical path

`T001 → T002 → T010 → T013 → T014 → T040 → T060 → T070 → T080 → T090 → T096 → T097`
≈ 12 sequential tasks; everything else is parallel-eligible to the right
people.

### Multica execution notes

- Each task ID = one Multica issue.
- Issue title: `[T###] [Story] Brief description`.
- Issue body references the task body verbatim plus links to:
  - the relevant `spec.md` FR / SC numbers
  - the relevant `plan.md` / `research.md` / `data-model.md` /
    `contracts/*.md` sections
  - upstream task dependencies by their T### IDs
- Multica TL is responsible for routing (Planner → Fullstack → Reviewer);
  the `[P]` tag tells TL which tasks can run in parallel.
- **Do not** add pipeline-routing instructions inside the issue body
  (per `multica-quick-issue` skill convention).

---

## Parallel Example: US1 Card Views

Once T096 (CardRouter) is in place, T097–T103 (the 7 type-specific
views) are independent files:

```bash
# Multica can spawn these in parallel:
T097 MetricCardView
T098 InsightCardView
T099 AgentSummaryCardView
T100 TodoListCardView
T101 TrendingCardView
T102 DigestCardView
T103 SectionHeaderCardView
```

Same pattern in Phase 2 Foundational: T010, T011, T012, T015, T016, T017,
T018, T020-T023 are all independent.

---

## Implementation Strategy

### MVP First: US1 only

1. Phase 1 SETUP (T001-T008) ≈ 1 day
2. Phase 2 FOUND (T010-T033) ≈ 3-5 days
3. Phase 3 US1 (T040-T110) ≈ 7-10 days
4. Ship as v0.1 once code/build/review gates pass; user feedback during
   real use becomes follow-up work

### Incremental delivery

- v0.1 = US1 (Mac-only briefing)
- v0.2 = + US2 (cross-device sync)
- v0.3 = + US3 (user events)
- v1.0 = + Phase 6 polish (CI + perf baseline + docs)

### Parallel team strategy

After Phase 2 completes:
- One Multica Fullstack agent on US1 backbone (T040, T060, T070, T080,
  T090, T096)
- Second Fullstack agent on US1 card views in parallel (T097-T103)
- Third Fullstack agent on US2 once US1 BriefingView lands (T130-T140)
- US3 can start as soon as US1's `XPCHandlers` is in place (T061)

---

## Notes

- `[P]` = different files, independent logic.
- `[Story]` = which spec user story this task delivers value for.
- Tasks reference plan.md / research.md / data-model.md /
  contracts/ — Multica agents should `cat` those files for full
  context.
- `swift test` must pass after every task in Phases 2-5 (CI gate).
- Do not create or wait on manual smoke-test tasks (historical T120/T150/T190).
  The user will give product feedback while using the app; Multica should turn
  that feedback into follow-up bugs, not block implementation completion.
- Constitution forbids `fatalError` / `try!` / `as!` in production code;
  every error path must be a graceful UI state or non-zero exit.
- Each task ends with `git commit` using conventional commit prefix
  (`feat:`, `fix:`, `refactor:`, `test:`, etc.) per Constitution
  §"Git Workflow".
