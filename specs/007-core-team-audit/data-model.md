# Data Model: Core Team Audit Contract

This document fixes the public Codable surface. Field names, optionality, raw
values, and equations are normative; a different wire shape does not satisfy
FR-003 or FR-008.

## Common envelope and section representation

TeamAuditPayload is public, Codable, Equatable, Sendable, and implements the
existing CardPayloadProtocol through its Validation-role extension.

| Field | Type | Wire presence and rule |
|---|---|---|
| snapshotID | String | Required, trimmed, non-empty |
| capturedAt | Date | Required UTC timestamp |
| scope | AuditScope | Required |
| mode | AuditMode | Required: baseline or incremental |
| section | TeamAuditSection | Required, one of eight locked values |
| partIndex | Int | Required; 0 <= partIndex < partCount |
| partCount | Int | Required and greater than zero |
| contentSHA256 | String | Required; exactly 64 lowercase hexadecimal characters |
| artifactSidecarID | String | Required, trimmed, non-empty |
| artifactSidecarSHA256 | String | Required; exactly 64 lowercase hexadecimal characters |
| referenceCatalog | SnapshotReferenceCatalog | Required |
| overview | AuditOverview? | Present and non-null only for section overview |
| findings | [AuditFinding]? | Present, non-null, and non-empty only for section findings |
| caseTimelines | [AuditCaseTimeline]? | Present, non-null, and non-empty only for section caseTimelines |
| individualMetrics | [IndividualMetric]? | Present, non-null, and non-empty only for section individualMetrics |
| feedbackLineage | [FeedbackLineage]? | Present, non-null, and non-empty only for section feedbackLineage |
| agentRepeatMetrics | [AgentRepeatMetric]? | Present, non-null, and non-empty only for section agentRepeatMetrics |
| importObservations | [ImportCollisionObservation]? | Present, non-null, and non-empty only for section importObservations |
| artifacts | ArtifactSection? | Present and non-null only for section artifacts |

The selected body is the only body key encoded. The other seven body keys are
absent, not null and not empty placeholders. TeamAuditSection raw values are
exactly overview, findings, caseTimelines, individualMetrics, feedbackLineage,
agentRepeatMetrics, importObservations, and artifacts.

AuditScope has required String fields owner, projectID, and repository. Each is
trimmed and non-empty. These are portable references, not local paths or
account-specific fixtures.

## Reference catalog

SnapshotReferenceCatalog has these required arrays:

| Field | Element type | Identity rule |
|---|---|---|
| caseIDs | String | Trimmed, non-empty, unique |
| eventIDs | String | Trimmed, non-empty, unique |
| evidenceRefs | String | Trimmed, non-empty, unique |
| subjectIDs | String | Trimmed, non-empty, unique |
| revisionEvidenceRefs | String | Trimmed, non-empty, unique |
| findings | FindingReference | Unique fingerprint |
| artifacts | ArtifactReference | Unique artifactID |

FindingReference has required fingerprint and priority fields. ArtifactReference
has required artifactID, kind, contentSHA256, url, sidecarID, and
sidecarSHA256 fields; url is optional. Catalog entries contain only identity
and immutable binding data. Every reference used by the selected section
resolves exactly once; duplicates reject even if all other fields are equal.

## Overview, modes, and counts

AuditOverview has the following fixed surface:

| Field | Type | Optionality / rule |
|---|---|---|
| cohort | AuditCohort? | Required non-null for baseline; absent for incremental |
| cursors | [AuditCursor] | Empty for baseline; non-empty for incremental |
| instructionVersions | [InstructionVersion] | Required; sourceID values unique |
| evidenceCoverage | EvidenceCoverage | Required |
| axisSummaries | [CoreAxisSummary] | Exactly one summary for each core axis |
| taskEffectiveness | TaskEffectivenessSummary | Required and separate from core axes |
| publicationCoverage | PublicationCoverage | Required |
| collisionCount | Int | Required and non-negative |
| limitations | [String] | Required; each value trimmed and non-empty |

