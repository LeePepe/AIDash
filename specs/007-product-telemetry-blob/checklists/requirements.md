# Specification Quality Checklist: Product Telemetry Blob Pipeline

**Purpose**: Validate completeness before exact-revision implementation handoff.
**Created**: 2026-10-15
**Feature**: `specs/007-product-telemetry-blob/spec.md`

## Authority and scope

- [x] Accepted v6 hash, fixed repository base, D-01/D-02, and stable FR-001–FR-007 are preserved.
- [x] OA-002 is persisted as the single `aad-owner-local` contract without copying real resource or personal identity metadata.
- [x] Owner-authorized constitution 1.14.0 amendment, migration note, and required PR title are persisted; implementation waits for amendment merge.
- [x] Lead replacement decision `no-reset-v1` is persisted: default-off Settings consent, one lifetime-stable first-opt-in random install ID, same-ID disable/re-enable, GUI-only construction, and no Reset/rotation/shared reset API/private-catalog parsing.
- [x] REL-001 remains a dependency-resolution gate, not a planning blocker.
- [x] VitalStride, VoxPocket/T3, Azure mutation, credentials, L5, and fixed-install entitlement changes are excluded.
- [x] No implementation or live canary is included in the planning slice.

## Requirement completeness

- [x] Each requirement is testable and has an owning task or explicit external closure.
- [x] GUI, headless, test-host, disabled, rollback, and unsafe-event behavior are specified.
- [x] `aidash.action` and `aidash.performance.ready_scene` have exact triggers, typed properties, no sampling, lifecycle cardinality, and monotonic timing formula.
- [x] Consent source/default/persistence/lifecycle, first-opt-in-only install-ID creation, fail-closed invalid established identity, and production read seam are exact and cross-platform.
- [x] Hostless acceptance covers the same install ID across relaunch and disable/re-enable and proves no Reset/rotation/shared-reset/private-catalog path exists.
- [x] Reader no-op, CLI-only DAC, GET-only origin confinement, redirect refusal, and no-fallback behavior are specified.
- [x] Complete-unit checkpoint, deterministic event key, idempotent L3 grain, and read-only L4 query are specified.
- [x] Reader request/run/page/object/byte limits and exact within/after-page checkpoint behavior are measurable.
- [x] E2E evidence covers both products, both event types, rerun, unsafe rejection, authorization, and exact revisions.
- [x] No unresolved clarification marker remains.

## Layer and task quality

- [x] XcodeWorkspace and RepoInfra release changes are separate tasks.
- [x] Azure Identity manifest/Foundation work and RepoInfra CI install are separate tasks.
- [x] Factory/no-op assertions belong to AIDashApp, not XcodeWorkspace.
- [x] Every task lists one owning layer, exact paths, exclusions, contract impact, acceptance, verification, and dependencies.
- [x] Every T001–T010 cites §A Scope Discipline plus applicable constitution 1.14.0 sections; T005 also cites §E Accessibility/§F Internationalization; all use hook/CI-owned test evidence rather than direct local suite commands.
- [x] DATA-FOUND and DATA-OPS remain non-activating; DATA-ACTIVATE atomically registers the source only after adapter/schema/query/runner readiness.
- [x] Every new aidata test/manifest includes parent and leaf routing updates.
- [x] E2E-05 is external evidence, not a fake implementation leaf.

## Dependency and ADR quality

- [x] ADR-004 covers LokiKit scope, alternatives, build/platform/concurrency cost, GUI-only behavior, rollback, and ADR-003 caveat.
- [x] ADR-005 covers Azure Identity, exact lock/CI cost, CLI-only DAC, alternatives, operations, and revocation boundary.
- [x] The Azure Storage SDK and raw CLI token subprocess are explicitly rejected.
- [x] Exact dependency identities are required before implementation claims resolution.

## Public-repository safety

- [x] Tracked endpoint selector is empty and examples are neutral.
- [x] No personal operator/principal metadata or real account/container value is present.
- [x] No token, SAS, account key, secret, or credential field is planned for the reader.
- [x] Producer protected values remain runtime-only and are never read by agents.
- [x] Logs, errors, fixtures, evidence, raw/clean/fact rows, and state prohibit credential/identity leakage.

## Coverage result

- [x] FR-001–FR-007 map to tasks/external gates in `tasks.md`.
- [x] US1/US2 acceptance maps to deterministic layer tests.
- [x] US3 maps only to E2E-05 after merged slices and Owner authorization.
- [x] The forward dependency graph is acyclic and independently green at every delivery boundary; rollback ordering is compensating, not a reverse edge.
- [x] No ERROR or CRITICAL coverage gap is knowingly open before exact-revision review.
