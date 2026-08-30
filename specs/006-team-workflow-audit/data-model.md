# Data Model: On-Demand Team Workflow Audit

## Stable identity rules

- All timestamps are UTC ISO-8601 values.
- `snapshotID`, source record IDs, case IDs, event IDs, attempt IDs, finding
  fingerprints, artifact IDs, delivery/release/observation IDs, and decision
  event IDs are stable source identities, not display labels.
- Every imported immutable object carries a content SHA-256. A repeated
  `(identity, hash)` is idempotent; a repeated identity with a different hash
  is a collision and cannot replace the accepted object.
- Generated card IDs are deterministic from
  `(snapshotID, section, partIndex, stable subject range)` so a republish does
  not create duplicate cards.

## Import bundle

### TeamAuditSnapshot

| Field | Type | Rules |
|---|---|---|
| `snapshotID` | String | Non-empty stable identity |
| `capturedAt` | Date | UTC |
| `scope` | AuditScope | Owner label, project reference, repository reference; redacted and portable |
| `mode` | AuditMode | `baseline` or `incremental` |
| `instructionVersions` | [InstructionVersion] | Each has source identity, update time, SHA-256 |
| `cohort` | AuditCohort? | Required for baseline, absent for incremental |
| `cursors` | [AuditCursor] | Required and non-empty for incremental, absent for baseline |
| `axisSummaries` | [CoreAxisSummary] | Exactly one each for Conformance, Fitness, Outcome |
| `taskEffectiveness` | TaskEffectivenessSummary | Separate from core summaries |
| `cases` | [AuditCase] | Stable, redacted case facts |
| `events` | [AuditEvent] | Stable evidence references; no raw log bodies |
| `attempts` | [AuditAttempt] | Actor role/cycle/outcome facts |
| `individualMetrics` | [IndividualMetric] | Descriptive metrics with denominator and limitation |
| `feedbackLineage` | [FeedbackLineage] | Problem → delivery → release → observation identities |
| `agentRepeatMetrics` | [AgentRepeatMetric] | Complete common, cycle/cause, role-specific, subject, and event metrics per actor role |
| `findings` | [AuditFinding] | Stable fingerprint and canonical state |
| `limitations` | [String] | Required when evidence or cohort is incomplete |

### AuditMode and cohort/cursor invariants

- `baseline`: fixed cohort required; cursor list empty.
- `incremental`: cohort absent; one cursor per source, each with timestamp,
  stable ID, and non-negative overlap hours.
- Incremental overlap replay deduplicates events by stable source identity; it
  does not modify the baseline cohort.

### AuditAxis and verdicts

`AuditAxis` has four cases:

- `workflowConformance`
- `workflowFitness`
- `outcomeIntegrity`
- `taskEffectiveness`

The first three are core axes with independent verdict enums:

- Conformance: `conformant | nonconformant | insufficientEvidence`
- Fitness: `fit | unfit | insufficientEvidence`
- Outcome: `intact | compromised | insufficientEvidence`

Each core summary's positive + negative + insufficient-evidence counts equals
`totalCases`. Task Effectiveness is never stored as a core verdict; it has
`effective`, `ineffective`, `regressed`, `pending`, and
`insufficientEvidence` counts that reconcile to its evaluated total.

### AuditFinding

| Field | Type | Rules |
|---|---|---|
| `fingerprint` | String | Stable, non-empty decision target |
| `axis` | AuditAxis | Independent classification |
| `priority` | FindingPriority | `P0 | P1 | P2 | info` |
| `verdict` | String | Preserved source verdict; display only when not a locked core verdict |
| `state` | FindingState | Exactly one locked lifecycle case |
| `summary` | String | Redacted display text |
| `caseIDs` | [String] | Stable case references |
| `eventIDs` | [String] | Stable evidence references |
| `evidenceRefs` | [String] | Hash/reference only, never raw logs |
| `remediationOwner` | RemediationOwner | `projectDevTeam | separateExecutionAgent` |

`FindingState` is exactly:
`open | acknowledged | approvedForRemediation | resolved | regressed | superseded`.

