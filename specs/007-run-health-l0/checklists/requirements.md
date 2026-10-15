# Specification Quality Checklist: Dev Team Run-Health L0 Collection

**Purpose**: Verify Specify-stage completeness and implementation readiness.
**Created**: 2026-10-15
**Feature**: `specs/007-run-health-l0/spec.md`

## Content Quality

- [x] User value and raw-collection boundaries are stated before implementation design.
- [x] Every user story is prioritized and independently fixture-testable.
- [x] Existing, compatible, and explicitly removed behavior are separated.
- [x] L0 terminology is reconciled with the repository's physical L1 raw boundary.
- [x] No unresolved clarification marker remains.

## Requirement Completeness

- [x] Per-agent run discovery explicitly replaces issue-number discovery.
- [x] Non-terminal runs remain refreshable until an explicit terminal status.
- [x] Queue, failure, cancellation, usage, and run-model absence semantics are testable.
- [x] Copilot empty usage is preserved without fabricated tokens or model.
- [x] Message cursor, stable identity, overlap, and replay behavior are explicit.
- [x] Raw message/tool content is structurally excluded before persistence.
- [x] Canonical bytes, SHA-256 representation, and byte-length semantics are fixed.
- [x] Red-line configuration, priority, pre-hash ordering, initial rules, and near misses are fixed.
- [x] Agent snapshot change detection and allowed fields are fixed.
- [x] Runtime usage/activity provenance and empty-response semantics are fixed.
- [x] Timeline activity-only mode, per-issue overlap, stable event identity, and truncation evidence are fixed.
- [x] Issue–PR candidate URL shape, provenance, normalization, and privacy boundary are fixed.
- [x] Existing schedule and normalized consumer compatibility are explicit.
- [x] Read-only enforcement and fixture-only CI are machine-verifiable.
- [x] The real local acceptance run names all seven resulting raw families and its privacy-safe evidence shape.

## Outcome Verifiability

- [x] Old-issue/new-run and running-to-terminal fixtures directly demonstrate the stale-data repair.
- [x] Secret-sentinel serialization checks directly demonstrate privacy.
- [x] Positive and near-miss rule fixtures directly demonstrate token-aware matching.
- [x] Replay fixtures directly demonstrate stable identities and cursor safety.
- [x] A subprocess spy directly demonstrates read-only commands and no live CI access.
- [x] Empty usage fixtures distinguish absent telemetry from measured zero.

## Scope and Architecture

- [x] No L2/L3/L4/L5 schema, query, metric, digest, card, or UI work is authorized.
- [x] No new scheduled source or cron runner change is required.
- [x] Configuration and adapter work are separated by owning repository layer.
- [x] Tracked defaults contain no real workspace, agent, runtime, email, or local-path value.
- [x] Existing tests may not be removed, skipped, or weakened.
- [x] Any out-of-layer failure becomes a separate task rather than scope expansion.

## Readiness

- [x] Research resolves agent enumeration, pagination honesty, usage absence, hashing, red-line order, timeline truncation, and PR provenance.
- [x] The data model defines stable keys, state transitions, relationships, and forbidden fields.
- [x] The L0 contract defines allowed persistence DTOs and read-only commands.
- [x] The plan passes pre- and post-design constitution checks.
- [x] Tasks can be issued as one Foundation dependency, one Adapter implementation, and one no-code acceptance-evidence step in one PR goal.
