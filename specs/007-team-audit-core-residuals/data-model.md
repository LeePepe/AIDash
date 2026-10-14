# Data Model: Hidden Team Audit Core Residuals

All types in this successor are internal to AIDashCore. They are Codable,
Sendable, and Equatable where needed for deterministic direct proof, but are
not registered as a card payload or exposed as public API.

## SnapshotReferenceCatalog

| Field | Type | Rules |
|---|---|---|
| `caseIDs` | `[String]` | Trimmed, non-empty, unique stable identities |
| `artifacts` | `[ArtifactReference]` | Unique artifact IDs; identity-only bindings |

The implementation may retain additional hidden catalog fields needed to keep
the historical value graph coherent, but they are not successor acceptance
surface and receive no new behavior in this feature.

## ArtifactKind

Locked values needed by this residual contract:

- `genericWorkflow`
- `teamRelationship`
- `findingEventChain`
- `fullReport`

Only `fullReport` can satisfy a `FullReportReference`.

## ArtifactReference

| Field | Type | Rules |
|---|---|---|
| `artifactID` | `String` | Trimmed, non-empty, unique in the catalog |
| `kind` | `ArtifactKind` | Must be `fullReport` for report resolution |
| `contentSHA256` | `String` | Exactly 64 lowercase hexadecimal characters |
| `url` | `String` | Raw immutable identity; exact comparison only |
| `sidecarID` | `String` | Trimmed, non-empty |
| `sidecarSHA256` | `String` | Exactly 64 lowercase hexadecimal characters |

## ArtifactManifestEntry

| Field | Type | Rules |
|---|---|---|
| `artifactID` | `String` | Stable manifest identity |
| `caseID` | `String?` | Nil allowed; present value resolves exactly once through catalog `caseIDs` |
| `contentSHA256` | `String` | Immutable artifact hash |
| `url` | `String?` | Raw publisher value; actionability is not owned here |
| `sidecarID` / `sidecarSHA256` | `String` | Immutable provenance binding |

When `caseID` is present, trimming may be used for the non-empty check but
resolution uses the stable stored identity exactly; the implementation must
not silently rewrite an identity.

## FullReportReference

| Field | Type | Rules |
|---|---|---|
| `artifactID` | `String` | Matches one catalog entry |
| `contentSHA256` | `String` | Matches that entry |
| `url` | `String` | Raw string exactly matches that entry |
| `sidecarID` | `String` | Matches that entry and payload sidecar |
| `sidecarSHA256` | `String` | Matches that entry and payload sidecar |

Resolution predicate:

```text
catalog.kind == fullReport
AND catalog.artifactID == reference.artifactID
AND catalog.contentSHA256 == reference.contentSHA256
AND catalog.url == reference.url
AND catalog.sidecarID == reference.sidecarID
AND catalog.sidecarSHA256 == reference.sidecarSHA256
```

Exactly one catalog value must satisfy the complete predicate.

## ExternalizableEntityKind

Exact raw-value set:

```text
p2Finding
infoFinding
caseTimeline
individualMetric
feedbackLineage
agentRepeatMetric
importObservation
optionalArtifact
```

The enum has no unknown fallback. Decoding any other raw value fails. It has no
case for overview, P0/P1 finding, generic workflow, team relationship, or
P0/P1 finding chain.

## ExternalizedEntityReference

| Field | Type | Rules |
|---|---|---|
| `entityKind` | `ExternalizableEntityKind` | One optional-only value |
| `stableID` | `String` | Trimmed, non-empty |
| `encodedByteCount` | `Int` | Strictly greater than zero |
| `reason` | `ExternalizationReason` | Exactly `exceedsInlinePayloadLimit` |
| `sidecarID` / `sidecarSHA256` | `String` | Match payload/report provenance |
| `fullReport` | `FullReportReference` | Equal to the already resolved section report |

The full report equality covers artifact ID, content hash, raw URL, sidecar ID,
and sidecar hash. A separately valid but different report is not substitutable.

## Structural validation order

1. Validate required non-empty identities and hash shapes.
2. Reject duplicate catalog identities.
3. Resolve every present artifact `caseID` exactly once.
4. Resolve the overview or artifact-section full report exactly once through
   the complete catalog predicate.
5. Validate externalized kind, stable ID, positive count, fixed reason, and
   sidecar provenance.
6. Compare each embedded externalized report with the already resolved report.

The order ensures a malformed catalog cannot make a later equality check look
authoritative. Errors remain ordinary thrown validation errors; production
code does not trap.
