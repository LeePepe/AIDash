# Contract: T005 AIDashCore Acceptance Matrix

This contract is the complete implementation boundary for T005. The task is
one AIDashCore-only PR. It may modify only the eleven files listed in the T005
row of `tasks.md`: the original nine Types/test paths plus
`Validation/TeamAuditPayloadValidation.swift` and
`TeamAuditPayloadValidationTests.swift`. It does not carry planning, AIDashUI,
App, CLI, aidata, or RepoInfra changes. The existing
`Validation/SchemaValidator.swift` and `Validation/URLPolicy.swift` are
consumed unchanged and are not in scope.

The implementation base is the exact published planning commit that receives
AI Reviewer `PASS`, as pinned in Team Lead's fresh handoff. Parent
`fdace13d20ee0b28759c4853c82445fd4d913dcc` alone is not an implementation
base because it does not contain FR-020–FR-025. A later approved descendant is
valid only when these nine planning artifact blobs are byte-identical.

## Intra-layer architecture seam

The existing interfaces remain `CardType.validate(_:)` and its production
caller `SchemaValidator.validateCardPut`. The Types file exposes only an
internal `validateStructuralInvariants()` helper. A Service-role extension in
`TeamAuditPayloadValidation.swift` supplies the public
`validateInvariants()` protocol witness, calls the structural helper, and then
passes the decoded audit payload to an internal
`TeamAuditPayloadURLValidator`. Only that Validation-role module calls
`URLPolicy`. `Models/**` never imports or calls a Validation-role type, and the
single decode/structured-error path remains unchanged.

The internal URL validator rejects an invalid present feedback-lineage PR URL,
an invalid full-report URL, and a missing/invalid mandatory artifact URL using
the existing structured payload error. Optional artifact/grill strings remain
opaque and round-trip unchanged; render-time actionability remains a separate
consumer of the same central policy. No URL scheme/host logic is duplicated in
Models and `URLPolicy` itself is unchanged.

## Public type surface

`TeamAuditPayload` is one public `CardPayloadProtocol`, `Codable`, and
`Sendable` model with a common envelope and exactly eight section cases:
`overview`, `findings`, `caseTimelines`, `individualMetrics`,
`feedbackLineage`, `agentRepeatMetrics`, `importObservations`, and
`artifacts`. Exactly one section value is populated and it must match the
section discriminator.

The public nested surface includes, at minimum:

- envelope and overview: `AuditScope`, `AuditMode`, `AuditCohort`,
  `AuditCursor`, `InstructionVersion`, `EvidenceCoverage`,
  `SnapshotReferenceCatalog`, `FindingReference`, three locked axis-specific
  verdict types, axis-tagged `CoreAxisVerdict`, `CoreAxisSummary`,
  `TaskEffectivenessSummary`, and `PublicationCoverage`;
- evidence: `AuditFinding`, `FindingPriority`, `FindingState`,
  `RemediationOwner`, `AuditCaseTimeline`, `AuditEvent`, `AuditAttempt`,
  `ActorRole`, `IndividualMetric`, `FeedbackLineage`, `ReleaseChannel`, and
  `TaskEffectivenessState`;
- repeats: `AgentRepeatMetric`, `RepeatTriggerCause`, and the five-case
  `RoleSpecificRepeatMetrics` tagged union;
- immutable artifacts: `ImportCollisionObservation`,
  `ImportObservationDisposition`, `ArtifactManifestEntry`,
  `ArtifactRequirement`, `ArtifactSection`, `GrillLinks`,
  `ArtifactReference`, `FullReportReference`, `ExternalizableEntityKind`, and
  `ExternalizedEntityReference`.

All public structs, enums, properties required to construct a valid fixture,
and memberwise initializers are callable from `AIDashCorePublicAPITests`
without `@testable import`.

## Locked wire vocabulary

| Type | Exact raw values / rule |
|---|---|
| `TeamAuditSection` | `overview`, `findings`, `caseTimelines`, `individualMetrics`, `feedbackLineage`, `agentRepeatMetrics`, `importObservations`, `artifacts` |
| `AuditMode` | `baseline`, `incremental` |
| Core axes | exactly `workflowConformance`, `workflowFitness`, `outcomeIntegrity`; `taskEffectiveness` is not a core-axis value |
| Conformance verdict | `conformant`, `nonconformant`, `insufficientEvidence` |
| Fitness verdict | `fit`, `unfit`, `insufficientEvidence` |
| Outcome verdict | `intact`, `compromised`, `insufficientEvidence` |
| `FindingPriority` | `P0`, `P1`, `P2`, `info` with matching case-sensitive JSON |
| `FindingState` | `open`, `acknowledged`, `approvedForRemediation`, `resolved`, `regressed`, `superseded` |
| `ActorRole` | `plannerLead`, `teamLead`, `fullstackEngineer`, `aiReviewer`, `prManager` |
| `ReleaseChannel` | `testflight`, `appStore`, `production`, `internal` |
| `ImportObservationDisposition` | only `rejectedIdentityHashCollision` |
| `RoleSpecificRepeatMetrics` | discriminator cases exactly match the five `ActorRole` values |

