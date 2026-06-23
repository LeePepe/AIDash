# Feature Specification: Core Briefing & CLI

**Feature Branch**: `001-core-briefing-cli`

**Created**: 2026-06-23

**Status**: Draft

**Input**: User description: "AIDash v1 core: CLI publishes daily briefings, multi-platform app renders them, app collects user events that agents pull back asynchronously"

**Constitution version**: 1.0.0

---

## Overview

AIDash v1's core capability: a single end-to-end loop where (a) an external
agent uses the `aidash` CLI on a Mac to publish a daily briefing, (b) the
AIDash app on macOS, iPadOS, and iPhone renders that briefing within seconds
of publication, and (c) the user's lightweight reactions (mark done, star,
hide) propagate back to a place where agents can pull them on their own
schedule.

This is the *Minimum Viable Product*. After v1, type renderers, container
layouts, history navigation, and a third-party agent ecosystem can all expand
without changing the v1 contract.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Agent Publishes Today's Briefing, Owner Reads It on Mac (Priority: P1)

A morning briefer agent runs on the owner's Mac at 06:30. It collects yesterday's
git activity, today's calendar, agent completions, and trending items from the
owner's monitored sources. It invokes `aidash briefing put …` once per
container, then `aidash briefing publish 2026-06-23`. The owner opens AIDash
on their Mac at 07:15 and sees the freshly-published briefing for today
without any extra interaction.

**Why this priority**: This is the only story that, by itself, justifies the
project's existence. Without it, there is no product. Multi-device sync and
user-event reactions are valuable but secondary — a single-device,
read-only briefing already delivers the "open it, see today, close it" daily
ritual.

**Independent Test**: An operator runs a scripted `aidash` sequence that
publishes a briefing containing two containers (one with a `metric` card and
a `digest` card, one with a `todoList` card). They open the macOS app and
verify all three cards render with correct title, content, size, and style.
This test does not require iCloud sync to a second device, nor any user
interaction beyond launching the app.

**Acceptance Scenarios**:

1. **Given** a Mac with the `aidash` CLI installed and the AIDash app
   launched, **When** an agent runs `aidash briefing put --date today
   --container-id c1 --title "Yesterday" --order 10` followed by
   `aidash card put --container-id c1 --id card1 --type digest --size hero
   --style neutral --payload <valid-digest-json>` and finally
   `aidash briefing publish --date today`, **Then** within 30 seconds the
   app's main screen shows a briefing dated 2026-06-23 with one container
   titled "Yesterday" containing one hero-sized digest card with the supplied
   content.

2. **Given** an agent attempts to publish a card with an unknown `type` value
   (e.g. `--type unicorn`), **When** the CLI runs the command, **Then** the
   CLI exits with non-zero status, writes a structured error to stderr
   identifying `type` as the offending field, and writes nothing to CloudKit.

3. **Given** the owner opens the app on a morning when no briefing has been
   published yet for today, **When** the app loads, **Then** the app shows
   the most recent previously-published briefing along with a clear "no new
   briefing today" indicator (not a blank screen, not an error).

4. **Given** an agent publishes the same briefing date twice (e.g. an
   early-morning run, followed by a mid-morning refresh), **When** the
   second publish completes, **Then** the app shows the latest version with
   no duplicated containers or cards, and the latest `generatedAt` timestamp
   is visible in the UI.

---

### User Story 2 — Owner Reads the Same Briefing on iPad and iPhone (Priority: P2)

After Story 1's briefing is published on the owner's Mac, they want to open
AIDash on their iPad or iPhone later and see the same briefing. They do not
publish from these devices; they only read. The data crosses devices via
CloudKit Private Database.

**Why this priority**: This is what makes the app's "open it on the couch /
in bed / on the commute" use case work. It is high value but Story 1 must
exist first — there's no point syncing nothing.

**Independent Test**: After Story 1's scripted publish completes on a Mac,
launch AIDash on a paired iPad (signed into the same iCloud account). The
app should show the same briefing content within 60 seconds, without manual
refresh action by the operator. Repeat on iPhone.

**Acceptance Scenarios**:

