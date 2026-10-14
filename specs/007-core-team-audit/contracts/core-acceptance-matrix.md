# Core Team Audit Acceptance Matrix

Every row is required. Positive fixtures start from one neutral field-complete
builder. A negative fixture mutates exactly the named dimension while all
other values remain valid.

## Registration, schema coordination, and public API

| ID | Required proof | Owner test |
|---|---|---|
| TA-REG-001 | teamAudit is the eleventh exact CardType wire value and dispatches only to TeamAuditPayload. | EnumRoundtripTests.swift; CardTypeDecodeTests.swift |
| TA-REG-002 | The ten existing card types retain decode behavior. | Existing Core suites; CardTypeDecodeTests.swift |
| TA-REG-003 | small, medium, wide, and hero pass through unchanged in both EffectiveCardSize resolver paths: serialized Data and decoded payload, including collapse-to-list enabled. | EffectiveCardSizeTests.swift |
| TA-SCHEMA-001 | The App advertises one parseable non-placeholder JSON object schema for teamAudit and exactly one schema for every CardType in both schema-list builders. | XPCHandlersContainerCardTests.swift |
| TA-SCHEMA-002 | A fully populated public TeamAuditPayload fixture has every emitted key declared by the App schema, and its section discriminator prevents body combinations Core rejects. | XPCHandlersContainerCardTests.swift |
| TA-CLI-001 | card put help exposes every CardType.allCases raw value, including teamAudit; a teamAudit request preserves its generic type/payload; the shared schema.list result remains generically renderable and Core type filtering accepts teamAudit. | CardPutCommandTests.swift; existing SchemaListCommandTests.swift |
| TA-API-001 | External callers construct every public nested type and all eight valid payload variants without testable import. | AIDashCorePublicAPITests/PublicInitTests.swift |

## Envelope, wire shape, overview, and reconciliation

| ID | Positive proof | Required focused negatives | Owner test |
|---|---|---|---|
| TA-WIRE-001 | Every required envelope field and exactly the selected non-null body key round-trip. | absent selected key; null/empty selected body; unrelated empty/null/populated body key; discriminator mismatch | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-MODE-001 | baseline has a typed cohort and empty cursors; incremental omits cohort and has non-empty unique-source cursors. | both present; both absent; blank/duplicate cohort case; blank/duplicate cursor source; negative overlap | TeamAuditPayloadInvariantTests.swift |
| TA-OVERVIEW-001 | AuditScope, cohort/cursors, instruction versions, collision count, and limitations survive exactly. | blank portable identity; duplicate instruction source; negative collision count; blank limitation | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-COVERAGE-001 | available + missing = required and redacted <= available; incomplete evidence carries a limitation. | every negative count; each equation mismatch; missing limitation | TeamAuditPayloadInvariantTests.swift |
| TA-AXIS-001 | Exactly one of each core axis, with axis-specific verdict and positive + negative + insufficient = total. | missing/duplicate/wrong axis; Task Effectiveness in core set; negative count; each equation mismatch | TeamAuditPayloadInvariantTests.swift |
| TA-AXIS-002 | The three serialized insufficientEvidence values retain their enclosing conformance, fitness, or outcome axis. | decode three distinct fixtures and assert exact typed union case | TeamAuditPayloadRoundTripTests.swift |
| TA-EFFECT-001 | The five Task Effectiveness counts are separate and sum to totalEvaluated. | negative count; each independent total mismatch | TeamAuditPayloadInvariantTests.swift |
| TA-PUB-001 | Four required/published pairs reconcile independently; non-zero omitted/externalized count has a resolved report. | each pair mismatched alone; finding satisfied only by chain; mandatory count replaced by report; non-zero optional count without report | TeamAuditPayloadInvariantTests.swift |
| TA-CATALOG-001 | Every catalog identity is trimmed, unique, and contains only its locked identity/binding fields. | blank/duplicate case, event, evidence, subject, revision, finding, or artifact identity; finding priority mismatch; artifact binding drift | TeamAuditPayloadInvariantTests.swift |
| TA-HASH-001 | Every SHA-256 and optional merge SHA has its exact lowercase shape. | uppercase, wrong length, and non-hex for every hash role | TeamAuditPayloadInvariantTests.swift |

## Findings, timelines, metrics, lineage, repeats, and collisions

