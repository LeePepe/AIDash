# Feature Specification: Product Telemetry Blob Pipeline

**Feature Directory**: `007-product-telemetry-blob`
**Created**: 2026-10-15
**Status**: Planning gate
**Input authority**: MY-1816 planning v6, SHA-256 `97dc0822f4ade9f6e70a5c070e9860c6eeb57076e0744f1cdd7744750e8c55f2`, adopted for `LeePepe/AIDash@bdf1435fe7d3d9c4da43ed4297cbc24482447b46`.

## Scope and authority

This package adopts the accepted `SL-AID-PLAN` scope without implementing it. It plans two later delivery slices:

- `SL-AID-PRODUCER`: GUI-only AIDash action and performance telemetry through the reviewed Blob writer contract.
- `SL-DATA`: a read-only `aidata` Blob source through L1/L2, L3, L4, and scheduled-source registration.

It also preserves the cross-repository `SL-E2E` evidence gate. VitalStride implementation, VoxPocket/T3, L5 cards or digests, Azure resource changes, credentials, and live canary execution are outside this repository-planning slice.

### Existing behavior and compatibility

- AIDash has no product telemetry. Constitution 1.14.0 authorizes it only after the amendment is published and merged; GUI, headless XPC, CLI, and test-host modes must remain distinguishable.
- `AIDashCore`, `AIDashUI`, CLI behavior, CloudKit/UserEvent storage, and existing analytics/data sources remain unchanged by this feature.
- `aidata` is a recursively routed Python subsystem. Its external sources are read-only, raw data is append-only, and an unconfigured source degrades to zero records.
- No accepted behavior or test is removed, skipped, weakened, or reclassified.

### Locked decisions

- **D-01 — Product ownership**: action names, performance names, fields, allowlists, sampling, and formulas remain product-local. Shared telemetry owns only generic transport, timing, privacy validation, persistence, and delivery diagnostics.
- **D-02 — Blob wire/durability contract**: producers and the reader use the exact contract in `contracts/blob-wire.md`. Producer credentials remain the previously approved create-only CI inputs and are never read by planning or implementation agents.
- **D-03 — Consent, identity, and AIDash events**: `contracts/aidash-events.md` is the normative AIDash event table. The GUI Settings toggle **Send usage data** is the sole consent source, reads/writes app `UserDefaults.standard`, defaults off, and creates a random persisted install UUID on first opt-in. Disable stops admission/upload but retains pending state; re-enable is fresh consent. Reset stages a generation-bound target UUID and cannot admit or flush until the retained LokiKit catalog proves that target is its current epoch. CLI, headless/XPC, and test-host production composition never constructs the telemetry service.
- **OA-002 / `aad-owner-local` — Reader identity**: the only reader is the Owner's existing Azure AD identity, used locally through the Azure CLI-backed `DefaultAzureCredential` leg. It has read/list authority only. There is no SAS mode, secret field, stored-policy use, or authentication fallback. Missing endpoint/sign-in or initial-token failure before listing returns zero with no state change; a later auth/network failure preserves earlier completed records/object checkpoints and leaves only its incomplete object/page unadvanced. Tracked files use only symbolic identifiers; the real selector belongs only in ignored `aidata/config_local.py`.

## User scenarios and testing

### User Story 1 — Safe GUI telemetry producer (Priority: P1)

As the Owner, I can explicitly enable AIDash GUI telemetry and receive the two events in `contracts/aidash-events.md` without changing headless, CLI, test-host, CloudKit, or UserEvent behavior.

**Independent test**: Hook-owned hostless logic uses isolated preferences and fakes for default-off consent, first-opt-in identity, eligible once-per-lifecycle event emission, and disabled production modes. SDK-backed hostless evidence proves retained-store Reset reconciliation across restart and failure/ambiguous-confirmation retry before admission or flush.

**Acceptance scenarios**:

