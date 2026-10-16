# Feature Specification: Product Telemetry Blob Pipeline

**Feature Directory**: `007-product-telemetry-blob`
**Created**: 2026-10-15
**Status**: Manual-batch planning gate
**Base**: `eb292dc041dab6c5722e270f0f138ecd35949509`

## Scope and authority

This package preserves the already merged GUI-only AIDash producer and plans
one later delivery slice: a human-authorized `aidata` command that lands one
successful Azure CLI download batch as one opaque immutable L1 completion
directory. `contracts/manual-batch-collector.md` is the sole reader authority.

It also preserves the post-merge T7 evidence milestone. Producer changes,
generic `collect`, source activation, Ops/scheduling, L2-L5 product paths,
Azure resource changes, credentials, and live TestFlight/Blob/query execution
are outside this repository-planning slice.

### Existing behavior and compatibility

- AIDash's explicit-consent GUI producer and its consent/identity lifecycle are
  merged. ADR-004, `contracts/aidash-events.md`, and the producer/lifecycle
  sections of `contracts/blob-wire.md` remain unchanged.
- `AIDashCore`, `AIDashUI`, Swift CLI behavior, CloudKit/UserEvent storage,
  generic aidata collection, existing analytics sources, runner, and cron
  remain unchanged by this reader slice.
- `aidata` is recursively routed; empty tracked reader configuration degrades
  to a hermetic no-op, and L1 raw storage is ignored/private.
- No accepted behavior or test is removed, skipped, weakened, or reclassified.

### Removed planned behavior

- Owner decision `no-reset-v1` supersedes the earlier planned install-ID Reset.
  Telemetry is not implemented at the fixed base, so this removes no production
  behavior or existing test. Version 1 must expose no Reset/rotation surface,
  shared-telemetry reset API, or private-catalog parsing. A future Reset requires
  its own SDK feature and product decision.
- The selected manual-batch decision supersedes the unshipped Python
  `DefaultAzureCredential`/LIST+GET, page/object cursor, per-file registration,
  custom cap, L2-L4, source activation, Ops, scheduler, and cross-run
  resume/deduplication plan. MB-020 removes no live-main behavior or test.

### Locked decisions

- **D-01 — Product ownership**: action names, performance names, fields, allowlists, sampling, and formulas remain product-local. Shared telemetry owns only generic transport, timing, privacy validation, persistence, and delivery diagnostics.
- **D-02 — Blob wire/durability contract**: producer behavior remains in
  `contracts/blob-wire.md`; the reader side points exclusively to
  `contracts/manual-batch-collector.md`. Producer credentials remain the
  previously approved create-only CI inputs and are never read by planning or
  implementation agents.
- **D-03 — Consent, identity, and AIDash events**: `contracts/aidash-events.md` is the normative AIDash event table. The GUI Settings toggle **Send usage data** is the sole consent source and reads/writes app `UserDefaults.standard`. Consent defaults off. The exact never-opted state has no `telemetry.identityEstablished` marker and no install ID; only that state may create one random UUID. First opt-in persists the UUID, then the monotonic non-identity marker, before consent becomes active. Later launches and consent cycles retain the marker and reuse that UUID for the app's lifetime. Disable stops admission/upload but retains pending state, the marker, and the ID; re-enable is fresh consent and resumes under the same ID. Any inconsistent or post-opt-in missing/malformed identity state fails closed without generating or rotating an ID. Version 1 has no install-ID Reset/rotation, shared reset API, or private-catalog parsing. CLI, headless/XPC, and test-host production composition never constructs the telemetry service.
- **OA-002 / `aad-owner-local` — Reader identity**: the only reader is the
  Owner's existing Azure AD identity, used locally by the installed Azure CLI
  through exact `download-batch --auth-mode login --overwrite false`. It has
  externally administered read/list authority only. The repository parses no
  token, stores no credential, and implements no alternate auth or fallback.
  Both real selectors belong only in ignored `aidata/config_local.py`.

## User scenarios and testing

### User Story 1 — Safe GUI telemetry producer (Priority: P1)

As the Owner, I can explicitly enable AIDash GUI telemetry and receive the two events in `contracts/aidash-events.md` without changing headless, CLI, test-host, CloudKit, or UserEvent behavior.

