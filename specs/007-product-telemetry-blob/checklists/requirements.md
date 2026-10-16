# Specification Quality Checklist: Manual Product Blob Batch Landing

**Purpose**: Validate the canonical manual-batch plan before exact-revision review.

**Created**: 2026-10-16

**Feature**: `specs/007-product-telemetry-blob/spec.md`

**Normative collector contract**: `specs/007-product-telemetry-blob/contracts/manual-batch-collector.md`

## Authority and scope

- [x] Live-main base `eb292dc041dab6c5722e270f0f138ecd35949509` is exact.
- [x] The manual-batch collector contract is the single normative source for reader behavior, threat model, JSON, completion-directory semantics, operator boundary, privacy, and T7 evidence.
- [x] ADR-005 and the reader/spec/data-model contracts point to the superseding contract without duplicating an alternative design.
- [x] Merged producer, consent, event-wire authority, generic `collect`, runner, cron, and unrelated repository behavior remain unchanged.
- [x] Prior `499b40cb` implementation evidence and `a7807696` → `e8b60e9` → `00e01d8` → `4d0738b` planning evidence remain historical and are not an implementation base.
- [x] No Constitution, gate, product, test, configuration, dependency, credential, scheduler, or live-resource change is part of this planning commit.

## Requirement completeness

- [x] Scope is VoxPocket-only, manual-only, one allow-listed prefix, and the Owner's existing read-only AAD identity.
- [x] Exact Azure CLI version/cloud preflight, login batch argv, allow-listed environment, private output, and non-retention are specified.
- [x] Startup rejects symlink or non-directory destination terminals under the trusted same-user local-filesystem threat model.
- [x] A private same-filesystem temporary stage retains opaque gzip bytes and publishes one immutable non-empty completion directory through fsync and one atomic directory rename.
- [x] Failure, interruption, and empty success create no completion; abandoned stages are ignored; a post-rename batch remains complete even if the response is lost.
- [x] The success JSON envelope excludes endpoint, identity, resource identifier, Blob name, payload, and absolute private path; all failures use one fixed neutral JSON error.
- [x] Later runs create independent batches; no cross-run incremental, deduplication, recovery, resume, or idempotency claim remains.
- [x] The external GNU 300-second KILL command is an operator boundary, not a scheduler or supervisor.
- [x] Private T7 evidence binds one TestFlight build, one real Blob, and one completion batch, then scopes filtered/count evidence to that batch and Blob without publishing private values.
- [x] Every requirement has T101, T102, or the external T7 milestone as its owner.

## Layer and task quality

- [x] RepoInfra authority is reviewed and merged before implementation.
- [x] T101 is a self-contained AidataFoundation task with exact CLI/config/adapter/test/context paths and matching parent/leaf routing.
- [x] T102 is a self-contained AidataL1L2 task with exact staging/publication/test/context paths and matching parent/leaf routing.
- [x] Dependency order is RepoInfra → T101 → T102; changed implementation layers produce separate verifiable commits and review binds the final descendant-chain head.
- [x] No AidataOps, registry, scheduler, activation, L2-L5, dependency, query-product, custom pagination/checkpoint, or second-supervisor task exists.
- [x] A retained-production defect stops execution and returns exact evidence to Team Lead instead of widening T101 or T102.
- [x] Existing tests are not deleted, skipped, weakened, or replaced; any future exception requires Owner approval on the published final PR head.

## Proof quality

- [x] One executable fake `az` drives the real CLI/adapter boundary and records only commands actually invoked.
- [x] Assertions observe literal argv/environment/privacy behavior and real temporary filesystem outcomes rather than fixture declarations, generic traces, or test counts.
- [x] Hermetic cases cover preflight, non-empty success, empty success, ordinary failure, interruption, unsafe terminals, abandoned stage, and a later independent batch.
- [x] Lower-layer durability evidence covers file and directory sync plus the single atomic directory publication boundary.
- [x] Hook/CI ownership and static checks follow repository policy; no planning claim treats unrun suites as executed evidence.

## Public-repository safety

- [x] Tracked endpoint and prefix selectors remain empty and examples remain neutral.
- [x] No personal operator/principal metadata, real endpoint, account/container value, prefix, Blob name, resource identifier, payload, private path, token, SAS, account key, secret, or credential field is recorded.
- [x] Public evidence is limited to neutral revisions, command shape, completion identifier, object count, and byte count as permitted by the normative contract.
- [x] Real T7 associations remain only in the Owner's private workflow evidence file.

## Coverage result

- [x] Producer FR-001–FR-004 remain unchanged and owned by merged authority.
- [x] Manual collector FR-005–FR-007 and success criteria map to T101/T102 and the external T7 milestone.
- [x] Removed per-file/page/custom-cap/L2-L5/Ops behavior is explicitly superseded rather than silently retained.
- [x] The graph is acyclic, contains no unattended execution path, and has no known P0/P1 planning gap before exact-revision review.