### AuditCase, AuditEvent, AuditAttempt, and IndividualMetric

- `AuditCase` references an ordered set of event/attempt identities and carries
  case-level limitations.
- `AuditEvent` preserves exactly: event ID, source, subject ID, actor role,
  free-form kind, timestamp, revision SHA, and evidence reference.
- `AuditAttempt` preserves stable attempt/role/cycle identities, actor role,
  trigger cause, outcome, and evidence references. Actor role is locked to
  Planner Lead, Team Lead, Fullstack Engineer, AI Reviewer, or PR Manager.
- `IndividualMetric` always includes metric definition, numerator,
  denominator, observation window, and limitation; it is descriptive and must
  not be presented as causal or as a personnel score.

### FeedbackLineage

`FeedbackLineage` preserves the source contract without reducing pending or
release state:

| Field | Type | Rules |
|---|---|---|
| `lineageID` | String | `SHA256(problemFingerprint, originIssueID, deliveryIssueID)` |
| `problemFingerprint` | String | Stable problem identity |
| `originIssueID` | String | Stable feedback-origin identity |
| `deliveryIssueID` | String | Stable delivery identity |
| `prURL` | String? | Untrusted source value; display policy applies |
| `mergeSHA` | String? | Exact delivery revision when known |
| `releaseChannel` | ReleaseChannel? | `testflight | appStore | production | internal` |
| `firstVersion` / `firstBuild` | String? | First containing release identity |
| `availableAt` | Date? | UTC availability time |
| `observationEventIDs` | [String] | Stable supporting observation identities |
| `relatedFeedbackIssueIDs` | [String] | Stable related-feedback identities |
| `taskEffectiveness` | TaskEffectivenessState | `effective | ineffective | regressed | pendingDelivery | pendingRelease | pendingObservation | insufficientEvidence` |

### AgentRepeatMetric

Each actor role has one complete metric record; roles are never combined into
an efficiency score.

| Field | Type | Rules |
|---|---|---|
| `actorRole` | ActorRole | One of the five locked workflow roles |
| `attemptsTotal` | Int | Non-negative |
| `repeatCycles` | Int | Non-negative, no greater than attempts |
| `repeatCases` | Int | Non-negative |
| `sameArtifactRepeatCycles` | Int | Non-negative |
| `changedArtifactRepeatCycles` | Int | Non-negative |
| `maxCyclesPerCase` | Int | Non-negative |
| `byCycleKind` | [String: Int] | All source cycle-kind counts preserved |
| `byTriggerCause` | [RepeatTriggerCause: Int] | All source cause counts preserved |
| `roleSpecific` | RoleSpecificRepeatMetrics | Tagged case must match `actorRole` |
| `subjectIDs` | [String] | Stable subjects supporting the counts |
| `eventIDs` | [String] | Stable evidence events supporting the counts |

`RepeatTriggerCause` is exactly `planningFinding | reviewFinding |
ciCodeFailure | ciInfrastructureFailure | shaOrMetadataMismatch |
permissionOrCredential | hardwareOrEnvironment | ownerDecision |
workflowConfiguration | unknown`.

`RoleSpecificRepeatMetrics` is a tagged union with these integer fields:

- `plannerLead`: `planningRevisionRounds`, `planningReviewRepeatCycles`,
  `planningSameRevisionReReviews`, `planningHandoffRepeatCycles`.
- `teamLead`: `recoveryDispatchRounds`, `recoveryDispatchRepeatCycles`,
  `sameRecoveryKeyRedispatches`, `ownerEscalationRepeatCycles`.
- `fullstackEngineer`: `implementationRevisionRounds`, `reviewFixRounds`,
  `ciRepairRounds`, `sameReviewFindingRepeats`, `sameCIFailureRepeats`,
  `handoffRepairRounds`.
- `aiReviewer`: `reviewRounds`, `reviewRepeatCycles`, `sameSHAReReviews`,
  `changedSHAReReviews`, `inconclusiveReviewRounds`,
  `changesRequestedRounds`.