| ID | Positive proof | Required focused negatives | Owner test |
|---|---|---|---|
| TA-FINDING-001 | Every finding field, all six states, four priorities, four axes, owner, and non-empty evidence arrays round-trip and catalog-resolve. | duplicate fingerprint; blank identity; priority mismatch; empty/duplicate/dangling case, event, evidence, or subject | TeamAuditPayloadRoundTripTests.swift; EnumRoundtripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-TIMELINE-001 | eventIDs and attemptIDs exactly equal ordered embedded identities and every child binds to the timeline case. | missing, duplicate, reordered, extra, or foreign child identity/back-reference | TeamAuditPayloadInvariantTests.swift |
| TA-TIMELINE-002 | Every event and attempt field survives; case/event/evidence/subject/revision values resolve. | blank source/kind/cycle/outcome; dangling reference; unknown actor role or trigger raw value | TeamAuditPayloadRoundTripTests.swift; EnumRoundtripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-METRIC-001 | Every metric field survives, subject resolves, values are non-negative, and denominator is positive. | duplicate/blank metric ID; dangling subject; negative value; zero denominator; blank limitation | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-LINEAGE-001 | lineageID equals lowercase SHA-256 of the trimmed problem U+001F origin U+001F delivery UTF-8 tuple. | delimiter substitution; untrimmed-hash substitution; changed tuple member; uppercase/wrong hash | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-LINEAGE-002 | All optional release fields and locked states survive; supporting lists are non-empty, unique, and resolved where catalog-backed. | malformed merge SHA; unknown channel/state; blank/duplicate/dangling observation; blank/duplicate related feedback; unsafe present PR URL | EnumRoundtripTests.swift; TeamAuditPayloadInvariantTests.swift; TeamAuditPayloadValidationTests.swift |
| TA-REPEAT-001 | Planner Lead exact tagged counters and primary-round bound pass. | role/tag mismatch; primary rounds exceed attempts; omitted/negative counter | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-REPEAT-002 | Team Lead exact tagged counters and primary-round bound pass. | role/tag mismatch; primary rounds exceed attempts; omitted/negative counter | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-REPEAT-003 | Fullstack Engineer exact tagged counters and primary-round bound pass. | role/tag mismatch; primary rounds exceed attempts; omitted/negative counter | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-REPEAT-004 | AI Reviewer exact tagged counters and primary-round bound pass. | role/tag mismatch; primary rounds exceed attempts; omitted/negative counter | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-REPEAT-005 | PR Manager exact tagged counters, including both primary round totals, pass. | role/tag mismatch; either primary total exceeds attempts; omitted/negative counter | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-REPEAT-006 | Common counts, cycle/cause maps, same/changed split, zero-attempt behavior, and supporting evidence reconcile. | each equation independently mismatched; empty/duplicate/dangling subject/event; non-zero repeat/round/max with zero attempts | TeamAuditPayloadInvariantTests.swift |
| TA-COLLISION-001 | Every collision field survives, disposition is locked, hashes differ, and parent ID/hash equal the envelope. | duplicate observation; foreign parent ID/hash; equal/malformed hashes; blank entity; unknown disposition; rejected body key | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |

## Artifact manifest and case resolution

| ID | Positive proof | Required focused negatives | Owner test |
|---|---|---|---|
| TA-ARTIFACT-001 | ArtifactSection, every manifest field/kind/requirement, unique IDs, envelope bindings, and chain references round-trip. | empty section; duplicate artifact; foreign snapshot/sidecar; dangling finding/event/revision; P0/P1 optional chain; mandatory artifact without URL | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift |
| TA-GRILL-001 | GrillLinks preserves either/both raw strings and exact envelope sidecar binding. | present object with no URL; foreign sidecar ID/hash; unsafe strings changed or rejected structurally | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadInvariantTests.swift; TeamAuditPayloadValidationTests.swift |

Run every artifact case through direct card validation and the production
schema path.

| ID | Fixture | Expected |
|---|---|---|
| TA-CASE-001 | Artifact omits caseID. | accept |
| TA-CASE-002 | Present trimmed caseID occurs exactly once in catalog. | accept |
| TA-CASE-003 | Present caseID is empty or whitespace. | reject |
| TA-CASE-004 | Present caseID has no catalog match. | reject |
| TA-CASE-005 | Catalog contains the matching case identity twice. | reject |

Owner tests: TeamAuditPayloadInvariantTests.swift and SchemaValidatorTests.swift.

## Full-report exact resolution

Run each row for overview publication coverage, ArtifactSection, and an
externalized embedded report. Negative rows mutate only one binding dimension.

| ID | Mutation from valid fixture | Expected |
|---|---|---|
| TA-FULL-001 | none; exactly one complete catalog match | accept |
| TA-FULL-002 | catalog artifact kind is not fullReport | reject |
| TA-FULL-003 | artifact ID differs | reject |
| TA-FULL-004 | content hash differs | reject |
| TA-FULL-005 | raw URL differs | reject |
| TA-FULL-006 | sidecar ID differs | reject |
| TA-FULL-007 | sidecar hash differs | reject |
| TA-FULL-008 | matching catalog artifact is absent | reject |
| TA-FULL-009 | matching catalog artifact identity is duplicated | reject |

