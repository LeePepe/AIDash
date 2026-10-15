# Research: Product Telemetry Blob Pipeline

## Authority reviewed

- Accepted MY-1816 planning v6, SHA-256 `97dc0822f4ade9f6e70a5c070e9860c6eeb57076e0744f1cdd7744750e8c55f2`.
- AIDash constitution 1.14.0 amendment, repository context routers, `aidata/adapters/CONTEXT.md`, ADR-003, and the existing manual-import contract.
- Owner decision `aad-owner-local`, effective 2026-10-15. The external authority record carries the actual operator/resource metadata; this public repository intentionally does not.
- Lead decision effective 2026-10-15 on the Owner's behalf: authorize constitution 1.14.0, default-off Settings consent, first-opt-in random install UUID, Reset, GUI-only composition, and Planner-owned minimal AIDash event vocabulary.

## Decision D-01: keep product semantics outside shared telemetry

**Decision**: AIDash owns its action/performance names, allowed fields, sampling, and formulas. LokiKit supplies generic transport, timing, validation, persistence, and diagnostics only.

**Rationale**: A shared product taxonomy would couple unrelated applications and contradict the accepted central plan. Product-local semantics also let hostless tests prove the exact two AIDash canary kinds without changing shared code.

**Alternatives rejected**:

- Put AIDash and VitalStride event enums in shared telemetry: shared transport must not own product vocabulary.
- Reuse CloudKit `UserEvent`: telemetry delivery, consent, retention, and Blob durability are different contracts.
- Add an SDK heartbeat: AIDash is explicitly timer-free and passes `heartbeatVersion: nil`.

## Decision D-03: explicit consent, random install identity, and minimal AIDash events

**Decision**: The GUI Settings toggle **Send usage data** is the sole consent
authority. It defaults off in app-scoped `UserDefaults`. First opt-in creates a
random persisted UUID; later launches reuse it. Reset is disabled/no-op before
an ID exists; later it rotates only future identity. Turning consent off first
persists false, closes admission, disables/cancels delivery, and awaits
quiescence while retaining ambiguous/pending work and identity history. No
queued work uploads while off. Re-enable is fresh consent and resumes eligible
retained work. CLI, headless/XPC, and test-host production composition never
constructs the service.

AIDash defines exactly the two events in `contracts/aidash-events.md`:
`aidash.action` with closed `action_name=briefing_viewed`, and
`aidash.performance.ready_scene` with a monotonic integer `duration_ms` from
entry to the GUI-production app-init branch—before consent/configuration
reads—to first interactive `.ready(container)` appearance. The captured start
is discarded when the lifecycle is ineligible. Both events are unsampled and at
most once in an eligible GUI lifecycle.

**Rationale**: Default-off, product-owned consent prevents accidental telemetry
construction; a random opt-in identity avoids hardware/account-derived identity.
The single first-ready callback makes action and performance evidence
deterministic without expanding shared telemetry vocabulary.

**Alternatives rejected**:

- Reuse `AIDashCore.DeviceIdentifier`: it can expose device/hardware identity
  and exists independently of telemetry consent.
- Enable by endpoint presence: producer configuration is not consent.
- Create an ID at install/launch: identity must not precede first opt-in.
- Delete pending state on disable or Reset: this contradicts the SDK retention
  contract and would rewrite or orphan frozen immutable batches.
- Emit after a mid-lifecycle opt-in: a retrospective ready event lacks the
  required launch-to-ready boundary.

## Decision D-02: retain the reviewed immutable Blob contract

**Decision**: Use the exact writer and reader wire/provenance contract in `contracts/blob-wire.md`. No repository-local simplification may weaken pre-store validation, immutable retry, queue retention, or privacy rejection.

**Rationale**: The cross-repository E2E gate can correlate an event only if producer object layout and reader provenance agree. Frozen bytes/path/destination prevent ambiguous retries from mutating an already attempted request.

**Alternatives rejected**:

- Treat `flush()` as receipt: it proves only local control flow.
- Drop on any 403/409: only one exact ambiguous-retry response proves immutable prior creation.
- Publish valid lines from a partially malformed object: state and analytical provenance would no longer identify a complete accepted unit.

## Decision OA-002: Azure CLI-only DefaultAzureCredential reader

**Decision**: `PRODUCT_BLOB_CONTAINER_URL` is the only reader config selector. The reader creates `DefaultAzureCredential` with every leg except Azure CLI disabled, requests the Azure Storage data-plane scope, and uses the resulting bearer token only for list/read requests to that validated container. No interactive login is initiated. Missing endpoint/identity or initial-token failure before listing degrades to zero/no-op with no state advance. Later auth/network failure leaves its incomplete object/page unadvanced while preserving records and object checkpoints completed earlier in the run.

