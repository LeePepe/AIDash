# Contract: Team Workflow Audit Snapshot v1

## Authority and decoding rules

This file is the complete raw wire contract for `snapshot.json` schema version
`team-workflow-audit/snapshot-v1`. T022 implements this contract directly; it
does not depend on an unpublished producer model, a historical implementation,
or field-name inference. Any producer change requires a new versioned contract.

Unless a row's type explicitly includes `null`, every listed key is required
and non-null; nullable keys are also required and use JSON null for absence.
Every object rejects unlisted keys and duplicate members. Keys are
case-sensitive camel case; aliases, including snake-case aliases, reject. Every
string is valid UTF-8 and trimmed; identity/display strings are non-empty.
Arrays are always present and preserve source order. Identity/reference arrays
contain unique non-empty strings. A JSON `integer` is parsed with arbitrary
precision and is then accepted only if it satisfies the field rule; booleans,
floats, and numeric strings are not integers. Dates are ISO-8601 strings with an
explicit zero UTC offset (`Z` or `+00:00`). SHA-256 values are exactly 64
lowercase hexadecimal characters; `mergeSHA` is exactly 40 lowercase
hexadecimal characters. Malformed UTF-8/JSON and unknown schema versions reject.

## Snapshot envelope

`snapshot.json` is exactly one object with these keys:

| Key | JSON type | Rule |
|---|---|---|
| `schemaVersion` | string | Exactly `team-workflow-audit/snapshot-v1` |
| `snapshotID` | string | Stable snapshot identity |
| `capturedAt` | string | UTC timestamp |
| `scope` | AuditScope | Exact object below |
| `mode` | string | `baseline | incremental` |
| `instructionVersions` | InstructionVersion[] | Non-empty; unique `sourceID` |
| `evidenceCoverage` | EvidenceCoverage | Exact object below |
| `cohort` | AuditCohort \| null | Non-null only for `baseline` |
| `cursors` | AuditCursor[] | Empty for `baseline`; non-empty for `incremental`; unique `sourceID` and `cursorID` |
| `axisSummaries` | CoreAxisSummary[] | Exactly three entries, one per core axis |
| `taskEffectiveness` | TaskEffectivenessSummary | Never encoded as a fourth core summary |
| `cases` | AuditCase[] | Unique `caseID` |
| `events` | AuditEvent[] | Unique `eventID`; complete snapshot event catalog |
| `attempts` | AuditAttempt[] | Unique `attemptID`; complete snapshot attempt catalog |
| `individualMetrics` | IndividualMetric[] | Unique `metricID` |
| `feedbackLineage` | FeedbackLineage[] | Unique `lineageID` |
| `agentRepeatMetrics` | AgentRepeatMetric[] | Exactly one entry for each actor role |
| `findings` | AuditFinding[] | Unique `fingerprint` |
| `limitations` | string[] | Required non-empty when evidence/cohort is incomplete |

Mode rules are exact: `baseline` requires a non-null cohort and empty cursors;
`incremental` requires null cohort and one or more cursors. The decoder does not
fabricate an absent object or translate an empty object into null.

## Scope, instruction, evidence, cohort, and cursor objects

| Object | Required keys and JSON types |
|---|---|
| AuditScope | `ownerLabel: string`; `projectReference: string`; `repositoryReference: string` |
| InstructionVersion | `sourceID: string`; `updatedAt: UTC string`; `sha256: SHA-256 string` |
| EvidenceCoverage | `requiredEvidenceCount: integer >= 0`; `availableEvidenceCount: integer >= 0`; `missingEvidenceCount: integer >= 0`; `redactedEvidenceCount: integer >= 0`; `limitations: string[]` |
| AuditCohort | `cohortID: string`; `caseIDs: string[]` (non-empty, source ordered, unique) |
| AuditCursor | `sourceID: string`; `cursorID: string`; `timestamp: UTC string`; `overlapHours: integer >= 0` |

Evidence coverage requires
`availableEvidenceCount + missingEvidenceCount == requiredEvidenceCount` and
`redactedEvidenceCount <= availableEvidenceCount`. Missing/redacted evidence
requires a limitation. A baseline cohort with fewer than 20 cases also requires
a limitation.

## Axis objects

`CoreAxisSummary` contains exactly:

| Key | JSON type | Rule |
|---|---|---|
| `axis` | string | `workflowConformance | workflowFitness | outcomeIntegrity` |
| `verdict` | string | Axis-scoped vocabulary below |
| `totalCases` | integer | >= 0 |
| `positiveCount` | integer | >= 0 |
| `negativeCount` | integer | >= 0 |
| `insufficientEvidenceCount` | integer | >= 0 |