Unknown locked raw values must produce the existing structured payload decode
failure and caller-level generic card fallback; they are never coerced to a
known semantic case. The explicit `RepeatTriggerCause.unknown` wire value is
source data and round-trips unchanged. T005 proves structured Core failure;
T008 proves the resulting rendered generic-card fallback in AIDashUI.

## Semantic and referential invariants

1. Stable identities and required display strings are non-empty after
   trimming. Every `*SHA256` field matches `^[0-9a-f]{64}$`.
2. `partCount > 0`, `0 <= partIndex < partCount`, and all counts are
   non-negative.
3. Baseline requires a typed cohort and has no cursors. Incremental has no
   cohort and requires one or more cursors with unique source IDs, stable
   cursor IDs, and non-negative overlap hours. Cohort case IDs are preserved,
   unique, and not represented as a display string.
4. Evidence coverage reconciles its required/available/missing counts,
   redacted counts cannot exceed available counts, and incomplete evidence
   has an explicit limitation.
5. Overview has exactly one summary for each of the three core axes, no
   duplicate or missing axis, and no Task Effectiveness member. Each
   axis-specific verdict belongs to its axis and
   `positive + negative + insufficientEvidence == totalCases`. Verdict decode
   is owned by `CoreAxisSummary`, decodes the enclosing axis first, and then
   constructs the typed verdict; each axis's `insufficientEvidence` therefore
   round-trips without being coerced to Workflow Conformance.
6. Task Effectiveness remains separate; its five non-negative state counts
   sum to `totalEvaluated`.
7. Every required/published pair in `PublicationCoverage` is equal and checked
   independently: generic workflow, team relationship, P0/P1 finding, and
   P0/P1 chain. A chain never satisfies a missing finding. A full report never
   satisfies any required count. Optional omission/externalization counts are
   non-negative; either count being non-zero requires a valid full report.
8. A case timeline embeds its ordered events and attempts. Its `eventIDs` and
   `attemptIDs` are unique and equal the embedded identities in the same
   order; every embedded record points back to the timeline case. Events have
   source, subject, actor role, timestamp, revision evidence, and evidence
   reference. Attempts have attempt, actor-role, cycle, cause, outcome, and
   evidence identities. Every case/event/evidence/subject/revision reference
   resolves exactly once through the common `SnapshotReferenceCatalog`.
9. Finding fingerprints, case IDs, and event IDs are unique within their
   section. Findings retain explicit subject and responsibility; no consumer
   parses either from the fingerprint. Each finding's case/event/evidence
   arrays are non-empty and unique; every value resolves exactly once through
   the catalog. Feedback-lineage identity equals the lowercase SHA-256 of the
   canonical U+001F-delimited problem/origin/delivery tuple, a supplied merge
   revision is one lowercase 40-hex Git SHA-1 object ID, and
   observation/related-feedback IDs are non-empty and unique.
10. A repeat metric carries the tagged role-specific variant matching
    `actorRole`. Common, cycle-kind, trigger-cause, and role-specific counters
    are all present and non-negative. `repeatCycles <= attemptsTotal`,
    `repeatCases <= attemptsTotal`,
    `sameArtifactRepeatCycles + changedArtifactRepeatCycles == repeatCycles`,
    and each complete cycle/cause breakdown sums to `repeatCycles`. Each
    role's repeat counters do not exceed its corresponding total/round count;
    every primary role-round total is no greater than `attemptsTotal`; zero
    attempts require zero repeat/maximum counters. Supporting subject/event
    arrays are required, unique, and catalog-resolved.
11. A collision observation has a unique observation ID, non-empty entity
    kind/identity, unequal accepted/rejected SHA-256 values, the one locked
    disposition, `parentSnapshotID == payload.snapshotID`, and
    `parentSnapshotSHA256 == payload.contentSHA256`. It cannot mutate or embed
    rejected content.
12. Every artifact has the envelope snapshot ID and artifact-sidecar ID/hash.
    Artifact IDs are unique. Finding chains retain unique catalog-resolved
    finding fingerprints, event IDs, revision evidence, and content SHA-256.
    P0/P1 chains are mandatory; P2/info chains may be optional. Mandatory URLs
    pass the Service-side `URLPolicy` HTTPS+host rule; optional URL strings
    stay untrusted and round-trip without constructing a `URL`.
13. `GrillLinks`, `FullReportReference`, and every externalized entity carry
    the envelope sidecar ID/hash. A full report resolves to exactly one
    catalog `fullReport` artifact with the same ID, hash, URL, kind, and sidecar
    binding, including from an independently decoded overview.
    Externalized references target optional detail only, use reason
    `exceedsInlinePayloadLimit`, use a locked optional-only entity-kind enum,
    have a positive encoded byte count, and bind to that resolved full report
    by ID, hash, URL, and sidecar ID/hash.
14. Types-owned models call no Validation-role symbol. The Service-role
    extension supplies the public protocol witness, invokes the internal
    structural helper followed by `TeamAuditPayloadURLValidator`, and preserves
    the unchanged `CardType.validate`/`SchemaValidator.validateCardPut`
    single-decode structured schema error/fallback contract.

