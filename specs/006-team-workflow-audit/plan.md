# Implementation Plan: On-Demand Team Workflow Audit

**Branch**: `006-team-workflow-audit` | **Date**: 2026-08-30 | **Spec**: `specs/006-team-workflow-audit/spec.md`

**Input**: Feature specification from `specs/006-team-workflow-audit/spec.md`

## Summary

Import already-produced, immutable Team Workflow Audit bundles through an
opt-in manual aidata source, normalize them into L1–L5 facts, and publish the
latest accepted snapshot into today's AIDash briefing as bounded typed
`teamAudit` cards. The payload preserves the three independent core axes and a
separate Task Effectiveness axis, findings, evidence timelines, individual
metrics, limitations, and hosted Archify relationships. Owner acknowledgement
and remediation approval reuse the existing append-only UserEvent seam and
record receipts only; no layer invokes an audit, changes source state, or
dispatches remediation.

## Technical Context

**Language/Version**: Swift 6.0/6.2 strict concurrency; repository-supported Python 3

**Primary Dependencies**: Foundation, SwiftUI, SwiftData, CloudKit, CryptoKit; existing Python standard-library/SQLite stack; no new third-party dependency

**Storage**: append-only aidata raw/clean data and immutable warehouse facts; existing SwiftData mirror + CloudKit Private DB UserEvent path; briefing payload remains CloudKit-authored through CLI/XPC

**Testing**: resolver-driven package/pytest/repository gates, XCTest/Swift Testing, neutral fixtures, hook-driven local verification, CI-only App/CLI heavy builds

**Target Platform**: macOS 26+, iPadOS 26+, iOS 26+; manual import on macOS

**Project Type**: multi-package Apple application + macOS CLI + layered Python data producer

**Performance Goals**: each encoded card payload ≤256 KB; deterministic replay without duplicate facts/cards; today's briefing remains bounded and glanceable

**Constraints**: audit is never scheduled/invoked; immutable redacted inputs; no raw logs; HTTPS-only links; flat Briefing → Container → Card hierarchy; no direct Python/CLI CloudKit access; no local host-based App tests

**Scale/Scope**: latest baseline or incremental snapshot, fixed baseline cohort normally 20 cases, bounded multi-card parts, all P0/P1 evidence prioritized, single Owner across synced devices

## Constitution Check

### Pre-design gate

| Principle / bar | Result | Evidence |
|---|---|---|
| I. Agent-Authored, User-Read | PASS after 1.13.0 amendment | Owner issue explicitly authorizes two structured audit receipts; amendment keeps content agent-authored and denies execution authority |
| II. CLI writes content / App writes events | PASS | aidata publishes through existing CLI/XPC; only AIDashApp appends UserEvent rows |
| III. Glanceable flat briefing | PASS | latest snapshot appears as one normal container with bounded card parts; no navigation tree |
| IV/VI. Typed schema and orthogonal card dimensions | PASS | one Core-owned `teamAudit` payload; audit state/priority are content, not size/style chrome |
| Scope Discipline | PASS | each implementation task owns one resolver leaf and exact files; sibling exclusions are explicit |
| URL policy | PASS | only central-policy HTTPS links become actionable; local/custom schemes remain text |
| Error handling | PASS | invalid/missing evidence and write failure degrade visibly, never trap |
| Accessibility/i18n/test coverage | PASS by plan | UI task includes semantic copy, hit targets, previews, action/round-trip tests |
| Public-repo identity | PASS | contracts use neutral references and configurable ignored local import root; no account/workspace/machine IDs |
| Hook-driven verification | PASS | tasks use resolver gates; App/CLI builds stay CI-only |

### Post-design re-check

PASS. Design artifacts retain every gate above. No dependency direction is
reversed, no new persistence authority or dependency is introduced, and every
cross-layer behavior is represented by a contract plus dependency edge.

## Project Structure

### Documentation (this feature)

```text
specs/006-team-workflow-audit/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── manual-import.md
│   ├── card-payload.md
│   └── owner-decision-events.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
aidata/
├── cli.py, config.py, config_local.example.py       # AidataFoundation manual registry/config
├── adapters/                                         # AidataL1L2 import + event normalize
├── schema/warehouse.sql, merge.py                    # AidataL3 immutable facts
├── L4_serve/queries/team-audit/                      # AidataL4 named read-only queries
└── L5_apps/digest/                                   # AidataL5 fetch + card publication

Packages/
├── AIDashCore/                                       # typed payload + UserEvent actions
├── DesignKit/                                        # classification tint only
└── AIDashUI/                                         # card rendering + action intents

Apps/AIDashApp/                                       # schema advertisement + append-only writer wiring
```

**Structure Decision**: Preserve the repository's existing resolver leaves.
No new package, target, network client, store, or application surface is
introduced. New files live inside existing owned scopes and every new test is
added to the matching router `test_paths` in the same layer task.

## Module and Seam Design

### `TeamAuditPayload` module

**Interface**: one common snapshot envelope plus five locked section variants
and validation invariants defined by `contracts/card-payload.md`.

**Implementation hidden behind it**: mode reconciliation, axis-count
validation, typed finding states, bounded part semantics, evidence identity,
and graceful URL presentation. Callers learn one CardType and section enum,
not multiple audit card schemas.

**Test surface**: Core round trips/invariants and UI rendering through
`CardType.decode`/`CardRouter`.

### Manual import seam

**Interface**: explicit `collect/normalize --source team_audit_snapshot` over a
configured bundle root.