1. Given a fresh install or missing/malformed consent preference, when any GUI lifecycle begins, then **Send usage data** is off and no install ID, telemetry service, store, timer, uploader, event, or network work is created.
2. Given the first explicit false-to-true opt-in, when preferences persist it, then a random canonical UUID is created once and reused on later launches; empty, unexpanded, or unsafe producer configuration still returns before service/store/timer/uploader/network construction.
3. Given valid configuration and consent already true at eligible GUI launch, when the first `.ready(container)` scene becomes interactive, then `aidash.action` with only `action_name=briefing_viewed` and `aidash.performance.ready_scene` with only finite nonnegative integer `duration_ms` are admitted at 100% sampling and at most once in that lifecycle.
4. Given consent becomes true only after the scene is already ready, readiness never occurs, or consent is revoked before readiness, then no retrospective action/performance event is emitted for that lifecycle.
5. Given headless XPC, CLI, or test-host production composition, when lifecycle seams run, then no telemetry service, store, uploader, timer, or event is constructed.
6. Given consent is turned off or producer rollback begins, when false is persisted, then admission closes and active delivery is disabled/cancelled before quiescence; no pending upload starts/continues, ambiguous in-flight work stays retained/unconfirmed, and a later opt-in may resume eligible retained work only after any pending Reset is proven reconciled.
7. Given Reset before first opt-in, then it is disabled/no-op and creates no ID. Given an existing ID, Reset disables/cancels active delivery before quiescence and atomically persists a target UUID plus opaque generation without rewriting frozen work; while off it constructs nothing. On the next consented valid construction, the retained catalog opens disabled, admission/flush remain closed, and the app reconciles an already-current target or applies SDK reset before proving the target epoch current. It promotes the target and clears only that generation after proof; failure, ambiguity, or stale completion remains pending, closed, and retryable across restart.

### User Story 2 — Read-only product-event analytics (Priority: P1)

As the Owner, I can collect authorized product Blob objects into `aidata`, preserve their provenance and event grain through L3, and query bounded product events from L4 without giving the reader write/delete authority or introducing an L5 consumer.

**Independent test**: A fake Azure transport paginates neutral Blob fixtures, supplies gzip NDJSON to the adapter, reruns collection and merge, and proves one stable L4 row per event with no duplicate and no partial checkpoint after a failed unit.

**Acceptance scenarios**:

1. Given an empty tracked endpoint selector or unavailable Owner-local Azure CLI identity, when `product_blob` collects, then it returns zero and neither contacts the endpoint nor advances state.
2. Given a signed-in authorized identity and paginated objects within `contracts/reader-auth.md` limits, when collection succeeds, then every complete object is parsed, redacted, appended, normalized, and checkpointed exactly once.
3. Given malformed gzip/NDJSON, invalid path, an oversized object, a timeout, a collection-budget/page/object limit, interrupted pagination, or mid-run token/network failure, when a unit cannot complete, then incomplete work emits no record and does not advance its page/object state while previously completed records/checkpoints remain and the wider pipeline continues.
4. Given normalized product events, when L3 merge and the L4 query rerun, then the honest event grain and object provenance remain stable and no analytical duplicate appears.

### User Story 3 — Correlated least-privilege proof (Priority: P2)

As the Owner, I can review a sanitized evidence bundle that correlates both in-scope products' action and performance canaries from producer to Blob, L1 checkpoint, L3 fact, and L4 query while exposing no credential, raw personal identifier, or unrestricted endpoint.

**Independent test**: After the implementation slices and external authorizations are complete, an authorized operator runs the bounded canary contract in `contracts/e2e-evidence.md`; an independent reviewer reconciles object/event fingerprints and exact merged revisions.

**Acceptance scenarios**:

1. Each product's action and performance canary correlates across producer, Blob receipt, L1, L3, and L4 by sanitized stable evidence.
2. A complete rerun adds no duplicate analytical row.
3. An event with an unknown/free-text or non-finite property is absent from accepted persistence, Blob, and L4.
4. Sanitized authorization evidence proves writers cannot list/read/overwrite/delete and the reader cannot write/delete without revealing tokens, SAS, account keys, personal identity metadata, or the real endpoint.