**Independent test**: Hook-owned hostless logic uses isolated preferences and fakes to prove default-off consent, one first-opt-in identity reused across relaunch and disable/re-enable, eligible once-per-lifecycle event emission, no Reset/rotation surface, and no service/store/timer/network construction in every disabled production mode.

**Acceptance scenarios**:

1. Given the exact never-opted state—consent off, no `telemetry.identityEstablished` marker, and no install ID—when any GUI lifecycle begins, then **Send usage data** is off and no install ID, telemetry service, store, timer, uploader, event, or network work is created.
2. Given the first explicit false-to-true opt-in from the never-opted state, when preferences persist it, then a random canonical UUID is created once, the monotonic non-identity marker is persisted, and only then consent becomes active. Both values are retained and reused on later launches; empty, unexpanded, or unsafe producer configuration still returns before service/store/timer/uploader/network construction.
3. Given valid configuration and consent already true at eligible GUI launch, when the first `.ready(container)` scene becomes interactive, then `aidash.action` with only `action_name=briefing_viewed` and `aidash.performance.ready_scene` with only finite nonnegative integer `duration_ms` are admitted at 100% sampling and at most once in that lifecycle.
4. Given consent becomes true only after the scene is already ready, readiness never occurs, or consent is revoked before readiness, then no retrospective action/performance event is emitted for that lifecycle.
5. Given headless XPC, CLI, or test-host production composition, when lifecycle seams run, then no telemetry service, store, uploader, timer, or event is constructed.
6. Given consent is turned off or producer rollback begins, when false is persisted, then admission closes and active delivery is disabled/cancelled before quiescence; no pending upload starts/continues, ambiguous in-flight work stays retained/unconfirmed, and the established marker plus UUID remain intact so a later opt-in resumes eligible retained work under that same UUID.
7. Given identity was established but the retained UUID is missing/malformed, or any marker/UUID/consent combination is inconsistent with the explicit state model, when launch or re-enable evaluates preferences, then it enters the established-invalid state, keeps consent inactive, constructs no telemetry service/store/uploader/timer/network work, and never generates a replacement UUID.
8. Given Settings or production composition in version 1, then no install-ID Reset/rotation action or API exists, no shared-telemetry reset feature is required, and AIDash never parses private telemetry storage to infer identity.

### User Story 2 — Manual opaque L1 batch landing (Priority: P1)

As the Owner, I can manually collect one authorized VoxPocket Blob prefix into
one immutable L1 completion directory without giving repository code a
credential, parser, scheduler, or downstream product pipeline.

**Independent test**: One executable fake `az` is selected by the real CLI and
adapter. It records the exact preflight/batch argv and environment and writes
neutral synthetic bytes into a real temporary filesystem. Assertions observe
only public CLI output and staging/completion filesystem outcomes.

**Acceptance scenarios**:

1. Given both tracked selectors are empty, when `product-blob` runs, then it
   returns the Constitution JSON `empty` success envelope and creates no Azure
   child, stage, or completion.
2. Given one valid private container URL/prefix and the existing signed-in
   read-only identity, when the exact Azure batch exits `0` with at least one
   object, then one byte-identical opaque file tree is fsynced and published by
   one atomic directory rename; stdout contains only the safe `completed`
   envelope.
3. Given invalid/partial config, failed preflight, nonzero batch, unsafe output,
   zero objects, or interruption before the atomic commit point, then no
   completion is published. Catchable failure uses the fixed neutral error;
   an abandoned private stage is never considered a result.
4. Given an earlier completion and any later invocation, then the earlier
   directory is never written, renamed, removed, scanned for identity, or used
   for deduplication. A later successful batch creates a distinct directory.

### User Story 3 — Batch/Blob-scoped T7 proof (Priority: P2)

As the Owner, after merge and separate live authorization, I can privately
associate the real TestFlight build and one actual Blob with one completion
batch and a query limited to that batch/Blob, without publishing identifiers or
claiming cross-run idempotency.

**Independent test**: An independent reviewer reconciles the exact merged
revision, private TestFlight/Blob association, byte-identical L1 file, and real
batch/Blob-filtered query result/count required by `contracts/e2e-evidence.md`.

**Acceptance scenarios**:

1. Private evidence relates the actual build and Blob name to one immutable
   completion batch; public evidence exposes neither value nor a local path.
2. The real query is explicitly filtered to that batch and Blob and proves no
   duplicate within that scope only.