**Adapters**: production filesystem bundle adapter and hermetic fixture
adapter. Default source selection is a separate no-op path that excludes the
manual source.

**Implementation hidden behind it**: redaction, hashing, replay/collision
handling, upstream schema normalization, and sidecar association.

### Owner decision seam

**Interface**: two AIDashUI intent closures targeting `(cardID,
findingFingerprint)` plus two persisted receipt sets.

**Adapters**: AIDashApp's SwiftData/CloudKit-backed writer and the UI's nil/spy
test adapters. The App writer owns append-only idempotency; the UI never sees
persistence.

## Vertical Delivery Slices

### US1 — Read a trustworthy baseline or incremental snapshot

**Outcome**: An explicitly imported snapshot appears in today's briefing with
scope/provenance/limitations, baseline cohort or incremental cursors, three
independent core axes, and separate Task Effectiveness.

**Layer path**:

`AidataFoundation → AidataL1L2 → AidataL3 → AidataL4 → AidataL5 → AIDashCore → DesignKit → AIDashUI → AIDashApp schema advertisement`

Core and aidata contract tasks may proceed in parallel after the planning
contract; AidataL5 waits for L4 and Core; UI waits for Core and DesignKit; App
schema advertisement waits for Core. The slice is independently demonstrated
with baseline/incremental fixtures and no audit invocation.

### US2 — Inspect findings, timelines, metrics, and artifacts

**Outcome**: The same typed publication exposes all six lifecycle states,
stable fingerprints, redacted case/attempt evidence, individual metrics, and
safe generic/team/P0/P1 Archify relationships.

**Dependencies**: US1 publication seam and card registration. Detail-specific
AidataL4 queries, L5 partitioning, and AIDashUI sections may land as separate
layer tasks without changing the common Core contract.

**Independent demonstration**: a neutral evidence fixture renders each detail
section; unsafe URLs are text and valid HTTPS artifacts preserve fingerprint,
event, hash, and revision relationships.

### US3 — Record acknowledgement or remediation approval safely

**Outcome**: The Owner records an idempotent append-only receipt for a stable
finding and sees it without changing canonical snapshot state or starting
remediation. Optional HTTPS grill links only open a destination.

**Layer path**:

`AIDashCore event contract → AIDashUI intent interface → AIDashApp writer/wiring → AidataL1L2 event normalization`

**Dependencies**: US2 findings renderer supplies the stable decision target.
The slice is independently proven by intent spies, in-memory event persistence,
action normalization, immutable-snapshot comparison, and zero-dispatch spies.

## Cross-Layer Contracts

| Contract | Producer | Consumer | Blocking edges |
|---|---|---|---|
| Manual snapshot bundle | External explicit operator + AidataL1L2 | AidataL3 | Foundation registry before adapter; adapter before schema merge |
| Immutable warehouse facts | AidataL3 | AidataL4 | L3 before query definitions |
| Named audit query bundles | AidataL4 | AidataL5 | L4 before mapping/publication |
| `teamAudit` JSON payload | AIDashCore | AidataL5, AIDashUI, AIDashApp schema advertisement, generic CLI | Core before mapping/render/schema; contract check after assembled changes |
| Classification tint | DesignKit | AIDashUI | DesignKit before final UI renderer |
| Audit action intent | AIDashUI | AIDashApp | Core action enum before both; UI interface before App wiring |
| `UserEvent` audit actions | AIDashApp | aidash events pull → AidataL1L2 | Core enum before App and adapter normalization |
| Hosted artifact manifest | AidataL1L2/L3/L4/L5 | AIDashCore payload + AIDashUI URLPolicy | manual import contract before detail publication |

## Dependency Graph

```text
T001 RepoInfra contracts/constitution
 ├─> T002 AidataFoundation manual registry
 │    └─> T003 AidataL1L2 import
 │         └─> T004 AidataL3 facts
 │              └─> T005 AidataL4 queries
 │                   └─> T009 AidataL5 publication
 ├─> T006 AIDashCore teamAudit payload ───────┬─> T009
 │                                            ├─> T010 AIDashUI renderer
 │                                            └─> T011 AIDashApp schema advertisement
 └─> T007 DesignKit classification ─────────────> T010

T005 + T006 + T007 ─> T008 US1/US2 contract fixture proof
T006 ─> T012 AIDashCore audit decision actions
T010 + T012 ─> T013 AIDashApp writer/wiring
T012 ─> T014 AidataL1L2 decision normalization
T013 + T014 ─> T015 US3 no-dispatch integration proof
all ─> T016 assembled contract/routing verification
```

The graph is acyclic. Parallel markers are allowed only for tasks whose files
do not overlap and whose blocking contract has landed.

## Verification Strategy

- Each task declares exactly one resolver layer and the exact
  `scripts/context/run <layer> --mode local` command when that leaf has local
  gates.
- Any task changing `aidata/CONTEXT.md`, layer frontmatter, or test routing also
  runs `scripts/context/audit`.
- Cross-language payload assembly runs
  `.claude/skills/aidash-content/scripts/contract_check.sh` in the integration
  verification task.
- Commit and push normally so repository hooks provide fresh selected-gate
  evidence. Do not bypass hooks.
- AIDashApp and aidash heavy build gates run only in CI. The host-based
  AIDashApp test target is forbidden locally.
- Exact implementation SHA must match local HEAD, remote branch, and PR head
  before independent implementation review.

## Complexity Tracking

No constitutional violation remains. Constitution 1.13.0 is an authorized
planning amendment that narrows the new actions to append-only audit receipts
and explicitly denies workflow execution authority.
