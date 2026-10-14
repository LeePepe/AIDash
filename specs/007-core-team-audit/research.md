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

**Decision**: Keep each implementation task layer-owned, but make Core
registration, App schema advertisement, and CLI help/consumer adaptation one
hard coordinated publication unit.

**Rationale**: Adding the enum case grows `CardType.allCases`, while the App's
current schema map covers only ten cases and its test requires exact
type/schema parity. The CLI generically consumes the shared result and Core
validation, but card-put help is a hard-coded incomplete type list. The
constitution requires a coordinated Core/App/CLI type release. UI and producer
adaptations remain downstream.

## Existing DesignKit behavior

**Decision**: Reuse Classification.teamAudit unchanged and create no DesignKit
task.

**Rationale**: Current main already carries the teamAudit light #E6294D and
dark #FF375F token plus golden, distinctness, and contrast tests. Token
creation is already satisfied current-main behavior, not successor work.

**Alternative rejected**: Carrying a historical downstream token task would
violate the required current-main re-baseline.

## Verification

**Decision**: Normal commit and push hooks own resolver-selected verification.
Freeze and independently review the complete uncommitted three-layer
candidate first; only the unchanged reviewed tree may then be committed and
pushed. Focused commands are diagnostic only after a hook emits a failure.

**Rationale**: The constitution assigns build/test gates to configured hooks
and requires independent prepublication review. Core SPM gates are selected by
the hooks, hostless App logic tests own the schema proof, and heavy App
platform builds remain CI-only. Manual duplication would not be authoritative.
