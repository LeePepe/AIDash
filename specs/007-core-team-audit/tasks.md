# Tasks: Core Team Audit Contract

**Input**: specs/007-core-team-audit/

**Prerequisite**: Exact committed 007 revision with AI Reviewer spec/plan
PASS. Team Lead approves that revision as immutable implementation base, or an
explicit descendant with byte-identical reviewed planning artifacts.

**Organization**: Three layer-owned tasks form one coordinated product slice.
They may be implemented in dependency order but cannot be published, pushed,
or merged separately.

## Phase 1 — Core public contract

- [ ] **T001 [US1]** Implement and prove the AIDashCore teamAudit payload contract.

  **Owning layer / context**: AIDashCore. Read root, Packages, and
  AIDashCore context and technical-context files.

  **Files in scope**:
  - Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift
  - Packages/AIDashCore/Sources/AIDashCore/Validation/TeamAuditPayloadValidation.swift
  - Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift
  - Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift
  - Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadRoundTripTests.swift
  - Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift
  - Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadValidationTests.swift
  - Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift
  - Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift
  - Packages/AIDashCore/Tests/AIDashCoreTests/EffectiveCardSizeTests.swift
  - Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorTests.swift
  - Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift

  **Files not to touch**:
  - Packages/AIDashCore/Sources/AIDashCore/Validation/SchemaValidator.swift
  - Packages/AIDashCore/Sources/AIDashCore/Validation/URLPolicy.swift
  - Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/CardPayloadProtocol.swift
  - Packages/AIDashCore/Package.swift
  - Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift
  - Every other AIDashCore, App, CLI, UI, DesignKit, aidata, and spec path

  **Interface / contract**:
  - Implement contracts/core-team-audit.md and every Core-owned row of
    contracts/core-acceptance-matrix.md.
  - data-model.md is normative for every field, optional key, raw value,
    reconciliation equation, catalog relation, and public initializer.
  - Models owns Codable values and structural/reference validation.
  - Validation supplies the protocol witness and is the only new URLPolicy
    caller. CardType.validate, SchemaValidator.validateCardPut, their
    structured errors, and the received byte gate remain unchanged.

  **Functional acceptance**:
  - All eight variants encode only their selected body, compare exactly after
    decode, validate directly and through production, and are externally
    constructible.
  - Mode, evidence, axes, effectiveness, publication coverage, findings,
    ordered timelines, metrics, canonical lineage, five role-repeat variants,
    collisions, artifacts, GrillLinks, and catalog relations pass every named
    positive/equation/one-field-negative row.
  - Artifact caseID omission/exact-resolution/blank/dangling/duplicate paths
    and full-report/externalization kind/ID/hash/URL/sidecar/count/reason paths
    are complete.
  - small, medium, wide, and hero pass through both effective-size resolver
    overloads, including collapse-to-list.
  - Valid received JSON at 262,144 bytes passes and valid mandatory JSON at
    262,145 bytes fails. Existing ten types, errors, and URL behavior remain.

  **Verification**:
  - Freeze evidence shows exactly these twelve paths and no Models-to-
    Validation dependency.
  - Normal commit and push hooks own resolver-selected Core build/test and
    routing evidence. Do not manually duplicate suites; a focused command is
    diagnostic only after a hook emits a failure.

  **Dependencies**: Hard prerequisite is the exact reviewed planning base.
  Hard successors are T002 and T003. T001 alone is not publishable.

## Phase 2 — Coordinated consumers

- [ ] **T002 [US1]** Add the AIDashApp teamAudit schema-list contract.

  **Owning layer / context**: AIDashApp. Read root, Apps, and AIDashApp
  context and technical-context files.

  **Files in scope**:
  - Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift
  - Apps/AIDashApp/Tests/XPCHandlersContainerCardTests.swift

  **Files not to touch**:
  - Apps/AIDashApp/project.yml and every other Apps path
  - All Core, CLI, UI, DesignKit, aidata, and spec paths

  **Interface / contract**:
  - Add payloadSchemas[CardType.teamAudit.rawValue] as a real JSON Schema
    object matching T001's public fields, locked raw values, selected-body
    discriminator, and required/optional keys.
  - Keep both existing schema-list builders on the shared payloadSchemas map.
  - Do not duplicate Core validation or add persistence, UI, or transport APIs.

  **Functional acceptance**:
  - TA-SCHEMA-001 and TA-SCHEMA-002 pass: eleven advertised type values equal
    the eleven schema keys; each schema parses as a JSON object.
  - A fully populated TeamAuditPayload fixture proves all emitted model keys
    are declared.
  - The advertised discriminator/body combinations do not permit null, empty,
    unrelated, or mismatched section shapes rejected by Core.
  - Existing schema catalog entries and handler/fast-path parity remain.

  **Verification**:
  - Freeze evidence shows exactly these two paths.
  - Normal hooks own the hostless App logic gates. Do not run host-based App
    tests or manual platform builds as a completion gate; diagnose only an
    emitted hook failure.

  **Dependencies**: Hard-depends on T001 public types. Hard member of the
  coordinated publication barrier.

