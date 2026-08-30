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
| `url` | String? | Actionable only when central URL policy accepts HTTPS + host |

Every P0/P1 finding requires a `findingEventChain` entry or an explicit
limitation. Each snapshot requires one generic workflow and applicable
team/repository relationship entries or an explicit limitation.

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
`overview | findings | caseTimelines | individualMetrics | artifacts`.
The payload contains only the collection selected by `section`; all unrelated
collections must be empty. Every encoded payload must remain within the
repository's 256 KB card limit.

### Section content

- `overview`: cohort or cursors, instruction versions, evidence coverage,
  exactly three core summaries, separate Task Effectiveness, provenance, and
  limitations.
- `findings`: one or more complete `AuditFinding` values. This is the only
  section that exposes decision controls.
- `caseTimelines`: bounded `AuditCase` values plus their referenced events and
  attempts.
- `individualMetrics`: bounded descriptive metrics.
- `artifacts`: artifact entries plus optional `grillMeURL` and
  `grillWithDocsURL`, both treated as untrusted HTTPS strings.

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
- `fact_team_audit_artifact`: one row per snapshot + artifact identity.

Child facts reference the accepted snapshot hash. L3 never updates a row with
a different hash. L4 queries are read-only and expose their grain explicitly.
