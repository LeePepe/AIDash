# Implementation Plan: Core Team Audit Contract

**Branch**: 007-core-team-audit | **Date**: 2026-10-14 |
**Spec**: specs/007-core-team-audit/spec.md

**Input**: Fresh successor specification derived from immutable current main
bdf1435fe7d3d9c4da43ed4297cbc24482447b46.

## Summary

Add the missing AIDashCore teamAudit contract as one deep module with a
field-complete public wire surface, eight locked section variants, exact local
catalog resolution, deterministic reconciliation, and one Validation-role URL
seam. Register the eleventh type and preserve all four authored sizes.

Coordinate registration with two narrow consumer adaptations: AIDashApp adds
the matching schema-list JSON schema and aidash makes card put help reflect
CardType.allCases while retaining generic shared validation. Core, App, and CLI
are separate layer tasks but one non-severable publication unit. The two
historical FR-024 residuals remain explicit: artifact caseID catalog resolution
and the complete full-report/externalization one-field negative matrix.

## Technical Context

**Language/Version**: Swift 6 strict concurrency

**Primary Dependencies**: Foundation and existing AIDashCore/App/CLI
interfaces; no new package or third-party dependency

**Storage**: None; immutable Codable values and existing schema-list metadata

**Testing**: Existing Core, hostless AIDashAppLogicTests, and CLI test targets,
selected by repository hooks

**Target Platform**: Existing package and application platforms

**Performance**: Deterministic validation; exact received-payload acceptance
through 262,144 UTF-8 bytes

**Constraints**: One production decode; Models cannot depend on Validation;
URLPolicy and SchemaValidator remain unchanged; neutral fixtures; normal
pre-commit/pre-push hooks own local gates; focused commands are diagnostic
only after an emitted hook failure

**Scale/Scope**: One card type, eight sections, twelve Core paths, two App
paths, two CLI paths, and no UI/data/producer/DesignKit change

## Constitution Check

### Pre-design gate

| Principle / bar | Result | Evidence |
|---|---|---|
| Agent-authored, user-read | PASS | Immutable audit output grants no mutation, dispatch, or remediation authority. |
| Coordinated type release | PASS | Core registration cannot publish without App schema parity and CLI help/consumer proof. |
| Typed schema | PASS | data-model.md fixes every field, optionality, enum, equation, and reference. |
| Orthogonal card dimensions | PASS | teamAudit is a type and all four authored CardSize values pass through. |
| Deep-module boundary | PASS | Callers learn CardType.teamAudit and TeamAuditPayload; resolution remains hidden. |
| Intra-layer direction | PASS | Models owns data/structure; Validation supplies the witness and central policy call. |
| Scope discipline | PASS | Three layer-scoped tasks have exact allowlists and a hard integration barrier. |
| Error handling | PASS | Existing structured decode/schema errors carry unknown or invalid values. |
| Public identity | PASS | Fixtures use neutral example identities and hosts. |
| Verification | PASS | Configured hooks own resolver-selected gates; no manual suite duplication. |

### Post-design gate

PASS by plan. The exact public surface and focused matrix remove ambiguous
wire alternatives. App and CLI adaptations close the coordinated-release gap
without introducing an audit-specific consumer API. The existing DesignKit
Classification.teamAudit token is reused unchanged.

## Project Structure

### Planning artifacts

    specs/007-core-team-audit/
    ├── spec.md
    ├── plan.md
    ├── research.md
    ├── data-model.md
    ├── quickstart.md
    ├── tasks.md
    ├── checklists/requirements.md
    └── contracts/
        ├── core-team-audit.md
        └── core-acceptance-matrix.md

### Implementation surfaces

    Packages/AIDashCore/
      Sources/AIDashCore/Models/CardType.swift
      Sources/AIDashCore/Models/EffectiveCardSize.swift
      Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift
      Sources/AIDashCore/Validation/TeamAuditPayloadValidation.swift
      Tests/AIDashCoreTests/
      Tests/AIDashCorePublicAPITests/PublicInitTests.swift

    Apps/AIDashApp/
      Sources/XPCService/XPCPayloadSchemas.swift
      Tests/XPCHandlersContainerCardTests.swift

    CLI/aidash/
      Sources/Commands/CardPutCommand.swift
      Tests/CardPutCommandTests.swift

**Structure decision**: Keep the public model and structural invariants in one
Core Types file and its protocol/URL-policy orchestration in one Validation
file. Keep schema advertisement in the existing App-owned catalog and CLI help
in its existing command. No cross-layer task owns another layer's code.

## Module and seam design

### TeamAuditPayload