- [ ] **T003 [US1]** Coordinate aidash card-put help with the shared CardType contract.

  **Owning layer / context**: aidashCLI. Read root, CLI, and aidash context and
  technical-context files.

  **Files in scope**:
  - CLI/aidash/Sources/Commands/CardPutCommand.swift
  - CLI/aidash/Tests/CardPutCommandTests.swift

  **Files not to touch**:
  - CLI/aidash/Sources/Commands/SchemaListCommand.swift
  - CLI/aidash/Sources/SchemaListRendering.swift
  - CLI/aidash/Tests/SchemaListCommandTests.swift
  - Every other CLI, Core, App, UI, DesignKit, aidata, and spec path

  **Interface / contract**:
  - card put --type help derives or is proven against CardType.allCases so
    every supported type, including teamAudit, is discoverable.
  - Retain the existing generic CardPutRequest/XPC path and shared
    SchemaValidator behavior. Add no teamAudit-specific validator or renderer.
  - schema list remains a generic read-only consumer of the App result.

  **Functional acceptance**:
  - TA-CLI-001 passes: help includes every exact CardType raw value; a
    teamAudit request preserves type and payload through request construction.
  - Existing unknown-type failure and every existing card-put behavior remain.
  - Existing SchemaListCommandTests allCases validation remains accepted
    without modifying that file.

  **Verification**:
  - Freeze evidence shows exactly these two paths.
  - Normal hooks own the selected CLI gates. Manual reruns are diagnostic only
    after an emitted hook failure.

  **Dependencies**: Hard-depends on T001 CardType. May proceed in parallel
  with T002. Hard member of the coordinated publication barrier.

## Integration and publication barrier

Barrier B001 is not a fourth implementation task and owns no paths. It closes
only when:

1. T001, T002, and T003 are present in one local uncommitted candidate.
2. Its manifest contains exactly the sixteen allowed paths above.
3. All mapped acceptance rows have focused proof and forbidden paths are clean.
4. AI Reviewer independently reviews that frozen tree before publication and
   grants explicit publication permission.
5. The unchanged tree is committed normally, then pushed normally, allowing
   configured pre-commit and pre-push hooks to own verification.
6. A PR is created/updated and captured local commit, remote branch, and PR
   head SHAs are byte-for-byte equal.

Any source or test byte change after reviewer permission invalidates the
permission and returns to step 1. Core registration must not be pushed,
published, or merged by itself.

## Dependency graph

    exact 007 PASS
          |
        T001
       /    \
     T002  T003
       \    /
        B001
          |
    UI + producer/data successors

## Acceptance coverage

| Specification | Task / proof |
|---|---|
| US1/AC1–AC2; FR-002/003/007/008/010 | T001: TA-WIRE through TA-COLLISION, TA-API |
| US1/AC3–AC4; FR-004 | T001: TA-CASE-001 through 005 |
| US1/AC5–AC6; FR-005 | T001: TA-FULL-001 through 009 |
| US1/AC7; FR-006 | T001: TA-EXT-001 through 010 |
| US1/AC8; FR-009 | T001: TA-SIZE-001 through 003 |
| FR-001 | T001: TA-REG-001/003; T002: TA-SCHEMA; T003: TA-CLI |
| US1/AC9; FR-011 | T001/T002/T003 plus B001: TA-REG-002, TA-URL, TA-COMPAT |
| SC-001–SC-006 | T001–T003 focused rows plus B001 manifest/review/hook/SHA evidence |

## Definition of done

- Each task changes only its layer allowlist; the integrated manifest contains
  exactly the sixteen authorized paths.
- The exact public wire schema and all acceptance rows have focused proof.
- Existing DesignKit Classification.teamAudit is unchanged and has no task.
- The frozen uncommitted candidate receives independent prepublication review
  before any commit or push.
- Normal hook output is the required local verification evidence; no manual
  suite run is substituted.
- Only the unchanged reviewed candidate is committed/pushed, and local,
  remote, and PR SHAs then match.
- MY-1522's registered workspace, metadata, branch, plan, and candidates
  remain untouched.
