# Contract: AIDashCore `teamAudit`

## Registration and compatibility

- Wire value: `teamAudit`.
- `CardType.teamAudit` decodes `TeamAuditPayload` through the existing
  single-decode `CardType.validate(_:)` interface.
- Authored card size is returned unchanged; the contract defines no
  content-derived size override.
- The ten existing card types and their payload behavior are unchanged.
- Unknown locked enum values and invalid invariants use the existing decode or
  structured schema failure. No fallback enum case is introduced.

## Public payload surface

`TeamAuditPayload` and every nested value needed to construct a valid payload
are public, Codable, Equatable, and Sendable. The common envelope is:

```json
{
  "snapshotID": "snapshot-example-001",
  "capturedAt": "2026-10-14T00:00:00Z",
  "scope": {
    "owner": "Owner",
    "projectID": "project-example",
    "repository": "https://example.com/org/repository"
  },
  "mode": "baseline",
  "section": "overview",
  "partIndex": 0,
  "partCount": 1,
  "contentSHA256": "<64 lowercase hex>",
  "artifactSidecarID": "snapshot-example-001:artifact-sidecar:v1",
  "artifactSidecarSHA256": "<64 lowercase hex>",
  "referenceCatalog": {
    "caseIDs": [],
    "eventIDs": [],
    "evidenceRefs": [],
    "subjectIDs": [],
    "revisionEvidenceRefs": [],
    "findings": [],
    "artifacts": []
  }
}
```

Exactly one of `overview`, `findings`, `caseTimelines`, `individualMetrics`,
`feedbackLineage`, `agentRepeatMetrics`, `importObservations`, or `artifacts`
is populated, matching `section`; all other bodies are absent or empty.

The payload types and invariants are normative in `../data-model.md`. Public
API naming may follow existing Core Swift conventions, but it must preserve
the locked wire values and relationships in this contract.

## Catalog resolution

Every reference used by the selected body resolves exactly once in
`SnapshotReferenceCatalog`. The catalog is identity-only and has unique
trimmed IDs. Duplicate catalog keys reject even if their remaining data is
equal.

An artifact's `caseID` has three distinct states:

- omitted: valid;
- present and trimmed/non-empty: valid only when exactly one catalog `caseID`
  equals it;
- present but blank, dangling, or multiply resolved: invalid.

Validation must exercise that rule from both direct card validation and the
production schema-validation path.

## Axis and section semantics

- Baseline carries a cohort and no cursors; incremental carries cursors and no
  cohort.
- The core summary set is exactly Workflow Conformance, Workflow Fitness, and
  Outcome Integrity. Each shared `insufficientEvidence` wire value is decoded
  in its enclosing axis. Task Effectiveness remains a separate value.
- Counts are non-negative and reconcile with their typed totals.
- Finding, timeline, individual metric, feedback lineage, role-repeat, import
  observation, and artifact identities are unique and catalog-resolved as
  specified by `../data-model.md`.
- All `*SHA256` values are 64 lowercase hexadecimal characters. A present Git
  merge object ID is 40 lowercase hexadecimal characters.

## Full-report binding

A `FullReportReference` is accepted only if exactly one catalog
`ArtifactReference` matches all six binding dimensions:

| Dimension | Required relationship |
|---|---|
| kind | exactly `fullReport` |
| artifact ID | exact equality |
| content SHA-256 | exact equality |
| raw URL | exact equality |
| sidecar ID | exact equality and envelope equality |
| sidecar SHA-256 | exact equality and envelope equality |

This rule is identical for an overview, an artifacts section, and a report
embedded in externalization. An ID-only match is never sufficient. Absence,
duplication, or a one-field substitution rejects.

## Externalization binding

Externalization is available only for the locked optional kinds:

```text
p2Finding | infoFinding | caseTimeline | individualMetric |
feedbackLineage | agentRepeatMetric | importObservation | optionalArtifact
```

Every reference has a trimmed stable ID, a positive `encodedByteCount`, reason
exactly `exceedsInlinePayloadLimit`, envelope-equal sidecar ID/hash, and an
embedded full report exactly equal to the already-resolved report. Zero or
negative counts, unknown kinds, mandatory-shaped kinds, different reason,
sidecar drift, or any report-binding mismatch reject.

## URL-policy seam

The Models file treats all URLs as opaque strings. It may enforce presence and
exact equality, but it does not reference `URLPolicy` or Validation types.

`TeamAuditPayloadValidation.swift` supplies the
`CardPayloadProtocol.validateInvariants()` witness. It runs structural
validation first and then delegates the following to unchanged `URLPolicy`:

- full-report URL;
- every mandatory artifact URL;
- each present feedback-lineage PR URL.

Optional artifact and grill strings remain exact untrusted data even when
unsafe. They are not promoted to actionable links by Core. `URLPolicy.swift`,
`SchemaValidator.swift`, and `CardPayloadProtocol.swift` remain unchanged.

## Received-byte contract

The existing production limit remains 262,144 received UTF-8 bytes.

- An otherwise-valid `teamAudit` payload whose received `Data.count` is
  exactly 262,144 is accepted.
- An otherwise-valid mandatory payload whose received `Data.count` is exactly
  262,145 is rejected.
- Tests reach the existing `SchemaValidator.validateCardPut` path and do not
  replace the received-byte decision with decoded semantic re-encoding.

## Failure and side-effect contract

Validation is deterministic and side-effect-free. Failure never traps, never
coerces unknown semantics, and never performs storage, network, issue, agent,
or remediation work. It returns through the existing CardType/schema error
surfaces.
