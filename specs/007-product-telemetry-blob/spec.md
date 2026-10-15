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

- AIDash has no product telemetry. GUI, headless XPC, CLI, and test-host modes must remain distinguishable.
- `AIDashCore`, `AIDashUI`, CLI behavior, CloudKit/UserEvent storage, and existing analytics/data sources remain unchanged by this feature.
- `aidata` is a recursively routed Python subsystem. Its external sources are read-only, raw data is append-only, and an unconfigured source degrades to zero records.
- No accepted behavior or test is removed, skipped, weakened, or reclassified.

### Locked decisions

- **D-01 — Product ownership**: action names, performance names, fields, allowlists, sampling, and formulas remain product-local. Shared telemetry owns only generic transport, timing, privacy validation, persistence, and delivery diagnostics.
- **D-02 — Blob wire/durability contract**: producers and the reader use the exact contract in `contracts/blob-wire.md`. Producer credentials remain the previously approved create-only CI inputs and are never read by planning or implementation agents.
- **OA-002 / `aad-owner-local` — Reader identity**: the only reader is the Owner's existing Azure AD identity, used locally through the Azure CLI-backed `DefaultAzureCredential` leg. It has read/list authority only. There is no SAS mode, secret field, stored-policy use, or authentication fallback. Missing endpoint configuration, missing Azure CLI sign-in, or token failure returns zero records before state advances. Tracked files use only symbolic identifiers; the real selector belongs only in ignored `aidata/config_local.py`.

## User scenarios and testing

### User Story 1 — Safe GUI telemetry producer (Priority: P1)

As the Owner, I can enable AIDash GUI telemetry and receive one product-local action signal and one ready-scene performance signal without changing headless, CLI, test-host, CloudKit, or UserEvent behavior.

**Independent test**: Hostless logic constructs the service only from valid, consented GUI configuration, emits exactly the two product event kinds once per GUI lifecycle, and proves every disabled mode returns before identity, store, timer, or network creation.

**Acceptance scenarios**:

1. Given empty, unexpanded, or unsafe producer configuration, when the factory is evaluated, then it returns a no-op before creating durable identity, storage, or network work.
2. Given valid configuration and consent in a GUI lifecycle, when the app becomes ready, then one product-local action event and one ready-scene performance event are accepted with only allowlisted properties.
3. Given headless XPC, CLI, test-host, or no-consent mode, when lifecycle seams run, then no telemetry service, timer, identity, store, or event is created.
4. Given producer disable or rollback, when active flush work exits, then pending files and historical identity epochs remain intact.

### User Story 2 — Read-only product-event analytics (Priority: P1)

As the Owner, I can collect authorized product Blob objects into `aidata`, preserve their provenance and event grain through L3, and query bounded product events from L4 without giving the reader write/delete authority or introducing an L5 consumer.

**Independent test**: A fake Azure transport paginates neutral Blob fixtures, supplies gzip NDJSON to the adapter, reruns collection and merge, and proves one stable L4 row per event with no duplicate and no partial checkpoint after a failed unit.

**Acceptance scenarios**:

1. Given an empty tracked endpoint selector or unavailable Owner-local Azure CLI identity, when `product_blob` collects, then it returns zero and neither contacts the endpoint nor advances state.
2. Given a signed-in authorized identity and paginated objects, when collection succeeds, then every complete object is parsed, redacted, appended, normalized, and checkpointed exactly once.
3. Given malformed gzip/NDJSON, interrupted pagination, or token/network failure, when a unit fails, then incomplete work does not advance its seen/watermark state and the wider pipeline continues.
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
- An object path that does not match the reviewed five-part layout is rejected without advancing state.
- One invalid NDJSON line rejects its containing collection unit; partial facts are not published.
- The real endpoint or a personal identity accidentally present in a fixture, doc, log, error, or tracked config is a release-blocking failure.

## Requirements

### Functional requirements