AuditCohort has cohortID and caseIDs. Both are required; the ID is non-empty,
and caseIDs is source-ordered, non-empty, and unique. Each case resolves
through the catalog.

AuditCursor has required sourceID, cursorID, timestamp, and overlapHours.
Identifiers are non-empty, sourceID is unique within an overview, and
overlapHours is non-negative.

InstructionVersion has required sourceID, updatedAt, and sha256. sourceID is
non-empty and sha256 is 64 lowercase hexadecimal characters.

EvidenceCoverage has required integer fields requiredEvidenceCount,
availableEvidenceCount, missingEvidenceCount, and redactedEvidenceCount, plus
required limitations. All counts are non-negative and:

    availableEvidenceCount + missingEvidenceCount == requiredEvidenceCount
    redactedEvidenceCount <= availableEvidenceCount

Missing or redacted evidence requires at least one limitation.

CoreAuditAxis raw values are exactly workflowConformance, workflowFitness, and
outcomeIntegrity. The independent verdict vocabularies are:

- ConformanceVerdict: conformant, nonconformant, insufficientEvidence
- FitnessVerdict: fit, unfit, insufficientEvidence
- OutcomeVerdict: intact, compromised, insufficientEvidence

CoreAxisSummary encodes required fields axis, verdict, totalCases, positive,
negative, and insufficientEvidence. It decodes axis first, then decodes
verdict using only that axis vocabulary. CoreAxisVerdict is the public typed
union of the three verdict types and has no context-free decoder. All counts
are non-negative and:

    positive + negative + insufficientEvidence == totalCases

TaskEffectivenessSummary has required non-negative fields totalEvaluated,
effective, ineffective, regressed, pending, and insufficientEvidence, with:

    effective + ineffective + regressed + pending
      + insufficientEvidence == totalEvaluated

PublicationCoverage has required non-negative integer fields:
requiredGenericWorkflowCount, publishedGenericWorkflowCount,
requiredTeamRelationshipCount, publishedTeamRelationshipCount,
requiredP0P1FindingCount, publishedP0P1FindingCount,
requiredP0P1ChainCount, publishedP0P1ChainCount,
omittedOptionalEntityCount, and externalizedEntityCount. It has optional
fullReport. The four required/published pairs are independently equal. A chain
does not satisfy a finding, and a full report satisfies none of the four
pairs. A non-zero omitted or externalized count requires fullReport.

## Findings

FindingAxis raw values are workflowConformance, workflowFitness,
outcomeIntegrity, and taskEffectiveness. FindingPriority is exactly P0, P1,
P2, or info. FindingState is exactly open, acknowledged,
approvedForRemediation, resolved, regressed, or superseded.
RemediationOwner is exactly projectDevTeam or separateExecutionAgent.

AuditFinding has required fields fingerprint, subjectID,
responsibilityLayer, axis, priority, verdict, state, summary, caseIDs,
eventIDs, evidenceRefs, and remediationOwner. Required string values are
trimmed and non-empty. Fingerprints are unique within the section and resolve
to a catalog FindingReference with the same priority. caseIDs, eventIDs, and
evidenceRefs are each non-empty and unique, and every member resolves once
through the corresponding catalog array. subjectID resolves through subjectIDs.

## Timelines, events, attempts, and individual metrics

AuditCaseTimeline has required caseID, eventIDs, attemptIDs, events, attempts,
and limitations. caseID resolves once. Both identity arrays are unique and
equal the embedded identities in the same order. Every embedded event and
attempt has the same caseID as the timeline.

AuditEvent has required eventID, caseID, source, subjectID, actorRole, kind,
timestamp, revisionSHA, and evidenceRef. Identity/display strings are trimmed
and non-empty. eventID, caseID, subjectID, revisionSHA, and evidenceRef resolve
through their corresponding catalog arrays.

AuditAttempt has required attemptID, caseID, actorRole, cycleID, triggerCause,
outcome, and evidenceRefs. All identity/display strings are trimmed and
non-empty; evidenceRefs is non-empty, unique, and catalog-resolved. attemptID
values are unique within the timeline.

