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

**Performance Goals**: each final serialized card payload ≤262,144 bytes; deterministic replay without duplicate facts/cards; today's briefing remains bounded and glanceable

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
CLI/aidash/                                           # audit UserEvent action filtering/help
.claude/skills/aidash-content/ + scripts/             # revision-local assembled contract gate
```

**Structure Decision**: Preserve the repository's existing resolver leaves.
No new package, target, network client, store, or application surface is
introduced. New files live inside existing owned scopes and every new test is
added to the matching router `test_paths` in the same layer task.

## Module and Seam Design

### `TeamAuditPayload` module

**Interface**: one common snapshot envelope plus eight locked section variants
and validation invariants defined by `contracts/card-payload.md`.

**Implementation hidden behind it**: mode reconciliation, axis-count
validation, typed finding states, complete lineage/repeat metrics, collision
observations, bounded part/externalization semantics, mandatory artifact
capacity, evidence identity, and graceful URL presentation. Callers learn one
CardType and section enum, not multiple audit card schemas.

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
independent core axes, separate Task Effectiveness, every P0/P1 finding, and
all mandatory generic/team/P0/P1 artifact links. L4 supplies immutable required
inputs; L5 packs them and computes final publication coverage.

**Layer path**:

`AidataFoundation → AidataL1L2 → AidataL3 → AidataL4 → AidataL5 → AIDashCore → DesignKit → AIDashUI → AIDashApp schema advertisement`

Core and aidata contract tasks may proceed in parallel after the planning
contract; AidataL5 waits for L4 and Core, computes published/omitted/externalized
results after packing, and emits the mandatory set; UI waits for Core and
DesignKit and renders it read-only; App schema advertisement waits for Core.
The slice is independently demonstrated with baseline/incremental fixtures and
no audit invocation.

### US2 — Inspect findings, timelines, metrics, and artifacts

**Outcome**: The same typed publication adds optional/detail views for all six lifecycle states,
stable fingerprints, redacted case/attempt evidence, complete feedback
lineage, per-role repeat/cause/role-specific metrics, collision observations,
individual metrics, optional artifacts/grill links, and full-report
externalization without changing US1's mandatory set.

**Dependencies**: US1 publication seam and card registration. Detail-specific
AidataL4 queries, L5 partitioning, and AIDashUI sections may land as separate
layer tasks without changing the common Core contract.

**Independent demonstration**: a neutral evidence fixture renders every typed
detail section; unsafe optional URLs are text, unsafe mandatory URLs reject
publication, valid HTTPS artifacts preserve fingerprint/event/hash/revision
relationships, mandatory link counts reconcile, and exact payload-size boundary
fixtures prove reject/externalize behavior.

### US3 — Record acknowledgement or remediation approval safely

**Outcome**: The Owner records an idempotent append-only receipt for a stable
finding and sees it without changing canonical snapshot state or starting
remediation. Optional HTTPS grill links only open a destination.

**Layer path**:

`AIDashCore event contract → AIDashUI intent interface → AIDashApp writer/wiring → aidashCLI filtering + AidataL1L2 event normalization`

**Dependencies**: US2 findings renderer supplies the stable decision target.
The slice is independently proven by intent spies, in-memory event persistence,
action normalization, immutable-snapshot comparison, and zero-dispatch spies.

## Cross-Layer Contracts

| Contract | Producer | Consumer | Blocking edges |
|---|---|---|---|
| Manual snapshot bundle | External explicit operator + AidataL1L2 | AidataL3 | Foundation registry before adapter; adapter before schema merge |
| Collision observations | AidataL1L2 | AidataL3 → AidataL4 → AidataL5 → AIDashUI | Independently keyed observation carries parent snapshot ID/hash and never updates accepted content |
| Immutable warehouse facts | AidataL3 | AidataL4 | L3 before query definitions |
| Named audit query bundles | AidataL4 | AidataL5 | L4 exposes immutable required entities/counts and optional facts only; L5 alone computes final publication coverage after packing |
| `teamAudit` JSON payload | AIDashCore | AidataL5, AIDashUI, AIDashApp schema advertisement, generic CLI | Payload carries snapshot + sidecar identity/hash and explicit finding identity; Core before mapping/render/schema |
| Classification tint | DesignKit | AIDashUI | DesignKit before final UI renderer |
| Audit action intent | AIDashUI | AIDashApp | Core action enum before both; UI interface before App wiring |
| `UserEvent` audit actions | AIDashApp | aidashCLI events pull → AidataL1L2 | Core enum before App, CLI filter, and adapter normalization |
| Hosted artifact sidecar | AidataL1L2/L3/L4/L5 | AIDashCore payload + AIDashUI URLPolicy | stable sidecar ID/exact byte hash, typed grill/full-report fields, mandatory invalid-link rejection, optional invalid-link text |
| Assembled contract checker | RepoInfra hook gate | Core/App/UI/AidataL5 revision | T018 waits for all adapters, resolves current worktree, and runs only through normal hook selection |

## Dependency Graph

```text
US1 data: T001 → T002 → T003 → T004 → T007
US1 app:  T005 ─┬→ T007
                ├→ T008 ← T006
                └→ T009

US2 data: T004 → T010 → T011 (T011 also waits for T007)
US2 UI:   T008 → T012

US3 core: T005 → T013
US3 CLI:  T013 → T017
US3 UI:   T012 + T013 → T014
US3 App:  T009 + T014 → T015
US3 data: T002 + T013 → T016

Assembled RepoInfra gate:
T007 + T008 + T009 + T011 + T012 + T015 + T016 + T017 → T018
```

The graph is acyclic. Parallel markers are allowed only for tasks whose files
do not overlap and whose blocking contract has landed.

## Verification Strategy

- Every task commits and pushes normally with `core.hooksPath=scripts/hooks`.
  The hooks run the routing audit, resolve changed paths, and execute affected
  leaves' declared local gates; this hook result is the authoritative local
  evidence.
- Do not invoke suites or resolver gates proactively. After an observed hook
  failure, one focused resolver rerun for the emitted layer is diagnostic-only;
  the next normal commit/push must still supply the passing hook evidence.
- T018 corrects the cross-language checker to use the current worktree and
  current App/Aidata anchors, registers it as a RepoInfra lint gate, and runs
  it once through normal hook selection on the assembled revision.
- AIDashApp and aidashCLI heavy build gates run only in CI. The host-based
  AIDashApp test target is forbidden locally; the hostless target is only a
  focused diagnostic exception after a concrete failure.
- Exact implementation SHA must match local HEAD, remote branch, and PR head
  before independent implementation review.

## Complexity Tracking

No constitutional violation remains. Constitution 1.13.0 is an authorized
planning amendment that narrows the new actions to append-only audit receipts
and explicitly denies workflow execution authority.

When the amendment-bearing PR is created, its title must use
`constitution: <change>` and retain the 1.13.0 migration note, as required by
Constitution Governance. Planning review does not substitute for that PR gate.
