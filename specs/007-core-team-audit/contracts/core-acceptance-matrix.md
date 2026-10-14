# Core Team Audit Acceptance Matrix

Every row is required. A positive fixture starts from one shared neutral valid
builder. Negative fixtures mutate exactly the named dimension while keeping
all other values valid, so one assertion cannot mask another.

## Registration, round trip, and public API

| ID | Proof | Owner test |
|---|---|---|
| TA-REG-001 | `teamAudit` is the eleventh exact `CardType` wire value and decodes to `TeamAuditPayload`. | `EnumRoundtripTests.swift`, `CardTypeDecodeTests.swift` |
| TA-REG-002 | All ten existing card types retain their decode behavior. | existing suites plus `CardTypeDecodeTests.swift` |
| TA-REG-003 | Authored compact/standard/expanded sizes are preserved for `teamAudit`. | `EffectiveCardSizeTests.swift` |
| TA-RT-001 | Each of eight section variants is exactly equal after encode/decode and passes direct card validation. | `TeamAuditPayloadRoundTripTests.swift` |
| TA-RT-002 | All locked enums round-trip, and unknown locked values fail without coercion. | `TeamAuditPayloadRoundTripTests.swift`, `EnumRoundtripTests.swift` |
| TA-API-001 | External AIDashCore callers can construct the complete valid surface without `@testable import`. | `AIDashCorePublicAPITests/PublicInitTests.swift` |

## Axis, mode, and structural invariants

| ID | Positive | Required negative mutations | Owner test |
|---|---|---|---|
| TA-MODE-001 | Baseline has cohort only; incremental has cursors only. | both present; both absent; duplicate/blank case ID; duplicate/blank cursor source | `TeamAuditPayloadInvariantTests.swift` |
| TA-AXIS-001 | Three core axes and separate Task Effectiveness reconcile. | missing/duplicate/wrong axis; Task Effectiveness in core set; negative or unreconciled counts | `TeamAuditPayloadInvariantTests.swift` |
| TA-AXIS-002 | `insufficientEvidence` retains each enclosing core axis. | decode all three from distinct serialized fixtures and assert exact axis | `TeamAuditPayloadRoundTripTests.swift` |
| TA-SECTION-001 | Exactly the selected section body is populated. | selected body empty when required; unrelated body populated; section/body mismatch | `TeamAuditPayloadInvariantTests.swift` |
| TA-REF-001 | Every case/event/evidence/subject/finding/revision identity resolves once. | blank, dangling, duplicate, wrong-kind, duplicate local relationship | `TeamAuditPayloadInvariantTests.swift` |
| TA-HASH-001 | SHA-256 and optional merge OID shapes are exact. | uppercase, wrong length, non-hex for each role | `TeamAuditPayloadInvariantTests.swift` |

## Artifact `caseID` resolution

| ID | Fixture | Expected | Paths |
|---|---|---|---|
| TA-CASE-001 | Artifact omits `caseID`. | accept | direct card + production schema |
| TA-CASE-002 | Present trimmed `caseID` occurs exactly once in catalog. | accept | direct card + production schema |
| TA-CASE-003 | Present `caseID` is empty or whitespace. | reject | direct card + production schema |
| TA-CASE-004 | Present `caseID` has no catalog match. | reject | direct card + production schema |
| TA-CASE-005 | Catalog contains duplicate matching case identity. | reject | direct card + production schema |

Owner tests: `TeamAuditPayloadInvariantTests.swift` for structural isolation and
`SchemaValidatorTests.swift` for the production structured-error path.

## Full-report exact resolution

Run every negative row for both an overview-carried report and an
artifacts-section report. For externalization, repeat the six binding
dimensions against its embedded report.

| ID | Single mutation from valid fixture | Expected |
|---|---|---|
| TA-FULL-001 | none; exactly one complete catalog match | accept |
| TA-FULL-002 | catalog artifact kind is not `fullReport` | reject |
| TA-FULL-003 | artifact ID differs | reject |
| TA-FULL-004 | content hash differs | reject |
| TA-FULL-005 | raw URL differs | reject |
| TA-FULL-006 | sidecar ID differs | reject |
| TA-FULL-007 | sidecar hash differs | reject |
| TA-FULL-008 | matching catalog artifact is absent | reject |
| TA-FULL-009 | matching catalog artifact identity is duplicated | reject |