## Exact acceptance matrix

| Surface | Type / invariant proof | Referential / negative proof | Round-trip / public proof | Owning allowlisted test file |
|---|---|---|---|---|
| Registration | `CardType.teamAudit`; count 10→11 | decode/validate dispatches only to `TeamAuditPayload` | raw value is `teamAudit` | `CardTypeDecodeTests.swift`, `EnumRoundtripTests.swift` |
| Size | `teamAudit` is pass-through for authored size | payload richness never downgrades size | data and decoded-payload resolver overloads agree | `SchemaValidatorTests.swift` |
| Envelope/section | part bounds, SHA-256, typed identity/finding/artifact reference catalog, exactly one of eight sections | wrong discriminator, empty/multiple sections and duplicate/unresolved catalog values reject | exact decoded equality for every common field in all eight variants | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Overview mode | typed cohort/case IDs vs typed cursors | baseline-without-cohort, baseline-with-cursor, incremental-with-cohort, incremental-without-cursor reject | baseline and incremental fixtures round-trip | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Axes/effectiveness | locked axis verdicts and reconciled counts | duplicate/missing axis, Task Effectiveness as core, negative or unequal totals reject | all verdicts/raw values round-trip, including three axis-scoped `insufficientEvidence` cases | `EnumRoundtripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Coverage | four independent required/published equalities | unequal finding counts reject even when chain counts match; full report cannot substitute | all count fields survive | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Findings | identity, subject, responsibility, priority/state, evidence | duplicate/unresolved case/event/evidence IDs and missing identity reject through the catalog | exact finding equality plus all six states and `P0/P1/P2/info` round-trip | `CardPayloadRoundTripTests.swift`, `EnumRoundtripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Case timelines | ordered embedded events/attempts with role/cycle identity | missing, duplicate, reordered, or foreign case/event/attempt IDs reject | complete timeline fields survive | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Feedback lineage | typed release channel and effectiveness state; canonical tuple-derived lineage ID | mismatched lineage hash, malformed 40-hex Git SHA-1 merge OID, duplicate/blank observation or related-feedback reference, and unknown channel reject/fallback | exact problem→release→observation equality | `CardPayloadRoundTripTests.swift`, `EnumRoundtripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Repeat metrics | five role-specific variants and common counters | mismatched role tag, primary rounds greater than attempts, empty/duplicate/unresolved subject/event evidence, and negative/inconsistent totals/breakdowns reject | exact equality for every role-specific field, cause, subject, and event | `CardPayloadRoundTripTests.swift`, `EnumRoundtripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Collisions | locked disposition, parent/entity/hash identity | foreign parent, equal/malformed hashes, missing entity reject | accepted/rejected identity fields survive | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Artifacts/grill | unique artifact IDs, typed requirements, grill/sidecar binding, P0/P1 mandatory vs P2/info optional chains | duplicate artifact/chain refs, foreign snapshot/sidecar, unsafe mandatory URL, dangling finding/event/revision refs reject; unsafe optional string remains exact data | exact artifact, grill, priority, event, and revision equality | `CardPayloadRoundTripTests.swift`, `SchemaValidatorTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Full report/externalization | typed catalog artifact, full report, and optional-only externalized collection | overview/artifact full report without exactly one matching kind/ID/hash/URL/sidecar catalog entry, mandatory-kind externalization, invalid reason/count reject | exact reference equality | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| URL policy seam | Service-role extension supplies the `validateInvariants()` witness and delegates to internal `TeamAuditPayloadURLValidator`; `CardType`, `SchemaValidator`, and `URLPolicy` interfaces stay unchanged | Models contain no `URLPolicy`/Validation dependency; unsafe mandatory/full-report/present-lineage URL rejects while unsafe optional artifact/grill strings remain accepted data | structured error field/code and optional raw string survive both `CardType.validate` and production `SchemaValidator` paths | `TeamAuditPayloadValidationTests.swift`, `SchemaValidatorTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Unknown enums | structured decode failure propagates through `CardType`/`SchemaValidator`; rendered fallback is T008-owned | no unknown value is coerced to a known semantic case | explicit `RepeatTriggerCause.unknown` survives; Core error field/code is exact | `CardTypeDecodeTests.swift`, `EnumRoundtripTests.swift`, `SchemaValidatorTests.swift` |
| Public API | every fixture type has a public initializer | no `@testable` import required | construct eight individually valid variants from the external target | `AIDashCorePublicAPITests/PublicInitTests.swift` |
| Wire-size boundary | validation measures the exact received serialized UTF-8 `Data.count` | an otherwise valid mandatory payload of exactly 262,145 bytes rejects with structured field/error; whitespace-only or merely “greater than” fixtures do not satisfy proof | an otherwise valid payload of exactly 262,144 bytes accepts | `SchemaValidatorTests.swift`, `TeamAuditPayloadInvariantTests.swift` |

The byte gate applies to the received final JSON bytes in
`CardType.teamAudit.validate(_:)`, not to an assumed or re-encoded semantic
size. `TeamAuditPayload.validateInvariants()` owns semantic validation; the
CardType/schema-validation path owns the exact wire-byte limit.