**Public interface**: One Codable, Equatable, Sendable payload with a fixed
envelope, one selected body key, and the complete nested surface in
data-model.md. Every valid value is externally constructible.

**Hidden implementation**: Section exclusivity, identity uniqueness,
reconciliation, typed-axis decode, lineage hashing, timeline ordering, repeat
equations, reference resolution, report binding, and externalization rules.

**Validation seam**: TeamAuditPayloadValidation.swift supplies
validateInvariants, calls the internal structural validator, then applies
unchanged URLPolicy only to actionable mandatory/report/PR strings.

**Production seam**: CardType.validate and
SchemaValidator.validateCardPut keep their interfaces and existing structured
error mapping.

### App schema catalog

XPCPayloadSchemas.swift owns the hand-written JSON schema. The teamAudit entry
must describe the locked discriminator/body relation and all public fields.
Both schema builders already consume the same payloadSchemas dictionary.
XPCHandlersContainerCardTests proves parseability, eleven-to-eleven parity,
fully populated field coverage, and rejected-combination exclusion.

### CLI shared consumer

CardPutCommand continues to send generic card.put requests and use shared Core
validation. Its help text must derive or be tested against every
CardType.allCases value, including teamAudit. No audit-specific decoder,
renderer, transport, or schema copy is added.

## Exact change boundaries

### T001 — AIDashCore allowed paths

1. Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift
2. Packages/AIDashCore/Sources/AIDashCore/Validation/TeamAuditPayloadValidation.swift
3. Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift
4. Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift
5. Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadRoundTripTests.swift
6. Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift
7. Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadValidationTests.swift
8. Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift
9. Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift
10. Packages/AIDashCore/Tests/AIDashCoreTests/EffectiveCardSizeTests.swift
11. Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorTests.swift
12. Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift

### T002 — AIDashApp allowed paths

1. Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift
2. Apps/AIDashApp/Tests/XPCHandlersContainerCardTests.swift

### T003 — aidash CLI allowed paths

1. CLI/aidash/Sources/Commands/CardPutCommand.swift
2. CLI/aidash/Tests/CardPutCommandTests.swift

### Forbidden paths

- Packages/AIDashCore/Sources/AIDashCore/Validation/SchemaValidator.swift
- Packages/AIDashCore/Sources/AIDashCore/Validation/URLPolicy.swift
- Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/CardPayloadProtocol.swift
- Packages/AIDashCore/Package.swift
- Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift
- Apps/AIDashApp/project.yml and every other Apps path
- CLI schema-list source/tests and every other CLI path
- Packages/AIDashUI, Packages/DesignKit, aidata, storage, producer, routing,
  constitution, and unrelated specification paths

If implementation needs any forbidden path, stop and return to Team Lead for a
fresh planning decision.

## Dependency and delivery graph

    exact 007 revision + AI Reviewer spec/plan PASS
                         |
                         v
                   T001 AIDashCore
                    /           \
                   v             v
        T002 App schema       T003 CLI help
                    \           /
                     v         v
              one fixed integrated candidate
                         |
             AI Reviewer prepublication PASS
                         |
          commit hooks -> push hooks -> PR/SHA proof
                         |
            UI and producer/data successors

T002 and T003 depend on T001's public type vocabulary. No Core-only candidate
may be published, pushed, or merged. The integration barrier closes only when
all three layer tasks are present in one frozen candidate and every mapped
acceptance row is satisfied.

## Verification and publication strategy

The normal repository flow owns verification:

1. Freeze the complete local uncommitted three-layer candidate and exact path
   manifest.
2. Obtain independent AI Reviewer content/architecture review and explicit
   publication permission for that fixed tree.
3. Commit the unchanged reviewed tree normally. Resolver-selected pre-commit
   hooks produce the required local Core and focused test evidence.
4. Push normally. Resolver-selected pre-push hooks produce their required
   evidence.
5. Create or update the PR, then prove captured local commit SHA equals the
   remote branch and PR head.

Do not manually run swift build, swift test, xcodebuild, or host-based
AIDashApp tests as a completion gate. A focused rerun is allowed only to
diagnose a failure emitted by a normal hook. App heavy platform builds remain
CI-only; XPCHandlersContainerCardTests is owned by the hostless App logic test
target. Any candidate byte change after review invalidates publication
permission and requires a new freeze/review.

Planning-only verification uses Spec Kit prerequisites,
scripts/hooks/check-tasks-fresh, and scripts/context/audit. It runs no product
build or product test.

## Complexity tracking

No constitutional exception is required. Three layer tasks are necessary
because current main makes CardType.allCases a shared release surface; keeping
their allowlists separate preserves ownership while the barrier preserves
schema sufficiency.