- **FR-001**: Both in-scope products MUST define their own allowlisted action and performance event names, fields, sampling, and formulas; shared telemetry MUST NOT gain product semantics.
- **FR-002**: Producers MUST fail closed for missing/unsafe configuration or consent, isolate Blob state and network work, reject an entire unsafe event before persistence/network, freeze exact retry bytes/path/destination, classify receipt exactly, and retain pending work and historical identity on disable or rollback.
- **FR-003**: VitalStride MUST retain its product-local TelemetryKit and Aptabase behavior and add Blob only through the separately owned VitalStride adapter slice; no AIDash task may edit that repository.
- **FR-004**: AIDash MUST add the exact approved LokiKit dependency only to GUI app composition, manually read the two expanded host keys, use the direct timer-free initializer with `heartbeatVersion: nil`, emit exactly one product action and one ready-scene performance event per GUI lifecycle, and remain a no-op in headless/test-host modes.
- **FR-005**: `aidata` MUST add a single-mode `product_blob` source using only the `aad-owner-local` contract, paginate and read the reviewed gzip NDJSON Blob format, preserve stable object/event provenance through an honest `fact_product_event`, expose a bounded read-only L4 query, and register the source in scheduled operations without adding L5 formulas or cards.
- **FR-006**: Final acceptance MUST correlate a bounded two-product canary set through producer, Blob, L1, L3, and L4, including rerun/no-duplicate and unsafe-event rejection evidence.
- **FR-007**: All writer and reader permissions, dependency identities, release inputs, temporary CI injection, evidence, and rollback MUST remain least-privilege and auditable. No agent may create/read/copy a credential or real endpoint, and no tracked artifact may contain personal identity metadata.

### Configuration and authorization requirements

- Tracked configuration declares only `PRODUCT_BLOB_CONTAINER_URL = ""`; absence means disabled.
- A real query-free HTTPS container URL may appear only in ignored `aidata/config_local.py`.
- No tracked or ignored config key exists for token, SAS, account key, tenant, client secret, username, object ID, or alternate auth mode.
- `DefaultAzureCredential` is configured so Azure CLI is its only enabled leg. Interactive login and every non-CLI credential leg are disabled; failure never falls back to another mechanism.
- The requested scope is the Azure Storage data-plane audience only. Adapter operations are limited to container list and object read.

### Non-goals

- Azure resource, role, stored-policy, secret, or local sign-in/session changes.
- A broker, OAuth service/workload principal, SAS reader, dual-mode auth, or `local-read` policy activation.
- AIDash fixed-install entitlement changes; ADR-003 remains authoritative.
- Product metric formulas, dashboards, digests, or any L5 consumer.
- VoxPocket/T3 or VitalStride source changes.
- Treating `REL-001` as a planning blocker. It gates AIDash's final dependency pin and live proof only.

### Key entities

- **Product Event**: Product-owned action or performance record with name, ISO timestamp, and closed properties.
- **Frozen Blob Batch**: Immutable gzip NDJSON bytes plus digest, destination, object path, and credential-free sidecar.
- **Blob Object Cursor**: Stable object path/ETag fingerprint and completed-unit state used for idempotent collection.
- **Product Event Fact**: One accepted event keyed by deterministic object-path plus line ordinal, retaining sanitized object provenance.
- **Reader Authorization Contract**: Fixed Azure CLI-only `DefaultAzureCredential` behavior with read/list operations and no config-supplied credential.
- **Canary Correlation**: Sanitized relationship across product/build, object fingerprint, source event key, L1 checkpoint, L3 fact, and L4 row.

## Success criteria

- **SC-001**: Hermetic producer tests observe exactly one allowlisted action and one performance event, zero SDK heartbeat events, and zero telemetry construction in every disabled mode.
- **SC-002**: Hermetic reader tests cover pagination, malformed content, auth/network degradation, no partial advance, and idempotent rerun with zero credential material in records or errors.
- **SC-003**: Temporary-database merge and L4 tests return one stable row per synthetic event after repeated runs and perform no source mutation.
- **SC-004**: The final evidence bundle correlates both products and both event types across every required stage and proves the unsafe event is absent.
- **SC-005**: Repository scanning finds no real endpoint, personal identity metadata, token, SAS, account key, or secret in the planned/implemented change.
- **SC-006**: All owning layer gates, repository context audit, required CI, dependency identity proof, and independent exact-revision reviews pass.

## Dependencies and gates

- `SL-AID-PLAN` is closed only by repository-native analysis, RepoInfra local gate, accepted ADR-004 and ADR-005, and exact-revision AI Reviewer PASS.
- `REL-001` gates only the exact LokiKit resolution in `AID-XCODE` and live E2E identity; it does not block this planning package or `SL-DATA`.
- OA-003/OA-004 gate live producer/canary evidence, not secret-free implementation.
- E2E-05 begins only after `SL-AID-PRODUCER`, `SL-DATA`, and the separately owned VitalStride slice are merged at recorded immutable revisions.
