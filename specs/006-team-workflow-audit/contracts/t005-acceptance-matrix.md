# Contract: T005 AIDashCore Acceptance Matrix

This contract is the complete implementation boundary for T005. The task is
one AIDashCore-only PR. It may modify only the nine files listed in the T005
row of `tasks.md`; it does not carry planning, AIDashUI, App, CLI, aidata, or
RepoInfra changes.

## Public type surface

`TeamAuditPayload` is one public `CardPayloadProtocol`, `Codable`, and
`Sendable` model with a common envelope and exactly eight section cases:
`overview`, `findings`, `caseTimelines`, `individualMetrics`,
`feedbackLineage`, `agentRepeatMetrics`, `importObservations`, and
`artifacts`. Exactly one section value is populated and it must match the
section discriminator.

The public nested surface includes, at minimum:

- envelope and overview: `AuditScope`, `AuditMode`, `AuditCohort`,
  `AuditCursor`, `InstructionVersion`, `EvidenceCoverage`, three locked
  axis-specific verdict types, `CoreAxisSummary`,
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
  `FullReportReference`, and `ExternalizedEntityReference`.

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
source data and round-trips unchanged.

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
   `positive + negative + insufficientEvidence == totalCases`.
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
   evidence identities.
9. Finding fingerprints, case IDs, and event IDs are unique within their
   section. Findings retain explicit subject and responsibility; no consumer
   parses either from the fingerprint. Every locally supplied finding/case/
   event reference resolves exactly once.
10. A repeat metric carries the tagged role-specific variant matching
    `actorRole`. Common, cycle-kind, trigger-cause, and role-specific counters
    are all present and non-negative. `repeatCycles <= attemptsTotal`,
    `repeatCases <= attemptsTotal`,
    `sameArtifactRepeatCycles + changedArtifactRepeatCycles == repeatCycles`,
    and each complete cycle/cause breakdown sums to `repeatCycles`. Each
    role's repeat counters do not exceed its corresponding total/round count;
    zero attempts require zero repeat/maximum counters.
11. A collision observation has a unique observation ID, non-empty entity
    kind/identity, unequal accepted/rejected SHA-256 values, the one locked
    disposition, `parentSnapshotID == payload.snapshotID`, and
    `parentSnapshotSHA256 == payload.contentSHA256`. It cannot mutate or embed
    rejected content.
12. Every artifact has the envelope snapshot ID and artifact-sidecar ID/hash.
    Finding chains retain a finding fingerprint, event IDs, revision evidence,
    and content SHA-256. Mandatory URLs pass `URLPolicy`'s HTTPS+host rule;
    optional URL strings stay untrusted and round-trip without constructing a
    `URL`.
13. `GrillLinks`, `FullReportReference`, and every externalized entity carry
    the envelope sidecar ID/hash. A full report resolves to exactly one
    `fullReport` artifact with the same ID, hash, and validated URL.
    Externalized references target optional detail only, use reason
    `exceedsInlinePayloadLimit`, have a positive encoded byte count, and bind
    to that resolved full report.

## Exact acceptance matrix

| Surface | Type / invariant proof | Referential / negative proof | Round-trip / public proof | Owning allowlisted test file |
|---|---|---|---|---|
| Registration | `CardType.teamAudit`; count 10→11 | decode/validate dispatches only to `TeamAuditPayload` | raw value is `teamAudit` | `CardTypeDecodeTests.swift`, `EnumRoundtripTests.swift` |
| Size | `teamAudit` is pass-through for authored size | payload richness never downgrades size | data and decoded-payload resolver overloads agree | `SchemaValidatorTests.swift` |
| Envelope/section | part bounds, SHA-256, exactly one of eight sections | wrong discriminator, empty/multiple sections reject | every common source field survives | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Overview mode | typed cohort/case IDs vs typed cursors | baseline-without-cohort, baseline-with-cursor, incremental-with-cohort, incremental-without-cursor reject | baseline and incremental fixtures round-trip | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Axes/effectiveness | locked axis verdicts and reconciled counts | duplicate/missing axis, Task Effectiveness as core, negative or unequal totals reject | all verdicts/raw values round-trip | `EnumRoundtripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Coverage | four independent required/published equalities | unequal finding counts reject even when chain counts match; full report cannot substitute | all count fields survive | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Findings | identity, subject, responsibility, priority/state, evidence | duplicate/unresolved local IDs and missing identity reject | all six states and `P0/P1/P2/info` round-trip | `CardPayloadRoundTripTests.swift`, `EnumRoundtripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Case timelines | ordered embedded events/attempts with role/cycle identity | missing, duplicate, reordered, or foreign case/event/attempt IDs reject | complete timeline fields survive | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Feedback lineage | typed release channel and effectiveness state | invalid SHA/reference/channel rejects or uses generic fallback | problem→release→observation fields survive | `CardPayloadRoundTripTests.swift`, `EnumRoundtripTests.swift` |
| Repeat metrics | five role-specific variants and common counters | mismatched role tag, negative/inconsistent totals/breakdowns reject | every role-specific field and cause survives | `CardPayloadRoundTripTests.swift`, `EnumRoundtripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Collisions | locked disposition, parent/entity/hash identity | foreign parent, equal/malformed hashes, missing entity reject | accepted/rejected identity fields survive | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Artifacts/grill | typed artifact requirement, grill and sidecar binding | foreign snapshot/sidecar, unsafe mandatory URL, dangling finding/event refs reject; unsafe optional string remains data | direct artifact and grill fields survive | `CardPayloadRoundTripTests.swift`, `SchemaValidatorTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Full report/externalization | typed full report and externalized collection | dangling/mismatched report, mandatory externalization, invalid reason/count reject | reference fields survive | `CardPayloadRoundTripTests.swift`, `TeamAuditPayloadInvariantTests.swift` |
| Unknown enums | structured decode failure reaches existing generic fallback | no unknown value is coerced to a known semantic case | explicit `RepeatTriggerCause.unknown` survives | `CardTypeDecodeTests.swift`, `EnumRoundtripTests.swift`, `SchemaValidatorTests.swift` |
| Public API | every fixture type has a public initializer | no `@testable` import required | construct all eight variants from external target | `AIDashCorePublicAPITests/PublicInitTests.swift` |
| Wire-size boundary | validation measures the received serialized UTF-8 `Data.count` | 262,145-byte mandatory payload rejects with structured field/error; optional externalization remains typed | 262,144-byte valid payload accepts | `SchemaValidatorTests.swift`, `TeamAuditPayloadInvariantTests.swift` |

The byte gate applies to the received final JSON bytes in
`CardType.teamAudit.validate(_:)`, not to an assumed or re-encoded semantic
size. `TeamAuditPayload.validateInvariants()` owns semantic validation; the
CardType/schema-validation path owns the exact wire-byte limit.
