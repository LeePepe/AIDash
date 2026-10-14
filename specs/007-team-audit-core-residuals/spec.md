# Feature Specification: Hidden Team Audit Core Residuals

**Feature Branch**: `007-team-audit-core-residuals`

**Created**: 2026-10-14

**Status**: Draft for the single final plan-gate review

**Input**: Decision B, accepted by the Team Lead as issue revision 5 plus
decision-comment revision 1.

## Authority and baseline

- Repository: the public AIDash repository named in the Planner handoff.
- Immutable observed baseline: `bdf1435fe7d3d9c4da43ed4297cbc24482447b46`.
- Constitution: 1.13.0; this feature does not amend it.
- The predecessor plan, its eleven-file allowlist, preserved candidate, and
  round-2 Reviewer finding are historical evidence only.
- The review-machinery dependency named in the Planner handoff is a later
  AIDash merge dependency. It grants no product scope and no path outside this
  feature's allowlist.

## Existing behavior

- Current main exposes exactly ten `CardType` cases. `teamAudit` is absent from
  `CardType`, decode/validation dispatch, `CardType.allCases`, schema listing,
  command help, and every rendered surface.
- Current main contains no `TeamAuditPayload`, `SnapshotReferenceCatalog`,
  `FullReportReference`, `ExternalizedEntityReference`, or
  `ExternalizableEntityKind` implementation. The two residual invariants are
  therefore not satisfied by current behavior.
- AIDashCore already owns the single HTTPS-with-host URL policy. Model data
  retains raw strings; consumers must not create another scheme/host policy.
- `specs/006-team-workflow-audit/` records the broader historical feature.
  It is not implementation authority for this bounded successor.

## Compatibility

- The ten existing card types, their raw values, their decode/validation
  behavior, effective-size behavior, schema enumeration, and tests remain
  byte-for-byte unchanged.
- The new Team Audit contract substrate remains internal to AIDashCore and is
  unreachable from `CardType`, `SchemaValidator`, the CLI, the App, aidata, and
  AIDashUI. A later coordinated feature must separately authorize promotion,
  registration, discovery, and rendering.
- A missing artifact `caseID` remains valid. A present valid `caseID`, a fully
  matching resolved full report, a positive encoded byte count, and every
  allowed optional externalization kind remain valid.
- AIDashCore remains the owner of URL policy. This feature compares raw URL
  identity as part of referential matching but does not alter or duplicate
  `URLPolicy` validation.
- Existing tests are retained without deletion or weakening.

## Removed or superseded behavior

- No accepted current-main behavior or test is removed.
- The historical proposal to register `CardType.teamAudit`, change the card
  count from 10 to 11, add effective-size handling, dispatch through
  `SchemaValidator`, expose a public initializer surface, or prove an
  AIDashUI fallback is explicitly superseded for this successor.
- Historical findings already closed by the predecessor round-2 review are not
  re-opened or re-planned. Only the two residual groups below remain.

## User Scenarios and Testing

### User Story 1 - Preserve trustworthy hidden references (Priority: P1)

As the future Team Audit publisher, I can rely on AIDashCore's hidden contract
to reject dangling artifact case references and substituted or invalid
full-report externalization references before any discovery surface is added.

**Why this priority**: These are the only unresolved correctness findings.
Closing them behind the Core boundary prevents a later coordinated release
from inheriting referential ambiguity without prematurely exposing the card.

**Independent Test**: Direct AIDashCore invariant fixtures construct neutral
hidden payload values without `CardType` registration. Valid present/nil case
bindings and valid full-report externalization pass; each one-field mismatch,
non-positive byte count, and unknown externalization kind fails.

**Acceptance Scenarios**:

1. **US1/AC1 — Present artifact case resolution**: Given an artifact whose
   optional `caseID` is present, when structural invariants run, then the value
   resolves exactly once through `SnapshotReferenceCatalog.caseIDs`; nil is
   accepted and a blank, duplicate, or dangling present value is rejected.
2. **US1/AC2 — Full-report catalog resolution**: Given an overview or artifact
   section full-report reference, when structural invariants run, then exactly
   one catalog entry matches kind `fullReport`, artifact ID, content hash, raw
   URL, sidecar ID, and sidecar hash.
3. **US1/AC3 — One-field mismatch matrix**: Given an otherwise valid full
   report, when kind, artifact ID, content hash, raw URL, sidecar ID, or sidecar
   hash is independently changed, then validation rejects the payload.
4. **US1/AC4 — Resolved/externalized identity**: Given an externalized optional
   entity, when its embedded report differs from the already resolved report
   by artifact ID, content hash, raw URL, sidecar ID, or sidecar hash, then
   validation rejects it.
5. **US1/AC5 — Positive encoded byte count**: Given an externalized optional
   entity, then a positive `encodedByteCount` is accepted and zero or negative
   values are rejected.
