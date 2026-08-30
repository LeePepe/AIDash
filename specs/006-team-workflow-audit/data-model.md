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
| `evidenceCoverage` | EvidenceCoverage | Required/available/missing/redacted evidence counts plus limitations |
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

`AuditCohort` contains a non-empty stable `cohortID` and the source-ordered,
unique stable `caseIDs`; it is never collapsed into a display string. A cohort
with fewer than the normal 20 eligible cases requires an explicit limitation.
`AuditCursor` contains non-empty `sourceID` and `cursorID`, a UTC timestamp,
and non-negative `overlapHours`; source IDs are unique within an overview.

### Audit axes, evidence coverage, and verdicts

`CoreAuditAxis` has exactly three cases: `workflowConformance`,
`workflowFitness`, and `outcomeIntegrity`. `taskEffectiveness` is not a
core-axis case. Findings use a separate `FindingAxis` vocabulary that may also
identify `taskEffectiveness` without allowing it into `axisSummaries`.

The three core axes use independent verdict enums:

- Conformance: `conformant | nonconformant | insufficientEvidence`
- Fitness: `fit | unfit | insufficientEvidence`
- Outcome: `intact | compromised | insufficientEvidence`

Each core summary's positive + negative + insufficient-evidence counts equals
`totalCases`. Task Effectiveness is never stored as a core verdict; it has
`effective`, `ineffective`, `regressed`, `pending`, and
`insufficientEvidence` counts that reconcile to its evaluated total.

`EvidenceCoverage` carries `requiredEvidenceCount`, `availableEvidenceCount`,
`missingEvidenceCount`, `redactedEvidenceCount`, and `limitations`. All counts
are non-negative,
`availableEvidenceCount + missingEvidenceCount == requiredEvidenceCount`, and
`redactedEvidenceCount <= availableEvidenceCount`. Missing or redacted
evidence requires a limitation and never borrows a verdict from another axis.

### AuditFinding

| Field | Type | Rules |
|---|---|---|
| `fingerprint` | String | Stable, non-empty decision target |
| `subjectID` | String | Explicit stable source subject; never parsed from fingerprint |
| `responsibilityLayer` | String | Explicit source responsibility layer; never parsed from fingerprint |
| `axis` | FindingAxis | Independent classification; may identify Task Effectiveness without entering the core summary set |
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

### AuditCaseTimeline, AuditEvent, AuditAttempt, and IndividualMetric

- `AuditCaseTimeline` carries one stable case ID, its ordered `eventIDs` and
  `attemptIDs`, the complete embedded event/attempt values, and case-level
  limitations. Both ID arrays are unique and equal the embedded identities in
  the same order; every embedded value points back to the containing case.
- `AuditEvent` preserves exactly: event ID, case ID, source, subject ID, actor
  role, free-form kind, timestamp, revision SHA, and evidence reference.
- `AuditAttempt` preserves stable attempt, case, actor-role, and cycle
  identities, actor role, trigger cause, outcome, and evidence references.
  Actor role is locked to Planner Lead, Team Lead, Fullstack Engineer, AI
  Reviewer, or PR Manager.
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

The tagged case must match `actorRole`. Every common, breakdown, and
role-specific value is present and non-negative. `repeatCycles` and
`repeatCases` do not exceed `attemptsTotal`;
`sameArtifactRepeatCycles + changedArtifactRepeatCycles == repeatCycles`; the
complete cycle-kind and trigger-cause maps each sum to `repeatCycles`; and
each role-specific repeat counter does not exceed its corresponding round/
attempt total. Zero attempts require zero repeat and maximum-cycle values.

### ImportCollisionObservation

An identity/hash conflict is observed without changing or annotating the
accepted immutable fact:

| Field | Type | Rules |
|---|---|---|
| `observationID` | String | `SHA256(sourceStableID, parentSnapshotID, stableIdentity, acceptedSHA256, rejectedSHA256, observedAt)` minted once at L1 and preserved on re-normalize/merge |
| `parentSnapshotID` | String | Explicit accepted snapshot parent |
| `parentSnapshotSHA256` | String | Immutable content hash of accepted snapshot parent |
| `observedAt` | Date | UTC |
| `source` | String | Portable source identity, never a local path |
| `entityKind` | String | Snapshot or child-fact kind |
| `stableIdentity` | String | Colliding immutable identity |
| `acceptedSHA256` | String | Hash of retained content |
| `rejectedSHA256` | String | Hash of rejected content; rejected body is not stored |
| `disposition` | ImportObservationDisposition | Exactly `rejectedIdentityHashCollision` |
| `limitation` | String | Redacted explanation surfaced to the Owner |