### Edge cases

- Redirects and non-server-trust authentication challenges are refused by producer transport.
- Only HTTP `201`, or an ambiguous immutable retry receiving the exact qualified overwrite rejection, may remove producer queue work.
- Changed destinations, corrupt sidecars, or source/body mismatches retain and block a producer batch.
- Consent disabled while work is pending retains the queue but forbids upload; a pending Reset blocks admission/flush until catalog proof and never rewrites a frozen batch's install-ID-bearing path.
- Ready-scene duration uses a monotonic clock and rejects negative/overflow results; wall-clock adjustment cannot change it.
- Every listed object reference is selected; a path that does not match the reviewed five-part layout is rejected before GET without an object checkpoint and blocks its page-marker advance.
- One invalid NDJSON line rejects its containing collection unit; partial facts are not published.
- Compressed/decompressed byte caps are enforced while streaming; `Content-Length` is only an early-rejection hint.
- The real endpoint or a personal identity accidentally present in a fixture, doc, log, error, or tracked config is a release-blocking failure.

## Requirements

### Functional requirements

- **FR-001**: Both in-scope products MUST define their own allowlisted action and performance event names, fields, sampling, formulas, and cardinality; shared telemetry MUST NOT gain product semantics. AIDash MUST implement exactly `contracts/aidash-events.md`.
- **FR-002**: Producers MUST fail closed for missing/unsafe configuration or consent, isolate Blob state and network work, reject an entire unsafe event before persistence/network, freeze exact retry bytes/path/destination, classify receipt exactly, and retain pending work and historical identity on disable or rollback. AIDash consent MUST use the default-off local preference lifecycle in D-03; first opt-in MAY create its preference/UUID before producer configuration validates, but invalid configuration MUST create no telemetry service/store/uploader/timer/network work. AIDash MUST persist a generation-bound Reset target, reconcile the retained catalog while disabled before admission/flush, clear only the proven matching generation, and keep failures or ambiguous/stale outcomes pending and retryable.
- **FR-003**: VitalStride MUST retain its product-local TelemetryKit and Aptabase behavior and add Blob only through the separately owned VitalStride adapter slice; no AIDash task may edit that repository.
- **FR-004**: AIDash MUST add the exact approved LokiKit dependency only to consented GUI app composition, manually read the two expanded host keys, use the direct timer-free initializer with `heartbeatVersion: nil`, expose the cross-platform Settings consent/Reset surface, keep a newly opened retained catalog disabled until Reset reconciliation proves its current epoch, emit the exact two AIDash events only for an eligible lifecycle, and remain a no-op in CLI/headless/test-host production composition.
- **FR-005**: `aidata` MUST add a single-mode `product_blob` source using only the `aad-owner-local` contract, paginate and read the reviewed gzip NDJSON Blob format within the exact timeout/page/object/byte limits in `contracts/reader-auth.md`, preserve stable object/event provenance through an honest `fact_product_event`, expose a bounded read-only L4 query, and activate the source atomically in registries and scheduled operations only after adapter/schema/query/runner readiness without adding L5 formulas or cards.
- **FR-006**: Final acceptance MUST correlate a bounded two-product canary set through producer, Blob, L1, L3, and L4, including rerun/no-duplicate and unsafe-event rejection evidence.
- **FR-007**: All writer and reader permissions, dependency identities, release inputs, temporary CI injection, evidence, and rollback MUST remain least-privilege and auditable. No agent may create/read/copy a credential or real endpoint, and no tracked artifact may contain personal identity metadata.

### Configuration and authorization requirements