3. Sanitized authorization evidence proves the producer remains create-only
   and the Owner's reader identity remains read/list-only without revealing a
   token, SAS, key, endpoint, or principal metadata.
4. Generic `collect`, templates, fixture traces, and test counts are labelled
   separately and cannot satisfy T7.

### Edge cases

- Redirects and non-server-trust authentication challenges are refused by producer transport.
- Only HTTP `201`, or an ambiguous immutable retry receiving the exact qualified overwrite rejection, may remove producer queue work.
- Changed destinations, corrupt sidecars, or source/body mismatches retain and block a producer batch.
- Consent disabled while work is pending retains the queue, monotonic established marker, and UUID but forbids upload; re-enable uses the same install ID and never rewrites a frozen batch's install-ID-bearing path. An invalid established state fails closed without replacement identity.
- Ready-scene duration uses a monotonic clock and rejects negative/overflow results; wall-clock adjustment cannot change it.
- Startup rejects symlink/non-directory product, staging, or completion
  terminals before Azure use; repeated same-user descriptor confinement is
  outside the trusted-local threat model.
- Azure exit `0` with no regular downloaded object is an `empty` no-op and is
  not ingestion evidence.
- A kill before the atomic directory rename leaves no completion; a kill after
  the rename occurs after the batch commit point, so the full directory is
  completion even if no success envelope reaches the caller.
- Symlinks/special files in Azure output reject publication. Gzip bytes are
  otherwise opaque and receive no parse, redaction, per-file cap, or raw ID.
- The real endpoint or a personal identity accidentally present in a fixture, doc, log, error, or tracked config is a release-blocking failure.

## Requirements

### Functional requirements

- **FR-001**: Both in-scope products MUST define their own allowlisted action and performance event names, fields, sampling, formulas, and cardinality; shared telemetry MUST NOT gain product semantics. AIDash MUST implement exactly `contracts/aidash-events.md`.
- **FR-002**: Producers MUST fail closed for missing/unsafe configuration or consent, isolate Blob state and network work, reject an entire unsafe event before persistence/network, freeze exact retry bytes/path/destination, classify receipt exactly, and retain pending work and historical identity on disable or rollback. AIDash consent MUST use the default-off local preference lifecycle in D-03. Only the exact never-opted state MAY generate a UUID; first opt-in MUST persist that UUID and a monotonic non-identity established marker before consent becomes active, even when producer configuration later proves invalid. Invalid configuration or any inconsistent/post-opt-in missing/malformed identity state MUST create no telemetry service/store/uploader/timer/network work. After first opt-in the marker and same install UUID MUST be retained and reused for the app's lifetime; no v1 path may replace, reset, rotate, or infer it from private storage.
- **FR-003**: VitalStride MUST retain its product-local TelemetryKit and Aptabase behavior and add Blob only through the separately owned VitalStride adapter slice; no AIDash task may edit that repository.
- **FR-004**: AIDash MUST add the exact approved LokiKit dependency only to consented GUI app composition, manually read the two expanded host keys, use the direct timer-free initializer with `heartbeatVersion: nil`, expose the cross-platform Settings consent surface without Reset/rotation, emit the exact two AIDash events only for an eligible lifecycle, and remain a no-op in CLI/headless/test-host production composition.
- **FR-005**: `aidata` MUST add only the unregistered manual command and opaque
  L1 adapter defined by MB-001–MB-020. One successful nonempty Azure batch
  produces one immutable completion directory; disabled/empty/failure and
  pre-commit interruption produce none.
- **FR-006**: Final T7 acceptance MUST privately associate the actual
  TestFlight build and one Blob with one completion batch and a real query
  explicitly filtered to that batch/Blob. It MUST prove only in-batch scoped
  count/nonduplication and MUST NOT claim cross-run incremental idempotency.
- **FR-007**: Writer and reader permissions, local selectors, output, evidence,
  and rollback MUST remain least-privilege and private. No agent may
  create/read/copy a credential, real endpoint/prefix, actual Blob name, or
  principal metadata into tracked/public artifacts.

### Configuration and authorization requirements

- Tracked configuration declares only `PRODUCT_BLOB_CONTAINER_URL = ""` and
  `PRODUCT_BLOB_PREFIX = ""`; both empty means disabled.