ActorRole raw values are plannerLead, teamLead, fullstackEngineer, aiReviewer,
and prManager. RepeatTriggerCause raw values are planningFinding,
reviewFinding, ciCodeFailure, ciInfrastructureFailure, shaOrMetadataMismatch,
permissionOrCredential, hardwareOrEnvironment, ownerDecision,
workflowConfiguration, and unknown. The explicit unknown case is valid source
data; other unknown raw values fail decoding.

IndividualMetric has required metricID, subjectID, metricDefinition, numerator,
denominator, observationWindow, and limitation. String fields are trimmed and
non-empty; metricID values are unique in the section; subjectID resolves once;
numerator and denominator are non-negative and denominator is greater than
zero. The model is descriptive and defines no personnel score or causal claim.

## Feedback lineage

FeedbackLineage has this fixed public surface:

| Field | Type | Optionality / rule |
|---|---|---|
| lineageID | String | Required canonical lowercase SHA-256 |
| problemFingerprint | String | Required, trimmed, non-empty |
| originIssueID | String | Required, trimmed, non-empty |
| deliveryIssueID | String | Required, trimmed, non-empty |
| prURL | String? | Optional opaque string; present value validated by URLPolicy |
| mergeSHA | String? | Optional; when present exactly 40 lowercase hex |
| releaseChannel | ReleaseChannel? | Optional |
| firstVersion | String? | Optional; present value trimmed and non-empty |
| firstBuild | String? | Optional; present value trimmed and non-empty |
| availableAt | Date? | Optional UTC timestamp |
| observationEventIDs | [String] | Required, non-empty, unique, catalog-resolved |
| relatedFeedbackIssueIDs | [String] | Required, non-empty, unique |
| taskEffectiveness | TaskEffectivenessState | Required |

ReleaseChannel raw values are testflight, appStore, production, and internal.
TaskEffectivenessState raw values are effective, ineffective, regressed,
pendingDelivery, pendingRelease, pendingObservation, and
insufficientEvidence.

The canonical preimage is the UTF-8 bytes of the trimmed tuple:

    problemFingerprint + U+001F + originIssueID + U+001F + deliveryIssueID

lineageID equals the lowercase SHA-256 of those exact bytes. Observation IDs
resolve through eventIDs. Lineage IDs are unique within the section.

## Per-role repeat metrics

AgentRepeatMetric has required actorRole, attemptsTotal, repeatCycles,
repeatCases, sameArtifactRepeatCycles, changedArtifactRepeatCycles,
maxCyclesPerCase, byCycleKind, byTriggerCause, roleSpecific, subjectIDs, and
eventIDs. All counts are non-negative. Map keys are complete source keys and
all map values are non-negative. The roleSpecific tag equals actorRole.

RoleSpecificRepeatMetrics has exactly these tagged cases and fields:

- plannerLead: planningRevisionRounds, planningReviewRepeatCycles,
  planningSameRevisionReReviews, planningHandoffRepeatCycles
- teamLead: recoveryDispatchRounds, recoveryDispatchRepeatCycles,
  sameRecoveryKeyRedispatches, ownerEscalationRepeatCycles
- fullstackEngineer: implementationRevisionRounds, reviewFixRounds,
  ciRepairRounds, sameReviewFindingRepeats, sameCIFailureRepeats,
  handoffRepairRounds
- aiReviewer: reviewRounds, reviewRepeatCycles, sameSHAReReviews,
  changedSHAReReviews, inconclusiveReviewRounds, changesRequestedRounds
- prManager: ciSupervisionRounds, ciSupervisionRepeatCycles, sameSHACIReruns,
  shippingAttemptRounds, shippingAttemptRepeatCycles,
  implementationReturnRounds

The reconciliation equations are:

    repeatCycles <= attemptsTotal
    repeatCases <= attemptsTotal
    sameArtifactRepeatCycles + changedArtifactRepeatCycles == repeatCycles
    sum(byCycleKind.values) == repeatCycles
    sum(byTriggerCause.values) == repeatCycles

