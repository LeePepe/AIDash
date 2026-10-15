# Specification Quality Checklist: Dev Team Run-Health L1 Collection

**Purpose**: Verify Specify-stage completeness and implementation readiness.
**Created**: 2026-10-15
**Feature**: `specs/007-run-health-l1/spec.md`

## Content quality

- [x] User value and L1 collect boundary precede implementation design.
- [x] Every story is prioritized and independently fixture-testable.
- [x] Existing, compatible, and removed behavior are separated.
- [x] Aidata terminology uses only L1 collect.
- [x] No unresolved clarification/template marker remains.

## Requirement completeness

- [x] Per-agent discovery replaces issue-number run discovery; unknown/non-terminal runs stay refreshable.
- [x] Queue/failure/cancellation/model/usage absence semantics are explicit.
- [x] Lifecycle sanitizer ordering, allowed fields, byte cap, raw/normalized proof, and stable cancelled-by ID are fixed.
- [x] Message cursor/identity/overlap, canonical hash/length, and raw-content exclusion are fixed.
- [x] Red-line configuration, priority, pre-hash ordering, initial rules, and near misses are fixed.
- [x] Agent snapshot transition ordinal plus complete pending projection preserves `A → B → A` and replays B exactly if the live source becomes C before retry.
- [x] Runtime usage/activity provenance and truthful empty wrappers are fixed.
- [x] Timeline activity-only overlap/event-marker/truncation and PR-link provenance/privacy are fixed.
- [x] `copilot_otel` registration, ordered runner equality that rejects omissions/duplicates/reordering, existing cadence, no-op normalizer, and no-merge boundary are fixed.
- [x] OTel binary byte offsets, incomplete tail, rotation/truncation generation, malformed-line behavior, and state ordering are fixed.
- [x] OTel fixed neutral source-slot allowlist, field allowlist, and response/context/content/path/free-label exclusions are fixed.
- [x] Conversation ID plus timestamp/window sufficiency is retained without L1 attribution; zero/multiple future matches are unresolved.
- [x] Read-only Multica enforcement and fixture-only/private-path-free CI are machine-verifiable.
- [x] Real acceptance requires a persisted row and sample for all eight families; zero rows block.
- [x] Fixed-candidate evidence precedes independent review; remote/PR proof follows PASS and publication.

## Outcome verifiability

- [x] Old-issue/new-run and non-terminal-to-terminal fixtures prove stale-data repair.
- [x] DTO/raw/normalized secret/path sentinels prove lifecycle privacy.
- [x] Positive/near-miss rule fixtures prove token-aware matching.
- [x] `A → B → A`, write failure, and pending-B/crash/source-C retry prove snapshot history/idempotency.
- [x] Complete/partial/resume/rotate/truncate fixtures prove OTel cursor correctness.
- [x] OTel serialized sentinels and shared-session windows prove privacy and deferred attribution.
- [x] Command/file spies prove hermetic CI.
- [x] Eight-family nonzero evidence directly proves real wiring.

## Scope and architecture

- [x] No L2 schema/output, L3/L4/L5 consumer, metric, query, digest, card, or UI work is authorized.
- [x] `copilot_otel` adds one registered source to the existing cadence, not a timer; `MERGE_SOURCES` stays unchanged.
- [x] Foundation, L1L2, and Ops changes are separate commits with exact paths.
- [x] Tracked defaults contain no real workspace, agent, runtime, email, slot path, or local identifier.
- [x] Existing tests remain active and unweakened.
- [x] Installed Hermes runner sync is owned by the lead's CLI session on the Owner's Mac after merge, with merged-SHA/sync/full-chain receipts and no squad or prepublication host mutation.

## Readiness

- [x] Research resolves source registration/no-op normalize, pagination, privacy, empty usage, transition identity, offsets, OTel projection/join boundary, timeline truncation, and review order.
- [x] Data model defines stable keys, pending/committed state, stream cursor, relationships, and forbidden fields.
- [x] L1 record contract defines allowed DTOs and read-only commands.
- [x] Acceptance matrix maps all 42 IDs exactly once.
- [x] Plan passes pre/post-design constitution checks.
- [x] Tasks are schedulable as T001 Foundation → T002 L1L2 → T003 Ops → T004 evidence/review/publication → merge → T005 lead-operator cadence activation.
