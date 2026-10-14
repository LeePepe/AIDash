# Quickstart: Implement the Core Team Audit Contract

## Preconditions

1. Use the implementation workspace prepared for the successor, not the
   preserved MY-1522 workspace.
2. Base implementation on the exact planning revision named by the AI Reviewer
   PASS, or on an explicitly approved descendant whose `007` planning artifact
   blobs are byte-identical.
3. Confirm the approved repository identity is `LeePepe/AIDash` and record the
   immutable implementation base before editing.
4. Read root and AIDashCore context/routing instructions.

## Implement T001

Work only in the twelve paths listed in `plan.md` and `tasks.md`.

1. Add the public value model and Types-owned structural/reference invariants
   in `TeamAuditPayload.swift`.
2. Add the Validation-role protocol witness and central URL-policy checks in
   `TeamAuditPayloadValidation.swift`.
3. Register `.teamAudit` in `CardType` and preserve authored size in
   `EffectiveCardSize`.
4. Add focused round-trip, invariant, Validation-role, registration, enum,
   effective-size, production-schema, and external public-construction proofs.
5. Implement every row in `contracts/core-acceptance-matrix.md`, especially
   artifact `caseID` resolution and the one-field report/externalization
   negative matrix.

Do not edit `SchemaValidator.swift`, `URLPolicy.swift`,
`CardPayloadProtocol.swift`, `Package.swift`, the broad shared payload test, or
any non-Core layer.

## Verify the implementation

First inspect the diff path list relative to the approved base. If every change
is under `Packages/` as required, use only Swift Package Manager:

```bash
cd Packages/AIDashCore
swift build
swift test
```

Do not run `xcodebuild` for this package-only task. Also verify:

- all changed files are in the twelve-path allowlist;
- no Models source refers to `URLPolicy` or a Validation symbol;
- all eight variants round-trip and validate through public and production
  paths;
- exact 262,144/262,145-byte fixtures use received UTF-8 bytes;
- existing ten card types retain behavior, with only the expected enum-count
  tripwire changing from ten to eleven.

## Handoff

Capture the implementation commit SHA, pushed branch SHA, and PR head SHA and
require byte-for-byte equality before exact-SHA content review. Hand off the
acceptance-matrix results and diff allowlist. App schema advertisement, UI
rendering, and producer work remain separately owned successors.