- `prManager`: `ciSupervisionRounds`, `ciSupervisionRepeatCycles`,
  `sameSHACIReruns`, `shippingAttemptRounds`,
  `shippingAttemptRepeatCycles`, `implementationReturnRounds`.

### ImportCollisionObservation

An identity/hash conflict is observed without changing or annotating the
accepted immutable fact:

| Field | Type | Rules |
|---|---|---|
| `observationID` | String | `SHA256(sourceStableID, stableIdentity, acceptedSHA256, rejectedSHA256, observedAt)` minted once at L1 and preserved on re-normalize/merge |
| `observedAt` | Date | UTC |
| `source` | String | Portable source identity, never a local path |
| `entityKind` | String | Snapshot or child-fact kind |
| `stableIdentity` | String | Colliding immutable identity |
| `acceptedSHA256` | String | Hash of retained content |
| `rejectedSHA256` | String | Hash of rejected content; rejected body is not stored |
| `disposition` | ImportObservationDisposition | Exactly `rejectedIdentityHashCollision` |
| `limitation` | String | Redacted explanation surfaced to the Owner |

L3 merges `observationID` idempotently. Distinct observation IDs remain
append-only history. No collision row updates the accepted snapshot.

### ArtifactManifestEntry

| Field | Type | Rules |
|---|---|---|
| `artifactID` | String | Stable within snapshot |
| `snapshotID` | String | Required parent |
| `kind` | ArtifactKind | `genericWorkflow | teamRelationship | findingEventChain | fullReport` |
| `title` | String | Redacted display label |
| `findingFingerprint` | String? | Required for finding event chains |
| `caseID` | String? | Optional case binding |
| `eventIDs` | [String] | Evidence relationship |
| `revisionEvidence` | [String] | Verified revision/blob/line references |
| `contentSHA256` | String | Generated artifact hash |
| `url` | String? | Mandatory artifacts require a present HTTPS+host value or publication rejects; optional invalid values remain non-actionable text under central URL policy |

Every P0/P1 finding requires a direct `findingEventChain` entry. Each snapshot
requires one generic workflow and every applicable team/repository relationship
entry. Missing, invalid, or oversized mandatory entries reject publication;
they are never converted into optional limitations or one full-report link.

### ArtifactSidecar, grill links, and publication coverage

`ArtifactSidecar` contains `schemaVersion=1`, matching `snapshotID`,
`artifacts: [ArtifactManifestEntry]`, and optional untrusted `grillMeURL` and
`grillWithDocsURL` strings. Grill URLs have their own warehouse grain and are
never inferred from an artifact title.

`FullReportReference` is explicitly typed as `artifactID`, `title`,
`contentSHA256`, and untrusted `url`. It may externalize optional detail only.
Its `artifactID`, hash, and URL must resolve exactly to one sidecar entry whose
kind is `fullReport`; otherwise the reference is invalid.

`PublicationCoverage` travels in every overview:

| Field | Type |
|---|---|
| `requiredGenericWorkflowCount` / `publishedGenericWorkflowCount` | Int |
| `requiredTeamRelationshipCount` / `publishedTeamRelationshipCount` | Int |
| `requiredP0P1ChainCount` / `publishedP0P1ChainCount` | Int |
| `omittedOptionalEntityCount` / `externalizedEntityCount` | Int |
| `fullReport` | FullReportReference? |

Each required/published pair must be equal for publication to succeed. A full
report never satisfies a missing required count.

`ExternalizedEntityReference` contains `entityKind`, `stableID`,
`encodedByteCount`, fixed reason `exceedsInlinePayloadLimit`, and a
`FullReportReference`. It can replace only optional detail.

## Card contract

### TeamAuditPayload common envelope

| Field | Type | Rules |
|---|---|---|
| `snapshotID` | String | Stable snapshot identity |
| `capturedAt` | Date | UTC |
| `scope` | AuditScope | Repeated on every part for standalone provenance |
| `mode` | AuditMode | Baseline or incremental |
| `section` | TeamAuditSection | Selects one content collection |
| `partIndex` | Int | Zero-based, non-negative |
| `partCount` | Int | Positive; `partIndex < partCount` |
| `contentSHA256` | String | Hash of the accepted immutable snapshot/bundle |