Owner tests: TeamAuditPayloadInvariantTests.swift for binding and
TeamAuditPayloadValidationTests.swift for URL safety.

## Externalization matrix

| ID | Fixture / mutation | Expected |
|---|---|---|
| TA-EXT-001 | Each of eight allowed kinds, positive count, exact reason/sidecar/report | accept |
| TA-EXT-002 | encodedByteCount is zero | reject |
| TA-EXT-003 | encodedByteCount is negative | reject |
| TA-EXT-004 | unknown kind on wire | structured decode failure |
| TA-EXT-005 | any mandatory-shaped kind on wire | structured decode failure; no enum case |
| TA-EXT-006 | reason differs from exceedsInlinePayloadLimit | structured decode or invariant failure |
| TA-EXT-007 | sidecar ID differs from envelope | reject |
| TA-EXT-008 | sidecar hash differs from envelope | reject |
| TA-EXT-009 | report differs by kind, ID, hash, URL, sidecar ID, or sidecar hash, one field at a time | reject every mutation |
| TA-EXT-010 | report has no or duplicate catalog resolution | reject |

Owner tests: TeamAuditPayloadInvariantTests.swift and
TeamAuditPayloadRoundTripTests.swift.

## URL, received bytes, and compatibility

| ID | Required proof | Owner test |
|---|---|---|
| TA-URL-001 | HTTPS full-report, mandatory artifact, and present PR URLs with hosts pass. | TeamAuditPayloadValidationTests.swift; SchemaValidatorTests.swift |
| TA-URL-002 | HTTP, hostless, malformed, or empty mandatory/actionable URL rejects one field at a time through the existing structured path. | TeamAuditPayloadValidationTests.swift; SchemaValidatorTests.swift |
| TA-URL-003 | Unsafe optional artifact and grill strings remain exact accepted data and are not made actionable by Core. | TeamAuditPayloadRoundTripTests.swift; TeamAuditPayloadValidationTests.swift |
| TA-URL-004 | Models contains no URLPolicy or Validation-role reference. | Dependency scan in reviewed diff |
| TA-SIZE-001 | Otherwise-valid final JSON is exactly 262,144 received UTF-8 bytes and is accepted. | SchemaValidatorTests.swift |
| TA-SIZE-002 | Otherwise-valid mandatory final JSON is exactly 262,145 received UTF-8 bytes and is rejected. | SchemaValidatorTests.swift |
| TA-SIZE-003 | The decision uses received Data.count, not re-encoded semantic size. | SchemaValidatorTests.swift |
| TA-COMPAT-001 | Existing structured errors, byte gate, and ten card payloads are unchanged. | Existing Core tests |
| TA-COMPAT-002 | URLPolicy behavior and interface are unchanged. | Existing URL tests; URLPolicy.swift unchanged |
| TA-COMPAT-003 | Existing DesignKit Classification.teamAudit token and its baseline golden/contrast behavior are reused unchanged. | Existing DesignKit tests; no DesignKit diff |

## Traceability

| Acceptance | Matrix coverage |
|---|---|
| US1/AC1–AC2 | TA-WIRE, TA-MODE, TA-OVERVIEW, TA-COVERAGE, TA-AXIS, TA-EFFECT, TA-PUB, TA-CATALOG |
| US1/AC3–AC4 | TA-CASE-001 through TA-CASE-005 |
| US1/AC5–AC6 | TA-FULL-001 through TA-FULL-009 |
| US1/AC7 | TA-EXT-001 through TA-EXT-010 |
| US1/AC8 | TA-SIZE-001 through TA-SIZE-003 |
| US1/AC9 | TA-REG, TA-SCHEMA, TA-CLI, TA-URL, TA-COMPAT |
| FR-001 | TA-REG-001/003, TA-SCHEMA-001/002, TA-CLI-001 |
| FR-002–FR-003 | TA-WIRE through TA-COLLISION |
| FR-004 | TA-CASE-001 through TA-CASE-005 |
| FR-005 | TA-FULL-001 through TA-FULL-009 |
| FR-006 | TA-EXT-001 through TA-EXT-010 |
| FR-007–FR-008 | TA-API, TA-CATALOG, TA-HASH, TA-URL, all exact round trips |
| FR-009 | TA-SIZE-001 through TA-SIZE-003 |
| FR-010 | TA-API-001 |
| FR-011 | TA-REG-002, TA-CLI-001, TA-COMPAT-001 through 003 |
