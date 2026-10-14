# Quickstart: Implement the Core Team Audit Contract

## Preconditions

1. Use the successor implementation workspace, never the preserved MY-1522
   workspace.
2. Base work on the exact 007 revision named by the AI Reviewer PASS, or an
   explicitly approved descendant with byte-identical planning artifacts.
3. Verify repository identity LeePepe/AIDash and record the immutable base.
4. Read root plus each affected Core, App, and CLI context/routing document.
5. Treat T001, T002, and T003 as one publication unit.

## T001 — Core

Work only in T001's twelve paths.

1. Implement the exact public values and structural/reference invariants from
   data-model.md in TeamAuditPayload.swift.
2. Implement the Validation-role witness and unchanged central URL-policy
   calls in TeamAuditPayloadValidation.swift.
3. Register teamAudit and preserve small, medium, wide, and hero through both
   effective-size resolver paths.
4. Add the focused round-trip, invariant, validation, registration, enum,
   size, production-schema, and external-public proofs.
5. Implement every Core matrix row, especially the field-complete nested
   surface, artifact caseID catalog rule, and full-report/externalization
   one-field negatives.

Do not edit SchemaValidator.swift, URLPolicy.swift, CardPayloadProtocol.swift,
Package.swift, the broad shared payload test, or another layer.

## T002 — App schema

After T001 fixes the public surface, work only in T002's two App paths.

1. Add the teamAudit JSON schema to the shared payloadSchemas catalog.
2. Describe every public field, required/optional key, locked value, and
   selected-body discriminator relation.
3. Prove both schema builders expose eleven type values and eleven schemas,
   each schema parses, all fully populated model keys are declared, and invalid
   body combinations are not advertised.

Use the hostless App logic test owner. Do not edit project.yml or add App
storage, UI, or transport behavior.

## T003 — CLI shared consumer

After T001 fixes CardType, work only in T003's two CLI paths.

1. Make card put type help derive from or remain mechanically complete against
   CardType.allCases.
2. Prove every raw value, including teamAudit, is discoverable and a
   teamAudit request preserves its generic type/payload fields.
3. Retain the existing shared Core validator and generic schema-list renderer.

Do not add an audit-specific CLI decoder, validator, renderer, or schema copy.

## Verification and handoff

1. Freeze one local uncommitted candidate containing exactly the sixteen task
   paths and record its manifest.
2. Request independent AI Reviewer content/architecture review of that fixed
   tree and obtain explicit publication permission before committing.
3. Commit the unchanged reviewed tree normally. The configured pre-commit
   hooks own resolver-selected local verification.
4. Push normally. The configured pre-push hooks own their gates.
5. Create or update the PR, capture local/remote/PR SHAs, and prove equality.

Do not manually run swift build, swift test, xcodebuild, host-based App tests,
or another suite as the required completion evidence. A focused command is
allowed only to diagnose a failure already emitted by a normal hook. Any
source/test byte change after review requires a new freeze and review.

Do not publish or merge T001 alone. UI rendering and producer/data work remain
downstream. The existing DesignKit Classification.teamAudit token is reused
unchanged and has no successor task.