`TeamAuditSection` is
`overview | findings | caseTimelines | individualMetrics | feedbackLineage |
agentRepeatMetrics | importObservations | artifacts`.
The payload contains only the collection selected by `section`; all unrelated
collections must be empty. Every final serialized UTF-8 payload, including its
envelope, must be at most 262,144 bytes.

### Section content

- `overview`: cohort or cursors, instruction versions, evidence coverage,
  exactly three core summaries, separate Task Effectiveness, provenance,
  `PublicationCoverage`, collision count/limitations, and limitations.
- `findings`: one or more complete `AuditFinding` values. This is the only
  section that exposes decision controls.
- `caseTimelines`: bounded `AuditCase` values plus their referenced events and
  attempts.
- `individualMetrics`: bounded descriptive metrics.
- `feedbackLineage`: complete typed problem → delivery → release → observation
  chains and pending/effectiveness state.
- `agentRepeatMetrics`: complete per-role common counts, cycle/cause maps,
  role-specific counters, and supporting subject/event IDs.
- `importObservations`: independently keyed collision observations tied to the
  accepted snapshot identity without changing its hash.
- `artifacts`: direct artifact entries, typed full-report/externalized optional
  references, and optional grill URLs from `ArtifactSidecar`.

## OwnerDecisionEvent

Owner decisions reuse the existing `UserEvent` model:

| UserEvent field | Value |
|---|---|
| `action` | `auditFindingAcknowledged` or `auditFindingRemediationApproved` |
| `cardId` | Deterministic ID of the findings card shown to the Owner |
| `itemRef` | Stable finding fingerprint |
| `cardType` | `teamAudit` |
| `id`, `timestamp`, `device` | Existing append-only event fields |

The App writer suppresses a repeated local event with the same
`(cardId, itemRef, action)`. Cross-device duplicates remain immutable history;
displayed receipt sets collapse by `(itemRef, action)`. Neither action mutates
`AuditFinding.state`. Only a later imported snapshot may publish a new
canonical state.

## Warehouse grains

- `fact_team_audit_snapshot`: one row per snapshot identity.
- `fact_team_audit_axis_summary`: one row per snapshot + axis.
- `fact_team_audit_case`: one row per snapshot + case identity.
- `fact_team_audit_event`: one row per snapshot + source event identity.
- `fact_team_audit_attempt`: one row per snapshot + attempt identity.
- `fact_team_audit_finding`: one row per snapshot + finding fingerprint.
- `fact_team_audit_individual_metric`: one row per snapshot + metric identity.
- `fact_team_audit_feedback_lineage`: one row per snapshot + lineage identity.
- `bridge_team_audit_lineage_observation`: one row per snapshot + lineage + observation event ID.
- `bridge_team_audit_lineage_related_feedback`: one row per snapshot + lineage + related issue ID.
- `fact_team_audit_agent_repeat_metric`: one row per snapshot + actor role.
- `fact_team_audit_repeat_cycle_kind`: one row per snapshot + actor role + cycle kind.
- `fact_team_audit_repeat_trigger_cause`: one row per snapshot + actor role + trigger cause.
- `fact_team_audit_repeat_role_value`: one row per snapshot + actor role + allowed role-specific key.
- `bridge_team_audit_repeat_subject`: one row per snapshot + actor role + subject ID.
- `bridge_team_audit_repeat_event`: one row per snapshot + actor role + event ID.
- `fact_team_audit_import_collision_observation`: one row per independent observation ID.
- `fact_team_audit_artifact`: one row per snapshot + artifact identity.
- `fact_team_audit_grill_link`: one row per snapshot + `grillMe|grillWithDocs`.

Child facts reference the accepted snapshot hash. L3 never updates a row with
a different hash. L4 queries are read-only and expose their grain explicitly.