- Tracked configuration declares only `PRODUCT_BLOB_CONTAINER_URL = ""`; absence means disabled.
- A real query-free HTTPS container URL may appear only in ignored `aidata/config_local.py`.
- No tracked or ignored config key exists for token, SAS, account key, tenant, client secret, username, object ID, or alternate auth mode.
- `DefaultAzureCredential` is configured so Azure CLI is its only enabled leg. Interactive login and every non-CLI credential leg are disabled; failure never falls back to another mechanism.
- The requested scope is the Azure Storage data-plane audience only. Adapter operations are limited to container list and object read.
- Reader collection uses a 30-second request timeout and 240-second monotonic run budget, with at most 100 list results per page, 10 pages, 1,000 object references/GETs, 8,388,608 compressed bytes per object, and 67,108,864 decompressed bytes per object.

### Non-goals

- Azure resource, role, stored-policy, secret, or local sign-in/session changes.
- A broker, OAuth service/workload principal, SAS reader, dual-mode auth, or `local-read` policy activation.
- AIDash fixed-install entitlement changes; ADR-003 remains authoritative.
- Product metric formulas, dashboards, digests, or any L5 consumer.
- VoxPocket/T3 or VitalStride source changes.
- Treating `REL-001` as a planning blocker. It gates AIDash's final dependency pin and live proof only.

### Key entities

- **Product Event**: Product-owned action or performance record with name, ISO timestamp, and closed properties.
- **Telemetry Preferences**: Local default-off consent, last-proven install UUID, and optional generation-bound pending Reset target; not a credential and never a source of device/hardware identity.
- **Frozen Blob Batch**: Immutable gzip NDJSON bytes plus digest, destination, object path, and credential-free sidecar.
- **Blob Object Cursor**: Stable object path/ETag fingerprint and completed-unit state used for idempotent collection.
- **Product Event Fact**: One accepted event keyed by deterministic object-path plus line ordinal, retaining sanitized object provenance.
- **Reader Authorization Contract**: Fixed Azure CLI-only `DefaultAzureCredential` behavior with read/list operations and no config-supplied credential.
- **Canary Correlation**: Sanitized relationship across product/build, object fingerprint, source event key, L1 checkpoint, L3 fact, and L4 row.

## Success criteria

- **SC-001**: Hook/CI-owned hermetic producer evidence observes the exact two AIDash events at most once in an eligible lifecycle, exact trigger/properties/timing, default-off/first-opt-in/disable/re-enable behavior, zero SDK heartbeat events, and zero telemetry construction in every disabled production mode. SDK-backed hostless evidence proves retained-store Reset across restart plus reset failure/ambiguous confirmation and successful retry, with admission/flush closed until the target epoch is proven current.
- **SC-002**: Hook/CI-owned hermetic reader evidence covers every request/run/page/object/byte boundary, malformed content, auth/network degradation, exact page/object checkpoint behavior, and idempotent rerun with zero credential material in records or errors.
- **SC-003**: Temporary-database merge and L4 tests return one stable row per synthetic event after repeated runs and perform no source mutation.
- **SC-004**: The final evidence bundle correlates both products and both event types across every required stage and proves the unsafe event is absent.
- **SC-005**: Repository scanning finds no real endpoint, personal identity metadata, token, SAS, account key, or secret in the planned/implemented change.
- **SC-006**: All owning layer gates, repository context audit, required CI, dependency identity proof, and independent exact-revision reviews pass.

## Dependencies and gates

- `SL-AID-PLAN` is closed only by repository-native analysis, a normal-commit RepoInfra hook receipt, accepted ADR-004 and ADR-005, and exact-revision AI Reviewer PASS.
- Every T001–T010 implementation task is additionally blocked until the constitution 1.14.0 amendment is published and merged in the required `constitution: authorize explicit-consent GUI telemetry` PR with its migration note.
- `REL-001` gates only the exact LokiKit resolution in `AID-XCODE` and live E2E identity; it does not block this planning package or `SL-DATA`.
- OA-003/OA-004 gate live producer/canary evidence, not secret-free implementation.
- E2E-05 begins only after `SL-AID-PRODUCER`, `SL-DATA`, and the separately owned VitalStride slice are merged at recorded immutable revisions.
