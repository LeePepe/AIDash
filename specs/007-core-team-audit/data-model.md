# Data Model: Core Team Audit Contract

## Common payload

`TeamAuditPayload` is public, Codable, Equatable, and Sendable. It contains:

| Field | Type | Invariant |
|---|---|---|
| `snapshotID` | `String` | Trimmed and non-empty |
| `capturedAt` | `Date` | Immutable provenance |
| `scope` | `AuditScope` | Neutral owner/project/repository references |
| `mode` | `AuditMode` | `baseline` or `incremental` |
| `section` | `TeamAuditSection` | One of exactly eight locked values |
| `partIndex` / `partCount` | `Int` | `partCount > 0`; `0 <= partIndex < partCount` |
| `contentSHA256` | `String` | Exactly 64 lowercase hexadecimal characters |
| `artifactSidecarID` | `String` | Trimmed and non-empty |
| `artifactSidecarSHA256` | `String` | Exactly 64 lowercase hexadecimal characters |
| `referenceCatalog` | `SnapshotReferenceCatalog` | Complete local identity resolution for the selected section |
| section bodies | typed values/arrays | Exactly the body selected by `section` is populated |

`TeamAuditSection` is exactly `overview`, `findings`, `caseTimelines`,
`individualMetrics`, `feedbackLineage`, `agentRepeatMetrics`,
`importObservations`, or `artifacts`. Unknown values fail decoding.

## Mode and overview

`AuditMode.baseline` carries a typed cohort with unique stable case IDs and no
incremental cursors. `AuditMode.incremental` carries unique per-source cursors
and no cohort. An overview includes scope/provenance, evidence coverage,
limitations, publication coverage, exactly three core axis summaries, and one
separate Task Effectiveness summary.

The three core axes are Workflow Conformance, Workflow Fitness, and Outcome
Integrity. Each owns its locked verdict vocabulary. The common raw value
`insufficientEvidence` is decoded against the already-decoded enclosing axis;
it is not guessed by trying verdict enums in a fixed order. Task Effectiveness
cannot occupy a core-axis slot.

Evidence coverage and every required/published publication-count pair use
non-negative counts and reconcile exactly. A full report never compensates for
missing mandatory content.

## Reference catalog

`SnapshotReferenceCatalog` contains unique, trimmed identity values:

- `caseIDs`, `eventIDs`, `evidenceRefs`, `subjectIDs`, and
  `revisionEvidenceRefs`;
- `FindingReference(fingerprint, priority)` values unique by fingerprint;
- `ArtifactReference` values unique by artifact ID.

The catalog carries identity and immutable binding data only, not raw evidence
or duplicate display bodies. Every selected-section reference resolves exactly
once. A duplicate catalog identity is invalid even when duplicate values are
otherwise equal.

## Findings and evidence sections

- `AuditFinding` has stable fingerprint, typed axis, locked priority
  (`P0`, `P1`, `P2`, `info`), canonical state, explicit subject and
  responsibility, evidence references, and remediation owner. References are
  unique and catalog-resolved.
- `AuditCaseTimeline` has one catalog-resolved case and ordered events and
  attempts with unique stable identities. Its reference arrays exactly match
  the embedded values.
- `IndividualMetric` has stable subject identity, definition, numerator,
  denominator, window, and limitation. Counts are non-negative and the
  subject resolves.
- `FeedbackLineage` retains a canonical problem/origin/delivery identity,
  delivery/release/observation relationships, locked state, and optional PR
  URL. Identity and revision references resolve; any merge OID is lowercase
  40-hex.
- `AgentRepeatMetric` is per actor role. Common totals, cycle/cause counts, and
  the matching role-specific tagged counters are non-negative and reconcile.
  Supporting subject and event identities are unique and catalog-resolved.
- `ImportCollisionObservation` identifies the accepted parent snapshot and
  hash, observed entity, accepted/rejected hashes, source, disposition, and
  limitation without mutating accepted content.

## Artifact manifest

`ArtifactManifestEntry` contains:

| Field | Rule |
|---|---|
| `artifactID` | Trimmed, non-empty, unique |
| `snapshotID` | Equals payload `snapshotID` |
| `kind` | `genericWorkflow`, `teamRelationship`, `findingEventChain`, or `fullReport` |
| `title` | Trimmed, non-empty neutral display value |
| `findingFingerprint` | Required for finding-event chains and catalog-resolved |
| `caseID` | Optional; omission valid, present value trimmed/non-empty and resolved exactly once in `referenceCatalog.caseIDs` |
| `eventIDs` | Unique and catalog-resolved |
| `revisionEvidence` | Unique and catalog-resolved |
| `contentSHA256` | Exactly 64 lowercase hexadecimal characters |
| `url` | Opaque in Types; mandatory/full-report safety checked by Validation |
| `requirement` | `mandatory` or `optional` |
| `sidecarID` / `sidecarSHA256` | Equal payload envelope binding |

P0/P1 finding chains, the generic workflow artifact, and team/repository
relationships are mandatory. A missing or invalid mandatory artifact rejects;
it cannot be replaced by a report reference.

## Full-report resolution

`FullReportReference` contains artifact ID, title, content SHA-256, raw URL,
sidecar ID, and sidecar SHA-256. It resolves only if exactly one catalog
`ArtifactReference` matches all of:

1. kind is `fullReport`;
2. artifact ID;
3. content hash;
4. raw URL;
5. sidecar ID;
6. sidecar hash.

This rule applies to overview publication coverage, an artifacts section, and
the report embedded by an externalized reference. ID-only matching is invalid.
Missing or duplicate matches reject.

## Externalization

`ExternalizedEntityReference` contains:

- `entityKind`: exactly `p2Finding`, `infoFinding`, `caseTimeline`,
  `individualMetric`, `feedbackLineage`, `agentRepeatMetric`,
  `importObservation`, or `optionalArtifact`;
- a trimmed, non-empty stable ID;
- `encodedByteCount > 0`;
- reason exactly `exceedsInlinePayloadLimit`;
- sidecar ID/hash equal to the payload envelope;
- a full report exactly equal to the section's already-resolved report across
  ID, hash, URL, and sidecar binding.

There is no enum case for overview, P0/P1 findings, generic workflow, team
relationship, or P0/P1 chain content. Unknown or mandatory-shaped values fail
decoding/validation rather than being coerced.

## URL roles

Types retain URL fields as exact strings and may require their presence or
equality. Validation applies the unchanged central HTTPS-with-host policy to:

- full-report URLs;
- mandatory artifact URLs;
- present feedback-lineage PR URLs.

Optional artifact and grill URL strings remain round-trippable untrusted data;
an unsafe value is not made actionable and does not become a structural model
failure.

## State transitions

The model is immutable and defines no application state transition. Its only
observable transition is validation:

```text
received JSON bytes
  -> locked decode
  -> structural/reference validation
  -> central URL-policy validation
  -> valid typed payload OR existing structured schema failure
```

No value triggers persistence, network access, issue mutation, dispatch, or
remediation.