L3 merges `(parentSnapshotID, observationID)` idempotently. Distinct
observation IDs remain append-only history. The parent ID/hash is mandatory for
snapshot- and child-fact collisions; no collision row updates the accepted
snapshot.

### TeamAuditIdentityIndex

The AidataL1L2 collector maintains a derived SQLite cache at
`raw_source_dir("team_audit_snapshot") / ".identity-index.sqlite"` (an
injected `tmp_path` in tests) so immutable-identity decisions survive process
restarts without rescanning every raw shard on the healthy path.

| Indexed value | Key / rule |
|---|---|
| Accepted immutable entity | `(entityKind, stableIdentity)` → first accepted SHA-256, parent snapshot ID/hash |
| Accepted sidecar | `(artifactSidecar, sidecarID)` → exact accepted sidecar-byte SHA-256, parent snapshot ID/hash |
| Collision observation | `(parentSnapshotID, observationID)` → complete body-free observation fields |
| Recovery marker | Raw-history fingerprint/checkpoint used only to detect stale cache state; never acceptance authority |

The index stores no snapshot, child, sidecar, raw-log, or rejected body. Raw
records and body-free observations remain authoritative. `open(index_path,
raw_history)` atomically rebuilds a missing, corrupt, stale, or unverifiable
cache from that history. A collector appends accepted raw records or body-free
observations before `commit(import_plan)` updates the cache transaction; therefore
a crash can leave raw ahead of the cache but never make an index-only identity
accepted. Index-ahead rows unsupported by raw history are discarded.

Classification is independent for the snapshot, every stable child kind, and
the sidecar. A snapshot replay cannot hide a changed sidecar or child hash.
Overlap-event deduplication uses the event stable identity through the same
index. The full restart/collision proof is
`contracts/t002-acceptance-matrix.md`.

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
| `requirement` | ArtifactRequirement | `mandatory` or `optional`; controls publication rejection versus non-actionable degradation |
| `sidecarID` / `sidecarSHA256` | String | Must equal the payload envelope and owning sidecar |

Every P0/P1 finding requires a direct `findingEventChain` entry. Each snapshot
requires one generic workflow and every applicable team/repository relationship
entry. Missing, invalid, or oversized mandatory entries reject publication;
they are never converted into optional limitations or one full-report link.

### ArtifactSidecar, grill links, and publication coverage

`ArtifactSidecar` contains:

| Field | Type | Rules |
|---|---|---|
| `sidecarID` | String | Stable `snapshotID:artifact-sidecar:v1` identity |
| `contentSHA256` | String | Importer-computed SHA-256 of the exact immutable `artifacts.json` bytes; normalized field, not self-declared inside the raw file |
| `schemaVersion` | Int | Exactly 1 |
| `snapshotID` | String | Must match the snapshot parent |
| `artifacts` | [ArtifactManifestEntry] | Every entry binds back to this sidecar and snapshot |
| `grillMeURL` / `grillWithDocsURL` | String? | Optional untrusted raw sidecar strings |

Sidecar identity/hash is preserved through normalized rows, warehouse facts,
L4 bundles, every card's common provenance envelope, and collision detection.
Artifact and grill facts carry `sidecarID`/`sidecarSHA256`; grill URLs are never
inferred from an artifact title.
The normalized `ArtifactSidecar.contentSHA256` maps without transformation to
card-envelope `artifactSidecarSHA256`.

The Core payload normalizes the two raw strings into a typed `GrillLinks`
value that also carries the envelope `sidecarID`/`sidecarSHA256`; the raw
sidecar file does not self-declare its computed hash.

`FullReportReference` is explicitly typed as `artifactID`, `title`,
`contentSHA256`, untrusted `url`, `sidecarID`, and `sidecarSHA256`. It may
externalize optional detail only. Its ID, hash, URL, and sidecar binding must
resolve exactly to one sidecar entry whose kind is `fullReport`; otherwise the
reference is invalid.

