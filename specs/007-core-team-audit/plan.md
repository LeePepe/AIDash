# Implementation Plan: Core Team Audit Contract

**Branch**: `007-core-team-audit` | **Date**: 2026-10-14 | **Spec**: `specs/007-core-team-audit/spec.md`

**Input**: Fresh successor specification derived from immutable current `main`
`bdf1435fe7d3d9c4da43ed4297cbc24482447b46`.

## Summary

Add the missing AIDashCore `teamAudit` card contract as one deep module: a
public Codable payload with eight locked section variants, a complete local
reference catalog, exact artifact/full-report/externalization bindings, and a
Validation-role protocol witness that reuses the existing URL policy and
schema-error flow. Register the eleventh card type and preserve authored size.
Prove the whole contract through focused Core tests, including the still-open
artifact `caseID` catalog rule and the full-report/externalization one-field
negative matrix. No App, UI, CLI, data, storage, or producer behavior belongs
to this slice.

## Technical Context

**Language/Version**: Swift 6 in strict-concurrency mode

**Primary Dependencies**: Foundation and existing AIDashCore interfaces only;
no new package or third-party dependency

**Storage**: N/A; immutable Codable values only

**Testing**: Swift Package Manager, XCTest/Swift Testing, public-API test target

**Target Platform**: The platforms already declared by AIDashCore

**Project Type**: Existing Swift library package

**Performance Goals**: Deterministic validation and exact received-payload
acceptance through 262,144 UTF-8 bytes

**Constraints**: One decode on the production validation path; Models cannot
depend on Validation; URL policy and schema validator stay unchanged; neutral
fixtures; package-only verification uses `swift build` and `swift test`, never
`xcodebuild`

**Scale/Scope**: One card type, eight section variants, twelve explicitly
allowed implementation/test paths, and no non-Core layer changes

## Constitution Check

### Pre-design gate

| Principle / bar | Result | Evidence |
|---|---|---|
| Agent-authored, user-read | PASS | The contract carries immutable audit output; it grants no write, dispatch, or remediation authority. |
| CLI/App authority boundary | PASS | This slice adds no persistence or event behavior. |
| Typed schema | PASS | One locked public payload replaces stringly typed section, reference, report, and externalization semantics. |
| Orthogonal card dimensions | PASS | `teamAudit` is a card type; authored `CardSize` is preserved. |
| Deep-module boundary | PASS | Callers learn `CardType.teamAudit` and `TeamAuditPayload`; structural resolution and URL orchestration remain hidden. |
| Intra-layer direction | PASS | Types own data and structural invariants; a Validation-role extension supplies the protocol witness and calls `URLPolicy`. |
| Scope discipline | PASS | One AIDashCore task has an exact twelve-path allowlist and explicit forbidden paths. |
| Error handling | PASS | Decode and invariant failures use the existing structured schema error; unknown locked values are never coerced. |
| Public identity | PASS | Fixtures use neutral example identities and hosts. |
| Verification | PASS | Package-only diff uses SPM build/test plus repository routing checks; no Xcode invocation. |

### Post-design re-check

PASS. The data model, contracts, acceptance matrix, and single task preserve the
same boundaries. No new storage, dependency, network client, policy, or
cross-layer coupling is introduced. The App's schema advertisement is an
explicit downstream dependency rather than hidden scope in this Core slice.

## Project Structure

### Documentation (this feature)

```text
specs/007-core-team-audit/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
├── checklists/
│   └── requirements.md
└── contracts/
    ├── core-team-audit.md
    └── core-acceptance-matrix.md
```

### Source Code (repository root)

```text
Packages/AIDashCore/
├── Sources/AIDashCore/
│   ├── Models/
│   │   ├── CardType.swift
│   │   ├── EffectiveCardSize.swift
│   │   └── Payloads/TeamAuditPayload.swift          # new
│   └── Validation/TeamAuditPayloadValidation.swift # new
└── Tests/
    ├── AIDashCoreTests/
    │   ├── TeamAuditPayloadRoundTripTests.swift    # new
    │   ├── TeamAuditPayloadInvariantTests.swift    # new
    │   ├── TeamAuditPayloadValidationTests.swift   # new
    │   ├── CardTypeDecodeTests.swift
    │   ├── EnumRoundtripTests.swift
    │   ├── EffectiveCardSizeTests.swift
    │   └── SchemaValidatorTests.swift
    └── AIDashCorePublicAPITests/PublicInitTests.swift
```

