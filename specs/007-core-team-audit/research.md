# Research: Core Team Audit Contract

## Baseline and authority

**Decision**: Treat current `main`
`bdf1435fe7d3d9c4da43ed4297cbc24482447b46` as the only product-behavior
baseline. Create a fresh `007` successor rather than amend `006`.

**Rationale**: Current Core has ten card types and no Team Audit type, payload,
catalog, report/externalization types, or tests. Historical revision
`9b25314544a1eec34f6f37e948cbbb50d0838fdb`, candidate `1348d2c…`, T005, and
its old allowlist predate the successor decision and are evidence only.

**Alternatives rejected**: Reopening historical T005 would inherit stale task,
path, and base authority. Reusing the preserved MY-1522 checkout or candidate
would violate the successor isolation decision.

## Residual assessment

**Decision**: Both historical FR-024 residuals still exist, but inside an
entirely absent Core contract:

1. an artifact's optional `caseID` must resolve exactly once through the case
   catalog when present; omission is valid, blank/dangling/duplicate is not;
2. full-report and externalization tests must mutate kind, ID, hash, URL,
   sidecar ID, sidecar hash, count, reason, allowed kind, and embedded report
   relationship independently.

**Rationale**: No current Team Audit implementation or focused test exists, so
neither residual has been satisfied by current repository authority.

**Alternative rejected**: Carrying only those two assertions as a patch would
pretend their prerequisite types and invariants already exist.

## Reused current behavior

**Decision**: Reuse without modification:

- `CardPayloadProtocol` and the one-decode `CardType.validate` interface;
- `SchemaValidator.validateCardPut` structured-error mapping;
- the 262,144-byte received-data gate;
- `URLPolicy`'s HTTPS-with-non-empty-host rule;
- AIDashUI's generic unknown/invalid-payload fallback.

**Rationale**: These are already accepted seams. Duplicating byte or URL policy
inside the new model would create divergent authorities.

## Owning layer and seam

**Decision**: AIDashCore owns the complete payload contract. Types own Codable
values and structural/reference validation; the Validation role supplies the
protocol witness and is the only new code allowed to call `URLPolicy`.

**Rationale**: This follows the repository direction `Types <- Services` and
keeps callers behind the existing small `CardPayloadProtocol` interface.

**Alternative rejected**: Calling `URLPolicy` from the Models payload would
reverse the intra-layer dependency. Changing `SchemaValidator` would broaden a
stable production seam unnecessarily.

## Test organization

**Decision**: Add focused round-trip, invariant, and Validation-role suites,
then update only the existing registration, enum, effective-size, schema, and
public-construction owner tests.

**Rationale**: The contract is large enough that one broad test file would hide
which invariant failed. Focused suites also make the two former residuals
explicit acceptance rows.

**Alternative rejected**: Editing the generic
`CardPayloadRoundTripTests.swift` repeats the historical allowlist without a
current-main ownership reason.

## Size boundary

**Decision**: Test exactly 262,144 and 262,145 received UTF-8 bytes using
otherwise-valid `teamAudit` JSON through `SchemaValidator.validateCardPut`.
The payload model does not reproduce the global byte limit.

**Rationale**: The existing production gate owns received bytes; semantic
re-encoding can change byte count and is not authoritative.

## Downstream compatibility

**Decision**: Keep T001 Core-only and record App schema advertisement as a hard
downstream integration dependency.

**Rationale**: Adding the enum case grows `CardType.allCases`, while the App's
current schema map covers only the ten baseline cases. App, UI, and producer
adaptations each belong to separate layers and must not be hidden in a Core
task.

## Verification

**Decision**: Because the future implementation diff is package-only, verify
from `Packages/AIDashCore` with `swift build` then `swift test`; never use
`xcodebuild`. Verify path allowlist and absence of Models-to-Validation
references separately.

**Rationale**: This is the repository's explicit package-only rule and gives
the smallest authoritative build/test surface.
