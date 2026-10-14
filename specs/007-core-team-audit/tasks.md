# Tasks: Core Team Audit Contract

**Input**: Design documents from `specs/007-core-team-audit/`

**Prerequisites**: Exact committed `007` planning revision and AI Reviewer
spec/plan PASS. Team Lead must approve that revision as the immutable
implementation base, or approve a descendant with byte-identical planning
artifact blobs.

**Organization**: The successor is one independently verifiable AIDashCore
vertical slice. No setup task or cross-layer task is needed.

## Phase 1: User Story 1 — Accept only trustworthy Core audit payloads (P1)

**Goal**: Add the complete Core-owned `teamAudit` contract and reject every
ambiguous, dangling, substituted, oversized, or unsafe mandatory payload
through existing validation surfaces.

**Independent test**: Construct all eight variants from the external public API,
round-trip and validate each, run every row in
`contracts/core-acceptance-matrix.md`, and leave all existing Core tests green.

- [ ] **T001 [US1]** Implement and prove the AIDashCore `teamAudit` payload contract.

  **Owning layer / context**: **AIDashCore** — read the root context, the
  Packages context, and the AIDashCore context and technical context files.

  **Files in scope** (the implementation PR may modify exactly these paths):
  - `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`
  - `Packages/AIDashCore/Sources/AIDashCore/Validation/TeamAuditPayloadValidation.swift`
  - `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`
  - `Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift`
  - `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadRoundTripTests.swift`
  - `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`
  - `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadValidationTests.swift`
  - `Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift`
  - `Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift`
  - `Packages/AIDashCore/Tests/AIDashCoreTests/EffectiveCardSizeTests.swift`
  - `Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorTests.swift`
  - `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift`

  **Files NOT to touch** (touching is a scope failure):
  - `Packages/AIDashCore/Sources/AIDashCore/Validation/SchemaValidator.swift`
  - `Packages/AIDashCore/Sources/AIDashCore/Validation/URLPolicy.swift`
  - `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/CardPayloadProtocol.swift`
  - `Packages/AIDashCore/Package.swift`
  - `Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift`
  - Any other AIDashCore path
  - All Apps, CLI, aidata, AIDashUI, and DesignKit paths
  - `.specify/memory/constitution.md`, routing/context files, and unrelated specs

  **Interface / contract**:
  - Implement `contracts/core-team-audit.md` and every row of
    `contracts/core-acceptance-matrix.md`.
  - Models own public Codable values and structural/reference invariants.
  - Validation owns the protocol witness and is the only new caller of the
    unchanged central `URLPolicy`.
  - `CardType.validate`, `SchemaValidator.validateCardPut`, received byte limit,
    and public protocol signatures remain unchanged.

  **Functional acceptance**:
  - `US1/AC1`–`US1/AC9` and `FR-001`–`FR-011` all map to passing named matrix rows.
  - The artifact `caseID` suite distinguishes omission from present blank and
    proves exact-once catalog resolution through direct and production paths.
  - Overview and artifacts-section full reports reject kind, ID, hash, URL,
    sidecar ID, and sidecar hash substitutions independently, plus missing and
    duplicate matches.
  - Externalization proves all eight optional kinds, positive/zero/negative
    byte counts, fixed reason, unknown/mandatory-shaped rejection, envelope
    sidecar equality, and exact embedded-report equality.
  - Otherwise-valid received JSON at exactly 262,144 bytes is accepted and a
    mandatory value at exactly 262,145 bytes is rejected.
  - Existing ten card types, schema errors, URL behavior, and tests remain
    accepted; only the intended enum-count tripwire changes to eleven.
  - Complete valid payloads are constructible without `@testable import`, and
    all fixtures use neutral public identities.

  **Quality bars**: Constitution cross-cutting quality bars apply automatically.

  **Exact verification**:
  - Confirm the diff contains only the twelve allowed package paths.
  - From the AIDashCore package directory, run `swift build` and `swift test`.
  - Do not invoke `xcodebuild` for this package-only diff.
  - Confirm Models contains no `URLPolicy` or Validation-symbol reference.
  - Run normal resolver-selected hook/routing checks when committing; use a
    focused rerun only to diagnose an emitted failure.

  **Dependencies**: Hard — exact `007` planning PASS and approved immutable
  base. Downstream — T001 unblocks separately owned AIDashApp schema
  advertisement, AIDashUI rendering, and producer/data work; none is included
  in this task.

## Dependency graph

```text
AI Reviewer PASS on exact 007 revision
               |
               v
             T001
      _________|____________
     v         v            v
 App schema  UI slice   producer/data slices
 (separate)  (separate)    (separate)
```

## Acceptance coverage

| Specification | Task / proof |
|---|---|
| US1/AC1–AC2 | T001: TA-RT, TA-AXIS, TA-SECTION, TA-REF |
| US1/AC3–AC4 | T001: TA-CASE-001 through TA-CASE-005 |
| US1/AC5–AC6 | T001: TA-FULL-001 through TA-FULL-009 |
| US1/AC7 | T001: TA-EXT-001 through TA-EXT-010 |
| US1/AC8 | T001: TA-SIZE-001 through TA-SIZE-003 |
| US1/AC9 | T001: TA-REG-002, TA-URL, TA-COMPAT |
| FR-001–FR-011 | T001: complete matrix traceability table |
| SC-001–SC-006 | T001: round-trip, negative matrix, boundary, path, and dependency checks |

## Definition of done

- T001 changes only its twelve allowed paths.
- SPM build and test pass; no package-only Xcode build is run.
- Every acceptance-matrix row is covered by a focused automated proof.
- Exact implementation SHA matches local, pushed branch, and PR head before
  independent content review.
- App schema/UI/producer successors remain separate and are scheduled before
  end-to-end advertisement of the new card type.
- MY-1522's workspace, metadata, branch, plan, and candidates remain untouched.