Verdicts are decoded only after `axis`:

- `workflowConformance`: `conformant | nonconformant | insufficientEvidence`
- `workflowFitness`: `fit | unfit | insufficientEvidence`
- `outcomeIntegrity`: `intact | compromised | insufficientEvidence`

The three counts sum to `totalCases`. `TaskEffectivenessSummary` contains
exactly `evaluatedTotal`, `effectiveCount`, `ineffectiveCount`,
`regressedCount`, `pendingCount`, and `insufficientEvidenceCount`; every value
is an integer >= 0 and the five counts sum to `evaluatedTotal`.

## Case, event, attempt, and individual-metric objects

`AuditCase` contains exactly:

| Key | JSON type | Rule |
|---|---|---|
| `caseID` | string | Stable case identity |
| `subjectID` | string | Stable redacted subject identity |
| `responsibilityLayer` | string | Explicit source-owned layer |
| `summary` | string | Redacted display text |
| `eventIDs` | string[] | Ordered unique identities |
| `attemptIDs` | string[] | Ordered unique identities |
| `events` | AuditEvent[] | Exact embedded values for `eventIDs`, same order |
| `attempts` | AuditAttempt[] | Exact embedded values for `attemptIDs`, same order |
| `limitations` | string[] | Case-local limitations |

`AuditEvent` contains exactly:

| Key | JSON type | Rule |
|---|---|---|
| `eventID` | string | Stable event identity |
| `caseID` | string | Back-pointer to containing/catalog case |
| `source` | string | Portable source identity, never a local path |
| `subjectID` | string | Stable subject identity |
| `actorRole` | ActorRole | Locked vocabulary below |
| `kind` | string | Non-empty free-form source value |
| `timestamp` | string | UTC timestamp |
| `revisionSHA` | string | 40 lowercase hexadecimal Git SHA-1 |
| `evidenceRef` | string | Stable hash/reference, never a raw body |

`AuditAttempt` contains exactly:

| Key | JSON type | Rule |
|---|---|---|
| `attemptID` | string | Stable attempt identity |
| `caseID` | string | Back-pointer to containing/catalog case |
| `actorRole` | ActorRole | Locked vocabulary below |
| `cycleID` | string | Stable cycle identity |
| `cycleKind` | string | Non-empty source cycle-kind value |
| `timestamp` | string | UTC timestamp |
| `triggerCause` | RepeatTriggerCause | Locked vocabulary below |
| `outcome` | string | Non-empty redacted source value |
| `evidenceRefs` | string[] | Non-empty stable hash/references |

`IndividualMetric` contains exactly `metricID: string`, `definition: string`,
`numerator: integer >= 0`, `denominator: integer > 0`,
`observationWindow: string`, and `limitation: string`. It is descriptive only.

Every case's embedded events/attempts equal the corresponding top-level catalog
values byte-for-byte after decoding. Each embedded value points to its case,
and every event and attempt timestamp is UTC. Event timestamps are
non-decreasing in source order; equal timestamps retain source order. No event,
attempt, case, evidence, or subject reference is invented or silently dropped.

## Feedback lineage

`FeedbackLineage` contains exactly:

| Key | JSON type | Rule |
|---|---|---|
| `lineageID` | string | SHA-256 of the normative tuple in `data-model.md` |
| `problemFingerprint` | string | Stable problem identity |
| `originIssueID` | string | Stable feedback-origin identity |
| `deliveryIssueID` | string | Stable delivery identity |
| `prURL` | string \| null | Exact untrusted source value |
| `mergeSHA` | string \| null | 40 lowercase hexadecimal Git SHA-1 when present |
| `releaseChannel` | string \| null | `testflight | appStore | production | internal` when present |
| `firstVersion` | string \| null | First containing version when known |
| `firstBuild` | string \| null | First containing build when known |
| `availableAt` | string \| null | UTC timestamp when present |
| `observationEventIDs` | string[] | Unique stable event identities |
| `relatedFeedbackIssueIDs` | string[] | Unique stable feedback identities |
| `taskEffectiveness` | string | `effective | ineffective | regressed | pendingDelivery | pendingRelease | pendingObservation | insufficientEvidence` |

Nullable keys are never omitted. `lineageID` is validated from the exact
U+001F-delimited tuple specified in `data-model.md`.

## Agent repeat metrics