6. **US1/AC6 — Locked optional-only kinds**: The exact allowed wire values are
   `p2Finding`, `infoFinding`, `caseTimeline`, `individualMetric`,
   `feedbackLineage`, `agentRepeatMetric`, `importObservation`, and
   `optionalArtifact`; they round-trip exactly, unknown values fail decoding,
   and no mandatory overview/P0/P1/workflow/relationship/chain kind is
   representable.
7. **US1/AC7 — Hidden surface**: After the change, `CardType.allCases` remains
   ten and no registration, enumeration, schema, command, UI, App, aidata, or
   public Team Audit API surface exists.

### Edge Cases

- `caseID == nil` is not treated as an unresolved reference.
- A present whitespace-only `caseID` is invalid even if the catalog contains a
  visually similar value.
- Duplicate catalog case IDs cannot turn one reference into multiple matches;
  duplicate catalog identities reject the payload.
- Matching only an artifact ID is insufficient; every full-report binding
  field participates in the same exact match.
- Two independently valid reports cannot be substituted for one another by an
  externalized entity.
- A positive count is required even when the referenced report is valid.
- Raw URLs are compared for exact identity here; HTTPS actionability remains
  owned by the unchanged AIDashCore URL policy.

## Requirements

### Functional Requirements

- **FR-001**: `teamAudit` MUST remain absent from all registration and
  discovery surfaces.
- **FR-002**: A present artifact `caseID` MUST be non-empty and resolve exactly
  once through the payload reference catalog; nil MAY remain valid.
- **FR-003**: Overview and artifact-section full reports MUST resolve exactly
  once by kind, artifact ID, content hash, raw URL, sidecar ID, and sidecar
  hash.
- **FR-004**: An externalized entity's embedded full report MUST equal the
  section's already resolved report across artifact ID, content hash, raw URL,
  sidecar ID, and sidecar hash.
- **FR-005**: `encodedByteCount` MUST be greater than zero.
- **FR-006**: `ExternalizableEntityKind` MUST expose exactly the eight
  optional-only values in US1/AC6; unknown values MUST fail decoding and
  mandatory content MUST remain unrepresentable.
- **FR-007**: Structural URL equality MUST compare raw strings only. Scheme and
  host policy MUST remain centralized in unchanged AIDashCore `URLPolicy`.
- **FR-008**: Proof fixtures MUST use public-neutral names and identities and
  MUST NOT remove or weaken an existing test.
- **FR-009**: Implementation MUST modify exactly the two allowed AIDashCore
  paths declared by the plan and no other source, test, context, or product
  layer path.

### Key Entities

- **SnapshotReferenceCatalog**: Hidden identity catalog with unique case and
  artifact references used by structural validation.
- **ArtifactManifestEntry**: Hidden immutable artifact record with an optional
  case binding and sidecar provenance.
- **ArtifactReference**: Identity-only catalog entry containing kind, ID, hash,
  raw URL, and sidecar binding.
- **FullReportReference**: Typed resolved report binding used by overview,
  artifact sections, and optional externalization.
- **ExternalizedEntityReference**: Optional-only replacement with a locked
  entity kind, stable identity, positive encoded byte count, fixed reason, and
  the resolved full report.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Neutral fixtures prove nil and valid present artifact case IDs
  pass while blank, duplicate-catalog, and dangling present values fail.
- **SC-002**: Positive overview and artifact-section full-report fixtures pass,
  and every one-field kind/ID/hash/URL/sidecar mutation fails.
- **SC-003**: Positive externalization passes; every resolved-versus-embedded
  report mutation and every zero/negative byte count fails.
- **SC-004**: All eight optional-only kinds round-trip exactly, an unknown raw
  value fails, and no mandatory kind exists.
- **SC-005**: The implementation diff contains exactly two paths, the existing
  card-count tripwire remains 10, and hook-selected AIDashCore gates pass.

## Assumptions and Dependencies

- The exact planning revision that receives the final AI Reviewer `PASS` is
  the recommended immutable implementation base. A descendant is acceptable
  only when every reviewed planning artifact blob is byte-identical.
- The named review-machinery dependency may block a later merge but does not
  block planning, expand this contract, or add an implementation path.
- Promotion of hidden types to a registered/public card is a separate Owner
  decision and coordinated multi-layer feature.

## Non-Goals

- Registering or enumerating `teamAudit`.
- Adding a CLI command, schema-list entry, App/XPC advertisement, aidata
  producer, AIDashUI renderer, or DesignKit token.
- Changing `CardType`, `EffectiveCardSize`, `SchemaValidator`, `URLPolicy`,
  `CardPayloadProtocol`, public API tests, generic enum/round-trip tests, the
  constitution, context routing, hooks, or CI.
- Replaying, mutating, copying, publishing, or reviewing the predecessor's
  preserved workspace or candidates.
- Implementing any historical residual already closed by the round-2 review.