Each repeat counter is no greater than its corresponding round/attempt total.
The primary round totals planningRevisionRounds, recoveryDispatchRounds,
implementationRevisionRounds, reviewRounds, ciSupervisionRounds, and
shippingAttemptRounds are each no greater than attemptsTotal. Zero attempts
requires zero repeat, round, and maximum-cycle counters. subjectIDs and
eventIDs are each non-empty, unique, and exactly catalog-resolved. actorRole
values are unique within the section.

## Collision observations

ImportCollisionObservation has required observationID, parentSnapshotID,
parentSnapshotSHA256, observedAt, source, entityKind, stableIdentity,
acceptedSHA256, rejectedSHA256, disposition, and limitation. Required strings
are trimmed and non-empty; all hashes are 64 lowercase hexadecimal characters;
accepted and rejected hashes differ. disposition is the sole locked value
rejectedIdentityHashCollision. parentSnapshotID equals the payload snapshotID,
and parentSnapshotSHA256 equals payload contentSHA256. observationID values
are unique. No rejected content body is representable.

## Artifacts, grill links, reports, and externalization

ArtifactKind raw values are genericWorkflow, teamRelationship,
findingEventChain, and fullReport. ArtifactRequirement is mandatory or
optional.

ArtifactManifestEntry has required artifactID, snapshotID, kind, title,
eventIDs, revisionEvidence, contentSHA256, requirement, sidecarID, and
sidecarSHA256; findingFingerprint, caseID, and url are optional. Present
optional identity strings are trimmed and non-empty; optional url remains an
opaque exact string. artifactID values are unique; snapshot and sidecar values
equal the envelope; hashes are valid.

findingEventChain requires findingFingerprint and non-empty eventIDs and
revisionEvidence. The finding and every event/revision resolve once. A P0/P1
finding chain is mandatory; a P2/info chain may be optional. caseID omission is
valid; a present value must be trimmed, non-empty, and resolve exactly once.
Every mandatory artifact has a present URL accepted by the unchanged central
URL policy. Optional unsafe URL strings remain exact non-actionable data.

ArtifactSection has required artifacts and externalizedEntities arrays plus
optional grillLinks and fullReport. The arrays may be empty only when the
section still contains grillLinks or fullReport; the section cannot be wholly
empty. Any fullReport resolves using the six-field rule below.

GrillLinks has required sidecarID and sidecarSHA256 plus optional grillMeURL
and grillWithDocsURL. At least one URL field is present. Sidecar values equal
the envelope. URL strings remain exact untrusted data and are not structural
failures.

FullReportReference has required artifactID, title, contentSHA256, url,
sidecarID, and sidecarSHA256. It resolves only when exactly one
ArtifactReference matches kind fullReport plus artifact ID, hash, raw URL,
sidecar ID, and sidecar hash. Sidecar values also equal the envelope. This same
rule applies from overview, ArtifactSection, and externalization.

ExternalizableEntityKind raw values are exactly p2Finding, infoFinding,
caseTimeline, individualMetric, feedbackLineage, agentRepeatMetric,
importObservation, and optionalArtifact. ExternalizationReason has the sole raw
value exceedsInlinePayloadLimit.

ExternalizedEntityReference has required entityKind, stableID,
encodedByteCount, reason, sidecarID, sidecarSHA256, and fullReport. stableID is
non-empty, encodedByteCount is greater than zero, sidecar values equal the
envelope, and fullReport equals the section's resolved report across every
field. No mandatory-shaped kind is representable.

## Validation transition and URL seam

The immutable model defines only this transition:

    received JSON bytes
      -> locked decode
      -> structural and referential validation
      -> unchanged central URL-policy validation
      -> valid typed payload or existing structured schema failure

Models contains no Validation-role reference. The Validation extension checks
full-report URLs, mandatory artifact URLs, and present feedback-lineage PR
URLs. It preserves optional artifact and grill strings. Validation performs no
storage, network, issue, dispatch, publication, or remediation side effect.