`ActorRole` is exactly `plannerLead | teamLead | fullstackEngineer |
aiReviewer | prManager`. `RepeatTriggerCause` is exactly `planningFinding |
reviewFinding | ciCodeFailure | ciInfrastructureFailure |
shaOrMetadataMismatch | permissionOrCredential | hardwareOrEnvironment |
ownerDecision | workflowConfiguration | unknown`.

`AgentRepeatMetric` contains exactly:

| Key | JSON type | Rule |
|---|---|---|
| `actorRole` | ActorRole | One record per role |
| `attemptsTotal` | integer | >= 0 |
| `repeatCycles` | integer | >= 0 and <= `attemptsTotal` |
| `repeatCases` | integer | >= 0 and <= `attemptsTotal` |
| `sameArtifactRepeatCycles` | integer | >= 0 |
| `changedArtifactRepeatCycles` | integer | >= 0 |
| `maxCyclesPerCase` | integer | >= 0 |
| `byCycleKind` | object<string, integer >= 0> | Non-empty trimmed keys; complete source map |
| `byTriggerCause` | object<RepeatTriggerCause, integer >= 0> | All ten cause keys required; no other key |
| `roleSpecific` | RoleSpecificRepeatMetrics | Tagged object below; tag equals `actorRole` |
| `subjectIDs` | string[] | Non-empty unique supporting subjects |
| `eventIDs` | string[] | Non-empty unique supporting events |

`RoleSpecificRepeatMetrics` has a required `kind` plus only the integer fields
for that kind; every integer is >= 0:

| `kind` | Additional required keys |
|---|---|
| `plannerLead` | `planningRevisionRounds`; `planningReviewRepeatCycles`; `planningSameRevisionReReviews`; `planningHandoffRepeatCycles` |
| `teamLead` | `recoveryDispatchRounds`; `recoveryDispatchRepeatCycles`; `sameRecoveryKeyRedispatches`; `ownerEscalationRepeatCycles` |
| `fullstackEngineer` | `implementationRevisionRounds`; `reviewFixRounds`; `ciRepairRounds`; `sameReviewFindingRepeats`; `sameCIFailureRepeats`; `handoffRepairRounds` |
| `aiReviewer` | `reviewRounds`; `reviewRepeatCycles`; `sameSHAReReviews`; `changedSHAReReviews`; `inconclusiveReviewRounds`; `changesRequestedRounds` |
| `prManager` | `ciSupervisionRounds`; `ciSupervisionRepeatCycles`; `sameSHACIReruns`; `shippingAttemptRounds`; `shippingAttemptRepeatCycles`; `implementationReturnRounds` |

The reconciliation equations and upper bounds in `data-model.md` are normative.
In particular, same-artifact plus changed-artifact cycles equals repeat cycles,
each complete breakdown sums to repeat cycles, and zero attempts require every
repeat/maximum value to be zero.

## Findings

`AuditFinding` contains exactly:

| Key | JSON type | Rule |
|---|---|---|
| `fingerprint` | string | Stable finding identity |
| `subjectID` | string | Explicit stable subject |
| `responsibilityLayer` | string | Explicit source-owned layer |
| `axis` | string | `workflowConformance | workflowFitness | outcomeIntegrity | taskEffectiveness` |
| `priority` | string | `P0 | P1 | P2 | info` |
| `verdict` | string | Non-empty source verdict |
| `state` | string | `open | acknowledged | approvedForRemediation | resolved | regressed | superseded` |
| `summary` | string | Redacted display text |
| `caseIDs` | string[] | Non-empty unique case references |
| `eventIDs` | string[] | Non-empty unique event references |
| `evidenceRefs` | string[] | Non-empty unique hash/references |
| `remediationOwner` | string | `projectDevTeam | separateExecutionAgent` |

Every finding reference resolves exactly once. Artifact-chain ownership is
validated against this finding, its cases, and its events as specified by
`contracts/manual-import.md` and `contracts/t002-acceptance-matrix.md`.

## Decoder disposition

T022 returns either one immutable decoded snapshot or one structured rejection;
it never partially accepts an object, applies aliases/defaults, or lets a JSON
numeric conversion exception escape. Semantic checks in `data-model.md`, this
wire contract, the sidecar wire contract, and the T002 acceptance matrix are all
conjunctive. This file owns raw snapshot shape; `data-model.md` owns cross-field
and cross-reference semantics; `contracts/manual-import.md` owns bundle import;
and `contracts/l1l2-normalized-output.md` owns the source-clean boundary.
