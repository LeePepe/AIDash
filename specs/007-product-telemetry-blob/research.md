# Research: Product Telemetry Blob Pipeline

## Authority reviewed

- Accepted MY-1816 planning v6, SHA-256 `97dc0822f4ade9f6e70a5c070e9860c6eeb57076e0744f1cdd7744750e8c55f2`.
- AIDash constitution 1.13.0, repository context routers, `aidata/adapters/CONTEXT.md`, ADR-003, and the existing manual-import contract.
- Owner decision `aad-owner-local`, effective 2026-10-15. The external authority record carries the actual operator/resource metadata; this public repository intentionally does not.

## Decision D-01: keep product semantics outside shared telemetry

**Decision**: AIDash owns its action/performance names, allowed fields, sampling, and formulas. LokiKit supplies generic transport, timing, validation, persistence, and diagnostics only.

**Rationale**: A shared product taxonomy would couple unrelated applications and contradict the accepted central plan. Product-local semantics also let hostless tests prove the exact two AIDash canary kinds without changing shared code.

**Alternatives rejected**:

- Put AIDash and VitalStride event enums in shared telemetry: shared transport must not own product vocabulary.
- Reuse CloudKit `UserEvent`: telemetry delivery, consent, retention, and Blob durability are different contracts.
- Add an SDK heartbeat: AIDash is explicitly timer-free and passes `heartbeatVersion: nil`.

## Decision D-02: retain the reviewed immutable Blob contract

**Decision**: Use the exact writer and reader wire/provenance contract in `contracts/blob-wire.md`. No repository-local simplification may weaken pre-store validation, immutable retry, queue retention, or privacy rejection.

**Rationale**: The cross-repository E2E gate can correlate an event only if producer object layout and reader provenance agree. Frozen bytes/path/destination prevent ambiguous retries from mutating an already attempted request.

**Alternatives rejected**:

- Treat `flush()` as receipt: it proves only local control flow.
- Drop on any 403/409: only one exact ambiguous-retry response proves immutable prior creation.
- Publish valid lines from a partially malformed object: state and analytical provenance would no longer identify a complete accepted unit.

## Decision OA-002: Azure CLI-only DefaultAzureCredential reader

**Decision**: `PRODUCT_BLOB_CONTAINER_URL` is the only reader config selector. The reader creates `DefaultAzureCredential` with every leg except Azure CLI disabled, requests the Azure Storage data-plane scope, and uses the resulting bearer token only for list/read requests to that validated container. No interactive login is initiated. Missing endpoint, missing/unavailable Azure CLI identity, token failure, or network failure degrades to zero/no-op with no state advance.

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

The collection unit is one complete Blob object after a complete pagination/list response identifies it. The adapter validates path, downloads bytes, verifies gzip, parses every NDJSON line, applies redaction, and prepares deterministic source keys before publishing completion state. A failed unit emits no checkpoint for that object; a failed page does not claim unseen continuation items.

Deterministic event key:

```text
sha256(canonical object path + "\n" + zero-based NDJSON line ordinal)
```

ETag/content fingerprints are provenance, not event identity. No raw SAS, bearer token, real endpoint, or personal identity enters raw records, normalized rows, errors, logs, or facts.

## Layering result

- `XcodeWorkspace`: dependency, empty build settings, plist expansion plumbing, and Fastlane path-only xcconfig consumption/cleanup.
- `RepoInfra`: TestFlight protected-secret injection/sentinel gate and aidata dependency installation in CI.
- `AIDashApp`: GUI lifecycle, consent, direct construction, action/PLT emission, rollback retention, and hostless-test gate declaration.
- `AidataFoundation`: fixed configuration schema, exact Python dependency, source registration, and dependency-manifest routing.
- `AidataL1L2`: list/read adapter, redacted append-only raw and source-clean rows.
- `AidataL3`: honest `fact_product_event` grain.
- `AidataL4`: exploratory read-only query.
- `AidataOps`: ordered scheduled-source registration and degrade behavior.
- No L5 change.

## Unresolved implementation gates

- **REL-001**: resolve the approved immutable LokiKit release/revision before AID-XCODE claims an exact dependency.
- **Python exact pin**: DATA-FOUND selects and reviews one compatible `azure-identity` version and a fully exact transitive lock; this does not reopen OA-002.
- OA-003/OA-004 remain external gates for live consent, protected injection, and canary authorization. They do not block hermetic implementation.