Owner tests: `TeamAuditPayloadInvariantTests.swift` for binding semantics and
`TeamAuditPayloadValidationTests.swift` for URL safety.

## Externalization matrix

| ID | Fixture/mutation | Expected |
|---|---|---|
| TA-EXT-001 | Each of the eight allowed optional kinds, positive count, exact reason/sidecar/report | accept |
| TA-EXT-002 | `encodedByteCount == 0` | reject |
| TA-EXT-003 | `encodedByteCount < 0` | reject |
| TA-EXT-004 | unknown kind on wire | decode failure |
| TA-EXT-005 | any mandatory-shaped entity kind on wire | decode failure; no representable enum case |
| TA-EXT-006 | reason differs from `exceedsInlinePayloadLimit` | decode or invariant failure |
| TA-EXT-007 | sidecar ID differs from envelope | reject |
| TA-EXT-008 | sidecar hash differs from envelope | reject |
| TA-EXT-009 | embedded report differs by kind, ID, hash, URL, sidecar ID, or sidecar hash, one field at a time | reject each mutation |
| TA-EXT-010 | embedded report has no or duplicate catalog resolution | reject |

Owner tests: `TeamAuditPayloadInvariantTests.swift` and
`TeamAuditPayloadRoundTripTests.swift`.

## URL behavior

| ID | Fixture | Expected |
|---|---|---|
| TA-URL-001 | HTTPS full report, mandatory artifact, and present PR URLs with hosts | accept |
| TA-URL-002 | Each mandatory/actionable URL is HTTP, hostless, malformed, or empty, one field at a time | reject through existing structured path |
| TA-URL-003 | Optional artifact/grill string is unsafe | preserve exact string and accept structurally; no actionable URL is produced by Core |
| TA-URL-004 | Models source dependency scan | no `URLPolicy` or Validation reference |

Owner test: `TeamAuditPayloadValidationTests.swift`; production-path
confirmation in `SchemaValidatorTests.swift`.

## Received bytes and compatibility

| ID | Proof | Owner test |
|---|---|---|
| TA-SIZE-001 | Otherwise-valid final JSON is exactly 262,144 received bytes. | accepted by `SchemaValidatorTests.swift` |
| TA-SIZE-002 | Otherwise-valid mandatory final JSON is exactly 262,145 received bytes. | rejected by `SchemaValidatorTests.swift` |
| TA-SIZE-003 | Decision uses received `Data.count`, not re-encoded semantic size. | fixture includes byte-count-sensitive legal JSON representation |
| TA-COMPAT-001 | Existing schema structured errors and byte-limit behavior are unchanged. | existing `SchemaValidatorTests.swift` remains green |
| TA-COMPAT-002 | Existing URL policy behavior is unchanged. | existing URL suites remain green; `URLPolicy.swift` unchanged |

## Traceability

| Acceptance | Matrix coverage |
|---|---|
| US1/AC1 | TA-RT-001, TA-REF-001, TA-API-001 |
| US1/AC2 | TA-AXIS-001, TA-AXIS-002 |
| US1/AC3 | TA-CASE-001, TA-CASE-002 |
| US1/AC4 | TA-CASE-003 through TA-CASE-005 |
| US1/AC5 | TA-FULL-001 |
| US1/AC6 | TA-FULL-002 through TA-FULL-009 |
| US1/AC7 | TA-EXT-001 through TA-EXT-010 |
| US1/AC8 | TA-SIZE-001 through TA-SIZE-003 |
| US1/AC9 | TA-REG-002, TA-URL-003/004, TA-COMPAT-001/002 |
| FR-001–FR-003 | TA-REG, TA-RT, TA-MODE, TA-AXIS, TA-SECTION |
| FR-004 | TA-CASE-001 through TA-CASE-005 |
| FR-005 | TA-FULL-001 through TA-FULL-009 |
| FR-006 | TA-EXT-001 through TA-EXT-010 |
| FR-007–FR-008 | TA-URL-004, TA-RT-002, TA-COMPAT |
| FR-009 | TA-SIZE-001 through TA-SIZE-003 |
| FR-010 | TA-API-001 |
| FR-011 | TA-REG-002, TA-COMPAT-001/002 |