**Rationale**: This persists the Owner-selected `aad-owner-local` identity while keeping secrets and personal metadata out of the public repository. It makes one authentication mechanism mechanically testable and prevents accidental SAS or ambient-credential fallback.

**Dependency consequence**: `azure-identity` becomes a Python runtime dependency for `aidata`. DATA-FOUND must add one exact audited pin and route its manifest to AidataFoundation. RepoInfra must install that lock in aidata CI. A version range or unreviewed transitive change is not acceptable. This version resolution is implementation work, not a new auth-mode decision.

**Alternatives rejected**:

- Dedicated service/workload principal: superseded by the Owner decision for this version.
- Read/list SAS or the existing `local-read` policy: explicitly inactive.
- Raw `az account get-access-token` subprocess parsing: it is not the authorized `DefaultAzureCredential` path and increases output-leak risk.
- Default multi-leg credential chain: it silently changes principal/mechanism when Azure CLI is unavailable.
- Azure Storage SDK: stdlib HTTP is sufficient for bounded list/read and avoids another dependency. Reconsider only through a new ADR.

## GUI-only dependency placement

LokiKit is wired only into `AIDashApp` and `AIDashAppLogicTests` through `project.yml` and app-local composition. It does not enter AIDashCore, AIDashUI, CLI, headless XPC composition, or host-based local tests. The factory manually reads the two expanded plist values and calls the direct initializer rather than a bundle convenience initializer.

The dependency costs and fixed-install caveat are recorded in ADR-004. `REL-001` remains a final version-resolution gate because the accepted `v0.2.0` tag was not proven at planning time.

## Reader unit and checkpoint boundary

The collection unit is one complete Blob object after a complete pagination/list response identifies it. Every listed reference is selected: the adapter validates path before GET, and an invalid path is an uncheckpointed object failure that blocks its page marker. For a valid path it downloads bytes, verifies gzip, parses every NDJSON line, applies redaction, and prepares deterministic source keys before publishing completion state. A failed unit emits no checkpoint for that object; a failed page does not claim unseen continuation items.

Each list/read request times out after 30 seconds and one `collect()` stops after
a 240-second monotonic budget. A run is also bounded to 100 results per page,
10 pages, 1,000 references/GETs, 8,388,608 compressed bytes per object, and
67,108,864 decompressed bytes per object. Byte limits are streaming-enforced.
A page marker advances only after the full page and all selected objects are
complete/already complete. Bound exhaustion after a complete page persists its
next marker; exhaustion/failure within a page does not. Completed object
checkpoints remain reusable.

Configuration/credential/initial-token failure before the first list request
returns zero with no state change. A later auth/network failure leaves the
incomplete object/page unadvanced but preserves records and object checkpoints
completed earlier in that run and may return their accepted count.

Deterministic event key:

```text
sha256(canonical object path + "\n" + zero-based NDJSON line ordinal)
```

ETag/content fingerprints are provenance, not event identity. No raw SAS, bearer token, real endpoint, or personal identity enters raw records, normalized rows, errors, logs, or facts.

## Layering result

- `XcodeWorkspace`: dependency, empty build settings, plist expansion plumbing, and Fastlane path-only xcconfig consumption/cleanup.
- `RepoInfra`: TestFlight protected-secret injection/sentinel gate and aidata dependency installation in CI.
- `AIDashApp`: GUI lifecycle, consent, direct construction, action/PLT emission, rollback retention, and hostless-test gate declaration.
- `AidataFoundation`: fixed configuration schema, exact Python dependency,
  canonical scheduled-source declaration, later atomic source activation, and
  dependency-manifest routing.
- `AidataL1L2`: list/read adapter, redacted append-only raw and source-clean rows.
- `AidataL3`: honest `fact_product_event` grain.
- `AidataL4`: exploratory read-only query.
- `AidataOps`: make the runner consume the canonical current-effective
  `SCHEDULED_SOURCES` declaration and preserve degrade behavior without source
  activation.
- No L5 change.

## Unresolved implementation gates

- **REL-001**: resolve the approved immutable LokiKit release/revision before AID-XCODE claims an exact dependency.
- **Constitution publication**: merge the required
  `constitution: authorize explicit-consent GUI telemetry` amendment with its
  migration note before AIDash implementation begins.
- **Python exact pin**: DATA-FOUND selects and reviews one compatible `azure-identity` version and a fully exact transitive lock; this does not reopen OA-002.
- OA-003/OA-004 remain external gates for live consent, protected injection, and canary authorization. They do not block hermetic implementation.