1. **Given** a briefing published from Mac at time T (Story 1 complete),
   **When** the owner opens AIDash on iPad signed into the same iCloud
   account, **Then** within 60 seconds the iPad shows the same briefing
   with the same containers, cards, and content.

2. **Given** iPad has stale local cache from yesterday, and a new briefing
   was published while iPad was offline, **When** iPad regains network and
   the app is reopened, **Then** the app first shows yesterday's cached
   briefing (within 1 second), then transitions to today's briefing once
   sync completes (with a brief loading indicator on the sync state).

3. **Given** the owner is signed into different iCloud accounts on Mac and
   iPad, **When** they publish a briefing on Mac and open the app on iPad,
   **Then** the iPad shows whatever the iPad's iCloud account previously
   had (or empty state) — under no circumstances does data leak across
   iCloud accounts.

4. **Given** the app has a per-device adaptive layout, **When** the owner
   views the same briefing on iPhone (single column), iPad (two columns
   when wider than 768pt), and Mac (multi-column), **Then** the same set of
   cards appears on all three but rearranged for the screen size; container
   order and card identity are preserved.

---

### User Story 3 — Owner Marks a Card "Done" or "Star" and Agent Picks It Up Later (Priority: P3)

The owner is reviewing today's briefing and sees a `todoList` card with
three suggested actions. They tap "done" on the first item, which marks it
done locally and emits a `done` event. They tap the prominent star button
on a separate `insight` card to signal "I want more like this." Later,
when an agent runs to generate tomorrow's briefing, it calls `aidash events
pull --since yesterday` to fetch a list of done/star events the owner
produced; the agent uses this list however it wants (e.g. exclude the done
item from tomorrow, amplify topics like the starred card).

**Why this priority**: This closes the feedback loop. Without it, agents
generate today's briefing in a vacuum — they have no signal whether
yesterday's content was useful. But it is correctly P3 because the
constitution's Agent-Authored principle means *the agent decides what to do
with the signal*; the app never modifies content. So v1 can ship without
this and still be useful (agents just run blind).

**Design note on actions chosen for v1**: The v1 surface intentionally
includes only `done` (lightweight completion marker) and `star` (positive
amplification signal). A `hide` action was considered and rejected for v1
because (a) it would push the user into a "management" mindset that conflicts
with "user only reads", and (b) users who don't want certain content can
simply scroll past or trust the agent to learn from the absence of star/done
signal on that content. If real usage shows a need to suppress recurring
unwanted cards, `hide` can be added in v2 without schema migration.

**Star is visually emphasized.** Unlike `done` (which is a small inline
checkmark), `star` is rendered as a prominent action — larger touch target,
distinct color (`accent`), and a brief animation on tap. This reflects its
semantic weight as the primary positive signal a user can give an agent.

**Independent Test**: With Story 1 and 2 complete, simulate user actions
via the app's debug menu (or programmatic event injection): mark one card
"done" and star another. Then on the Mac run `aidash events pull --since
2026-06-23`. Verify the CLI returns a JSON document containing exactly
two events with the correct `cardId`, `action`, `device`, and timestamp
values.

**Acceptance Scenarios**:

1. **Given** a briefing is open in the app and a card has interactive
   actions (done / star) available, **When** the owner taps "done"
   on a card, **Then** within 100ms the card shows a visual "done" state
   (e.g. strikethrough, dimmed, or check overlay) and remains visible (it
   does not disappear from this briefing).

2. **Given** the owner has tapped "done" on a card on iPhone, **When** they
   open the same briefing later on iPad, **Then** that card also shows the
   "done" state (events synced across devices via CloudKit).

3. **Given** the owner taps the star button on a card, **When** the tap
   occurs, **Then** within 100ms the app plays the star animation, the star
   icon transitions to its "starred" filled state, and a `star` UserEvent
   is queued for CloudKit. The star action MUST be visually more prominent
   than `done` (larger hit target, more saturated color, dedicated animation)
   so that users perceive it as the deliberate positive-signal action.

4. **Given** the owner taps "done" then "undone" on the same card within
   a short window, **When** the agent later runs `aidash events pull`,
   **Then** the agent sees both events with their original timestamps and
   can de-duplicate / collapse however it chooses (the CLI does not collapse
   for the agent).

5. **Given** the owner has marked multiple cards across multiple briefings
   over several days, **When** an agent runs `aidash events pull --since
   2026-06-20`, **Then** the CLI returns all events with timestamps on or
   after 2026-06-20 in chronological order (with deterministic tie-breaker
   per FR-024); agents can rely on `(cardId, timestamp, device)` being
   unique within the result.

6. **Given** the owner is offline when they tap "done" or "star" on a card,
   **When** they regain network later, **Then** the event syncs to CloudKit
   (preserving original tap timestamp), and agents pulling events see the
   original time, not the sync time.

---

### Edge Cases

- **Briefing for a date in the past**: An agent publishes a briefing for
  `--date 2026-01-15`. The CLI MUST accept the publish (agents may legitimately
  back-fill, e.g. when migrating data or recovering from offline periods).
  However v1 of the app does NOT surface past briefings — historical
  navigation (date picker, "yesterday's briefing", etc.) is out of scope for
  v1. Past briefings remain in CloudKit and are visible to v2's historical
  navigation feature when it ships. Decision rationale: keeps "glanceable
  today" the unambiguous v1 experience; v2 can build history on the same
  data model with zero schema changes.
- **Briefing for a date in the future**: Agent publishes for `2027-01-01`.
  CLI accepts; app does not surface it until that date arrives.
- **Empty briefing**: Agent publishes a briefing with zero containers. App
  shows a "today's briefing is empty" state, not an error.
- **Card payload too large**: A `digest` card with a 50 KB body. CloudKit
  has per-record size limits; CLI must validate payload size and reject
  oversize records with a clear error before sending to CloudKit.
- **Container with zero cards**: Permitted (e.g. a placeholder container
  for a section the agent hasn't filled yet). App renders the title +
  subtitle with an empty body.
- **Sync conflict on the same briefing**: Two agents on different Macs
  publish the same date within seconds. CloudKit's last-writer-wins
  resolves the briefing record; events are append-only so no conflict.
- **CloudKit account not signed in**: App displays a clear "Sign in to
  iCloud to view briefings" state; no crash, no blank screen.
- **App opened with no internet on first launch (no cache yet)**: Shows
  empty state with "Waiting for first briefing — check internet" message.

---

## Requirements *(mandatory)*

### Functional Requirements

#### CLI publishing & retrieval

- **FR-001**: The `aidash` CLI MUST be installable as a standalone
  command-line binary on macOS 26+ and MUST work without launching the app.
- **FR-002**: The CLI MUST expose at minimum these subcommands:
  `briefing put`, `briefing publish`, `briefing get`,
  `container put`, `container delete`,
  `card put`, `card delete`,
  `events pull`,
  `schema list`.
- **FR-003**: Every CLI subcommand MUST support `--help` and `--json` output
  modes. `--help` MUST document every flag, accepted value, and the schema of
  any `--payload` argument so an agent can write correct calls without
  consulting other documentation.
- **FR-004**: The CLI MUST validate every input against the locked schema
  (type whitelist, size whitelist, style whitelist, required fields per
  type's payload, payload size limit) BEFORE sending anything to CloudKit.
  Validation failures MUST exit non-zero with structured JSON on stderr
  identifying the offending field.
- **FR-005**: The CLI MUST be idempotent on retry: re-running the exact
  same `briefing put` / `container put` / `card put` MUST produce no
  duplicates and the same end state in CloudKit. Idempotency is keyed on
  the caller-supplied `id` fields.
- **FR-006**: `briefing publish` MUST be an atomic operation: either the
  briefing becomes visible to readers with all containers and cards, or no
  change is visible. Partial publishes are not permitted to be observable.

#### App rendering

- **FR-010**: The AIDash app MUST run on macOS 26+, iPadOS 26+, and iOS 26+
  from a single SwiftUI codebase.
- **FR-011**: On launch, the app MUST display the most recently published
  briefing for the local date if one exists; otherwise the most recent
  available briefing of any date with a clear "no new briefing today"
  indicator.
- **FR-012**: The app MUST render every card type in the v1 whitelist
  (`metric`, `insight`, `agentSummary`, `todoList`, `trending`, `digest`,
  `sectionHeader`) at every size (`small`, `medium`, `wide`, `hero`).
  The renderer MUST adapt density automatically (e.g. `metric` shows one
  item at `small`, eight at `wide`).
- **FR-013**: The app MUST respect the container's `layout` value
  (`auto | list | grid | hero`) when arranging cards.
- **FR-014**: The app MUST display cards in container order (`order`
  ascending) and containers in briefing order.
- **FR-015**: The app MUST update displayed content within 60 seconds of a
  new publish arriving via CloudKit, without requiring a manual refresh.
- **FR-016**: The app MUST contain no input fields, compose buttons, "new
  card" affordances, or chat surfaces. "Input" in this context means any
  UI that produces new text content — typing, dictation, content selection,
  file pickers, voice notes, drawing. The lightweight event actions defined
  in FR-020 (tap to mark done / star) are NOT considered "input" — they
  emit only structured signal events about pre-existing cards, never new
  content. The only user actions on briefing content are: tap-to-open-detail
  (read-only), and the event actions defined in FR-020.

#### User events

- **FR-020**: The app MUST expose two lightweight per-card actions:
  `done` and `star`. Tapping either MUST give optimistic visual feedback
  within 100ms. `done` is rendered as a small inline marker (checkmark);
  `star` is rendered as a visually prominent action (larger hit target,
  saturated color from the `accent` palette, dedicated tap animation) to
  reflect its semantic weight as the primary positive signal.
- **FR-021**: Each tap MUST be persisted to CloudKit as an append-only
  `UserEvent` record containing `id`, `timestamp`, `device`, `cardId`,
  `action`. Valid `action` values in v1 are `done` and `star`. The app
  MUST NEVER modify briefing content as a result of user actions.
- **FR-022**: If the device is offline when the user taps, the event MUST
  be queued locally and synced when network returns, preserving the
  original tap timestamp.
- **FR-023**: User event visual state (done/star) MUST sync across
  the owner's devices via CloudKit within 60 seconds (subject to the
  CloudKit-latency assumption below).
- **FR-024**: The CLI's `events pull` subcommand MUST return all events
  on or after the `--since` timestamp in chronological order as a
  newline-delimited JSON stream or `--json` array. Events with identical
  `timestamp` MUST be ordered by lexicographic `(timestamp, device, cardId)`
  to guarantee deterministic output for the same dataset across runs and
  across machines. Agents can rely on `(cardId, timestamp, device)` being
  unique within the result; if a true duplicate is ever observed, it is a
  schema bug, not a normal occurrence.

#### Schema & data integrity

- **FR-030**: The schema for `Briefing`, `Container`, `Card`, and
  `UserEvent` MUST be defined in exactly one place inside `AIDashCore`
  and shared by both the app and the CLI. Schema drift between app and
  CLI MUST NOT be possible.
- **FR-031**: Unknown fields in incoming CloudKit records MUST be ignored,
  not cause crashes (forward compatibility for future schema additions).
- **FR-032**: Missing required fields in incoming CloudKit records MUST
  cause that specific record to be skipped with a logged warning, not
  crash the app.

#### Privacy & access

- **FR-040**: All briefing content and user events MUST be stored
  exclusively in the user's iCloud Private Database. No data MUST be sent
  to any third-party server.
- **FR-041**: When iCloud is not available (not signed in, account
  disabled, container quota exceeded), the app MUST display a clear,
  actionable state — never crash, never blank screen, never silent
  failure.

---

### Key Entities

- **Briefing**: One day's complete content. Keyed by `date` (YYYY-MM-DD).
  Contains: ordered list of Containers, `generatedAt` timestamp,
  `generatedBy` agent name. There is exactly one Briefing per (account,
  date) pair after a successful publish.

- **Container**: A render slot inside a Briefing. Carries no product
  semantics. Contains: `id` (caller-supplied UUID), `title`, optional
  `subtitle`, `order` (sparse int), `layout` (`auto | list | grid | hero`),
  `style` (`neutral | success | warning | accent`), ordered list of Cards.

- **Card**: A single unit of displayed content. Contains: `id`,
  `type` (whitelisted enum), `size` (whitelisted enum), `style`
  (whitelisted enum), `payload` (type-specific strongly-typed struct).

- **UserEvent**: A single tap by the user against a card. Append-only,
  immutable once written. Contains: `id`, `timestamp`, `device` (human-
  readable device identifier), `cardId`, `action` (`done | star`).

- **CardType**: Enum of allowed `type` values. v1 set: `metric`, `insight`,
  `agentSummary`, `todoList`, `trending`, `digest`, `sectionHeader`. Each
  has a strongly-typed payload schema documented in CLI `--help` output.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An agent script can publish a complete briefing (1 briefing,
  3 containers, 6 cards across at least 4 types) from a cold start (CLI
  not previously invoked this hour) in under 5 seconds end-to-end.

- **SC-002**: A briefing published on Mac is visible on a signed-in iPad
  or iPhone within 60 seconds in 95% of test runs on a typical home
  internet connection.

- **SC-003**: The app launches and displays the most recent locally-cached
  briefing within 1 second on iPhone 15 (or newer) running iOS 26, even
  when the device is offline.

- **SC-004**: An operator can read the CLI's `--help` output and
  `schema list` output for the first time, then write a correct
  `aidash card put …` invocation for every v1 card type without consulting
  source code or external documentation.

- **SC-005**: Schema validation rejects 100% of malformed payloads
  (wrong type, wrong size, missing required field, oversize payload) at
  the CLI boundary; zero malformed records reach CloudKit.

- **SC-006**: The owner taps "done" or "star" on a card and within 100ms
  sees visual feedback in the app, in 100% of taps on iPhone 15 or newer
  running iOS 26. Specifically: `done` shows a checkmark / strikethrough
  state, and `star` plays its animation and transitions to its filled
  state.

- **SC-006b**: In a usability check with five-second exposure to a
  briefing screen, observers can correctly identify the star action as
  "more important / more prominent" than the done action in 100% of
  test cases (validates that the star prominence requirement in FR-020
  is actually visually achieved, not just declared).

- **SC-007**: After 7 days of daily briefings (worst case ~50 cards/day
  × 7 = 350 cards), the iPhone app's cold-launch time remains under 2
  seconds.

- **SC-008**: Across a 30-day pilot with the owner as sole user, zero
  briefing publishes are reported lost (i.e. published on Mac but
  permanently invisible on iPad/iPhone after sync completes).

---

## Assumptions

- The owner has an active paid Apple Developer account, enabling
  CloudKit Private DB at production scale and TestFlight distribution
  for cross-device testing during development.

- All devices (Mac, iPad, iPhone) used by the owner are signed into the
  same iCloud account; multi-account is explicitly out of scope.

- All agents that publish briefings run on the owner's Mac and have
  permission to invoke the `aidash` CLI binary. Agents on iOS or in
  cloud services are out of scope for v1 (constitution Principle II).

- Network connectivity is "typical home / office WiFi or LTE"; offline-
  first behavior is required but constant offline use is not optimized.

- The CLI's authoritative schema (via `--help` and `schema list`) is
  considered sufficient agent documentation; no separate developer
  portal or web docs are required for v1.

- The owner does not require a way to "snooze", "schedule for later", or
  otherwise schedule briefing actions through the app; if such behavior
  is desired, the agent that authors the briefing implements it server-
  side.

- Push notifications ("today's briefing is ready") are out of scope for
  v1. Owners discover new briefings by opening the app. If push proves
  necessary in v2, CloudKit Subscriptions are the planned mechanism, not
  third-party push services.

- Widget extensions (lock screen, home screen, StandBy) are out of scope
  for v1. They are an obvious v2 extension on top of the same CloudKit
  data.

- macOS 26, iPadOS 26, and iOS 26 are the only supported OS versions.
  No back-compatibility shims for OS 25 or earlier.

- CloudKit sync latency is opaque to the app and is not a contractual
  Apple SLA. All "within N seconds" targets (FR-015, FR-023, SC-002) are
  based on Apple's documented typical sync behavior for Private Database
  pushes on iCloud, not guaranteed numbers. If real-world test runs
  show consistently higher latency, success criteria SC-002 may be
  relaxed in a v1.x amendment rather than treated as a defect.