**Structure Decision**: Keep one AIDashCore module boundary. The payload file
owns public value types and structural/reference invariants. The Validation
file owns the `CardPayloadProtocol` witness and central URL-policy calls. Three
focused new test files prevent the broad shared payload suite from becoming an
unreviewable catch-all.

## Module and Seam Design

### `TeamAuditPayload`

**Public interface**: One Codable/Equatable/Sendable payload with immutable
envelope provenance, a locked `TeamAuditSection`, exactly one populated section
body, and a `SnapshotReferenceCatalog`. All valid values are constructible from
the external public-API test target.

**Hidden implementation**: Section exclusivity; identity uniqueness;
baseline/incremental reconciliation; typed-axis decoding; reference resolution;
SHA, count, sidecar, report, artifact, and externalization invariants. Internal
helpers may be split inside the same allowed payload file but are not new
caller concepts.

**Validation seam**: `TeamAuditPayloadValidation.swift` supplies
`validateInvariants()`. It first invokes the Types-owned structural validator,
then checks only actionable mandatory/full-report URLs using unchanged
`URLPolicy`. Optional unsafe artifact/grill strings remain exact untrusted data.

**Production path**: `CardType.teamAudit` decodes once via the existing
`CardType.validate(_:)` flow. `SchemaValidator.validateCardPut` continues to
apply its existing received-data limit and structured-error mapping unchanged.

## Exact Change Boundary

### Allowed paths

1. `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`
2. `Packages/AIDashCore/Sources/AIDashCore/Validation/TeamAuditPayloadValidation.swift`
3. `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`
4. `Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift`
5. `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadRoundTripTests.swift`
6. `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`
7. `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadValidationTests.swift`
8. `Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift`
9. `Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift`
10. `Packages/AIDashCore/Tests/AIDashCoreTests/EffectiveCardSizeTests.swift`
11. `Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorTests.swift`
12. `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift`

### Forbidden paths

- `Packages/AIDashCore/Sources/AIDashCore/Validation/SchemaValidator.swift`
- `Packages/AIDashCore/Sources/AIDashCore/Validation/URLPolicy.swift`
- `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/CardPayloadProtocol.swift`
- `Packages/AIDashCore/Package.swift`
- `Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift`
- Any other AIDashCore source or test file
- All `Apps/`, `CLI/`, `aidata/`, `Packages/AIDashUI/`, and
  `Packages/DesignKit/` paths
- Constitution, repository routing, and unrelated specification files

## Dependency and Delivery Graph

```text
exact 007 planning revision + AI Reviewer spec/plan PASS
                         |
                         v
                  T001 AIDashCore
                    /      |      \
                   v       v       v
       App schema advertisement   UI rendering   producer/data work
          (separate owner)      (separate owner) (separate owner)
```

T001 is the only implementation task in this successor. Adding
`CardType.teamAudit` expands `CardType.allCases`; therefore integrated delivery
must schedule a separate AIDashApp-owned schema-catalog adaptation before the
new type is advertised end to end. That dependency is not permission to modify
App code in T001.

## Verification Strategy

From `Packages/AIDashCore`:

```bash
swift build
swift test
```

Before those commands, confirm every implementation diff path is beneath
`Packages/` and inside the twelve-path allowlist. Do not invoke `xcodebuild`.
Also prove no Models source references `URLPolicy` or a Validation symbol, and
run the repository's resolver-selected routing/context checks required by the
normal hook. Planning-only validation uses Spec Kit prerequisites,
`scripts/hooks/check-tasks-fresh`, and `scripts/context/audit`; it does not run
product build/tests.

## Complexity Tracking

No constitutional violation or complexity exception is required.