- One real query-free HTTPS container URL and one allow-listed VoxPocket prefix
  may appear only in ignored `aidata/config_local.py`.
- No tracked or ignored config key exists for token, SAS, account key, tenant, client secret, username, object ID, or alternate auth mode.
- The repository never initiates login or parses a token. The installed Azure
  CLI uses only `--auth-mode login`; failure never selects another mechanism.
- Repository code executes exactly one batch and performs no direct list/read,
  resource-management, write, overwrite, append, metadata, lease, or delete
  operation.
- Manual execution is externally bounded by MB-016; no repository scheduler or
  second supervisor is added.

### Non-goals

- Azure resource, role, stored-policy, secret, or local sign-in/session changes.
- A broker, OAuth service/workload principal, SAS reader, dual-mode auth, or `local-read` policy activation.
- AIDash fixed-install entitlement changes; ADR-003 remains authoritative.
- Product metric formulas, dashboards, digests, or any L5 consumer.
- Generic `collect`, source registries, L2 normalize, L3 merge, L4 query product
  code, L5, runner, cron, timer, scheduler, or automatic source execution.
- Per-Blob registry/raw ID, custom byte caps, pagination/checkpoint, resume,
  recovery, cross-run deduplication, or idempotency.
- VoxPocket producer/T3 or VitalStride source changes.
- Install-ID Reset/rotation, a shared-telemetry reset API, or private telemetry-storage parsing. Revisit Reset only as a separately authorized SDK feature.

### Key entities

- **Product Event**: Product-owned action or performance record with name, ISO timestamp, and closed properties.
- **Telemetry Preferences**: Local default-off consent, one lifetime-stable random install UUID created only from the exact never-opted state, and a monotonic non-identity `identityEstablished` marker that distinguishes never-opted from disabled/corrupt post-opt-in state; none is a credential or a source of device/hardware identity.
- **Frozen Blob Batch**: Immutable gzip NDJSON bytes plus digest, destination, object path, and credential-free sidecar.
- **Completion Batch**: One random non-identity directory name plus a nonempty,
  byte-identical opaque relative Blob file tree, absent before and immutable
  after one atomic publish.
- **Reader Authorization Contract**: Direct installed Azure CLI batch using the
  Owner's existing externally administered read-only identity, with no
  config-supplied credential or token parsing.
- **Manual Batch Evidence**: Private association across exact merged revision,
  actual build/Blob, one completion batch, and one batch/Blob-scoped query.

## Success criteria

- **SC-001**: Hook/CI-owned hermetic producer evidence observes the exact two AIDash events at most once in an eligible lifecycle, exact trigger/properties/timing, default-off/first-opt-in/disable/re-enable behavior with the monotonic established marker and same install UUID across relaunch and consent cycles, fail-closed inconsistent/corrupt post-opt-in states with zero replacement-ID generation or telemetry construction, zero Reset/rotation surface, zero SDK heartbeat events, and zero telemetry construction in every disabled production mode.
- **SC-002**: Hook/CI-owned hermetic reader evidence proves exact Azure
  preflight/batch argv and environment, fixed private output, disabled/empty/
  failure/interruption behavior, byte-identical completion, fsync plus one
  atomic directory publish, abandoned-stage ignore, and independent later
  completion.
- **SC-003**: Repository scanning and final diff prove no per-file registry,
  parser, cap, state/checkpoint, dependency, generic activation, Ops, scheduler,
  or L2-L5 product implementation was added.
- **SC-004**: The final private evidence bundle associates the actual
  TestFlight build and Blob with one completion batch and one batch/Blob-scoped
  query result/count without public identifiers.
- **SC-005**: Repository scanning finds no real endpoint, personal identity metadata, token, SAS, account key, or secret in the planned/implemented change.
- **SC-006**: All owning layer gates, repository context audit, required CI, dependency identity proof, and independent exact-revision reviews pass.

## Dependencies and gates

- Implementation is blocked until this exact RepoInfra planning revision passes
  independent review and is merged on a live-main descendant.
- T101 AidataFoundation precedes T102 AidataL1L2. No other implementation task
  is authorized by this package.
- Existing producer/dependency resolution is preserved and is not reopened by
  this reader plan.
- Separate explicit live-operation approval gates TestFlight, Azure,
  collection, and query evidence, not hermetic implementation.
- T7 begins only after the exact implementation head is merged and those
  external authorizations exist.