L4 emits `RequiredPublicationInputs`: the required entities and counts for the
generic workflow, team/repository relationships, and P0/P1 findings/chains. It
contains no `published*`, omitted, or externalized results.

L5 computes `PublicationCoverage` only after final card packing and budget
selection; it travels in every overview:

| Field | Type |
|---|---|
| `requiredGenericWorkflowCount` / `publishedGenericWorkflowCount` | Int |
| `requiredTeamRelationshipCount` / `publishedTeamRelationshipCount` | Int |
| `requiredP0P1FindingCount` / `publishedP0P1FindingCount` | Int |
| `requiredP0P1ChainCount` / `publishedP0P1ChainCount` | Int |
| `omittedOptionalEntityCount` / `externalizedEntityCount` | Int |
| `fullReport` | FullReportReference? |

Each required/published pair must be equal for publication to succeed. A full
report never satisfies a missing required count. The finding pair counts
complete P0/P1 `AuditFinding` entities independently from their required event
chain links; publishing a chain never increments the finding count.

`ExternalizedEntityReference` contains `entityKind`, `stableID`,
`encodedByteCount`, fixed reason `exceedsInlinePayloadLimit`, sidecar ID/hash,
and a `FullReportReference`. The byte count is positive, every sidecar value
matches the payload envelope, and it can replace only optional detail.

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
| `artifactSidecarID` | String | Stable immutable sidecar identity |
| `artifactSidecarSHA256` | String | Exact sidecar content hash retained as payload provenance |

`TeamAuditSection` is
`overview | findings | caseTimelines | individualMetrics | feedbackLineage |
agentRepeatMetrics | importObservations | artifacts`.
The payload contains only the collection selected by `section`; all unrelated
collections must be empty. Every final serialized UTF-8 payload, including its
envelope, must be at most 262,144 bytes. The exact gate measures the received
JSON `Data.count` in `CardType.teamAudit.validate(_:)`; semantic re-encoding is
not a substitute for wire-byte validation.

### Section content

- `overview`: a typed cohort with case IDs or typed cursors, instruction
  versions, typed evidence coverage, exactly three core summaries with
  axis-specific verdicts, separate Task Effectiveness, provenance,
  `PublicationCoverage`, collision count/limitations, and limitations.
- `findings`: one or more complete `AuditFinding` values. This is the only
  section that exposes decision controls.
- `caseTimelines`: bounded `AuditCaseTimeline` values with their ordered,
  embedded, referentially complete events and attempts.
- `individualMetrics`: bounded descriptive metrics.
- `feedbackLineage`: complete typed problem → delivery → release → observation
  chains and pending/effectiveness state.
- `agentRepeatMetrics`: complete per-role common counts, cycle/cause maps,
  role-specific counters, and supporting subject/event IDs.
- `importObservations`: independently keyed collision observations tied to the
  explicit accepted parent snapshot ID/hash without changing its content.
- `artifacts`: one typed `ArtifactSection` containing direct artifact entries,
  typed full-report/externalized optional references, and typed optional grill
  links from `ArtifactSidecar`.

All SHA-256 values are exactly 64 lowercase hexadecimal characters. Collision
parents match the envelope snapshot ID/hash; artifacts, grill links, full
reports, and externalized references match the envelope sidecar ID/hash.
Locally supplied case/event/attempt, finding, artifact, and full-report
references resolve exactly once. The complete Core acceptance and negative
fixture matrix is normative in `contracts/t005-acceptance-matrix.md`.

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
- `fact_team_audit_finding`: one row per snapshot + finding fingerprint,
  retaining explicit subject ID and responsibility layer.
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
- `fact_team_audit_import_collision_observation`: one row per parent snapshot + independent observation ID, retaining parent snapshot hash.
- `fact_team_audit_artifact_sidecar`: one row per snapshot + sidecar identity/content hash.
- `fact_team_audit_artifact`: one row per snapshot + sidecar + artifact identity/hash.
- `fact_team_audit_grill_link`: one row per snapshot + sidecar + `grillMe|grillWithDocs`, retaining sidecar hash.

Child facts reference the accepted snapshot hash. L3 never updates a row with
a different hash. L4 queries are read-only and expose their grain explicitly.
