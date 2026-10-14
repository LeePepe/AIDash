# Feature Specification: Core Team Audit Contract

**Feature Branch**: `007-core-team-audit`

**Created**: 2026-10-14

**Status**: Draft

**Input**: Re-baseline the AIDashCore `teamAudit` payload contract from
immutable current `main` `bdf1435fe7d3d9c4da43ed4297cbc24482447b46` and
plan only behavior that snapshot still lacks.

## Existing behavior

- The baseline exposes exactly ten `CardType` values. `teamAudit`, its payload,
  its reference catalog, and its audit-specific tests do not exist.
- `CardType.validate` already decodes a payload once and calls the payload's
  invariant interface. `SchemaValidator.validateCardPut` already converts
  decode and invariant failures into the existing structured schema error.
- The received-payload limit is already 262,144 UTF-8 bytes. Existing generic
  tests cover arbitrary bytes at and above that limit, but no otherwise-valid
  `teamAudit` value exercises the production path at the exact boundary.
- Agent-authored link safety already has one policy: HTTPS with a non-empty
  host. The policy and its public interface are accepted behavior.
- AIDashUI already degrades an unrecognized decoded payload to its generic
  card fallback. The App schema catalog still advertises only the ten current
  payloads and requires a later AIDashApp-owned adaptation after Core adds the
  new enum case.
- Historical `specs/006-team-workflow-audit/` artifacts describe the broader
  product feature, but their retired T005 recovery base, candidate, task ID,
  and file allowlist are not execution authority for this successor.

## Compatibility

- All ten existing card types, payloads, validation behavior, structured
  errors, and tests remain unchanged except for the intentional 10-to-11 enum
  registration tripwire.
- The existing `CardPayloadProtocol`, `CardType.validate`,
  `SchemaValidator.validateCardPut`, payload byte limit, and `URLPolicy`
  interfaces are reused unchanged.
- Existing unknown-payload UI fallback behavior remains valid; explicit audit
  rendering and schema advertisement stay downstream, layer-owned work.
- Unsafe optional artifact and grill strings remain round-trippable untrusted
  data. They do not become actionable links.
- Neutral fixtures contain no account, employer, machine, workspace, or real
  project identifiers.

## Removed or superseded behavior

- No shipped behavior or accepted test is removed or weakened.
- Historical `006/T005`, historical FR-020 through FR-025, planning revision
  `9b25314544a1eec34f6f37e948cbbb50d0838fdb`, and preserved implementation
  candidates are evidence only. This specification gives the successor its
  own acceptance IDs and current-main-derived paths.
- The historical eleven-file allowlist is superseded. In particular, focused
  Team Audit tests replace edits to the broad shared payload round-trip file,
  and the current owner test for effective-size behavior is included.

## User Scenarios & Testing

### User Story 1 - Accept only trustworthy Core audit payloads (Priority: P1)

As an audit publisher, I can submit one typed Team Workflow Audit card payload
whose identity, evidence, artifact, report, and externalization relationships
are self-consistent, while malformed or substitution-prone payloads are
rejected before storage.

**Why this priority**: Every downstream producer, schema advertisement, and
renderer depends on one trustworthy Core contract. Shipping a permissive or
ambiguous contract would make immutable provenance unverifiable.

**Independent Test**: Construct all eight section variants with neutral data,
validate them through the public card interface and production schema path,
then mutate each locked value or relationship one field at a time and observe
the existing structured failure without changing any non-Core layer.

**Acceptance Scenarios**:

1. **US1/AC1** — Given any of the eight valid section variants, when it is
   encoded, decoded, and validated, then every common and section value is
   exactly equal and its references resolve once through the local catalog.
2. **US1/AC2** — Given baseline and incremental overviews, when their axis
   summaries decode, then all three enclosing-axis `insufficientEvidence`
   values retain the correct axis and Task Effectiveness stays separate.
3. **US1/AC3** — Given an artifact with no `caseID`, validation succeeds; given
   a present `caseID`, it succeeds only when the trimmed value resolves exactly
   once in the catalog.
4. **US1/AC4** — Given a blank or dangling artifact `caseID`, or duplicate case
   catalog identity, both direct card validation and the production schema path
   reject it with the existing structured payload failure.
5. **US1/AC5** — Given an overview or artifacts-section full report, validation
   succeeds only when exactly one catalog artifact matches `fullReport` kind,
   artifact ID, content hash, raw URL, sidecar ID, and sidecar hash.
6. **US1/AC6** — Given an otherwise-valid report, changing any one of kind, ID,
   hash, URL, sidecar ID, or sidecar hash—or making the match absent or
   duplicate—rejects both the overview and artifacts-section paths.
7. **US1/AC7** — Given an externalized optional entity, its kind is one locked
   optional-only value, its reason is `exceedsInlinePayloadLimit`, its encoded
   byte count is positive, and its embedded report exactly equals the resolved
   report; zero, negative, unknown, mandatory-shaped, or mismatched values
   reject.
8. **US1/AC8** — Given otherwise-valid serialized payloads of exactly 262,144
   and 262,145 bytes, the first is accepted and the mandatory second is
   rejected by the production received-byte gate.
9. **US1/AC9** — Given existing card payloads and URL strings, the successor
   changes none of their behavior and neither widens nor duplicates the
   central URL policy.

### Edge Cases

- A standalone overview carries a full-report reference but no artifact body;
  its catalog entry must still make the reference independently resolvable.
- Matching an artifact ID while changing any other immutable binding is a
  substitution and rejects.
- Optional `caseID` omission is distinct from a present blank value; omission
  is valid and blank is invalid.
- Duplicate catalog identities reject rather than being silently deduplicated.
- Mandatory overview, P0/P1 finding, generic workflow, team relationship, and
  P0/P1 chain content cannot be represented by the externalizable-kind enum.
- An unknown locked enum fails decoding; it is never coerced to a known value.
- Optional unsafe URL strings remain exact data, while unsafe mandatory or
  full-report URLs reject through the existing policy.

## Requirements

### Functional Requirements

- **FR-001**: AIDashCore MUST register `teamAudit` as the eleventh card type,
  decode it as one public payload, and preserve authored size without a
  content-derived downgrade.
- **FR-002**: The payload MUST have one common immutable envelope and exactly
  eight locked section variants: `overview`, `findings`, `caseTimelines`,
  `individualMetrics`, `feedbackLineage`, `agentRepeatMetrics`,
  `importObservations`, and `artifacts`.
- **FR-003**: Baseline/cohort and incremental/cursor modes, the three typed core
  axes, separate Task Effectiveness, coverage counts, findings, timelines,
  lineage, repeat metrics, and collision observations MUST satisfy the
  reconciliation and catalog rules in the successor contract.
- **FR-004**: Every artifact's optional `caseID`, when present, MUST be trimmed,
  non-empty, and resolve exactly once through `referenceCatalog.caseIDs`.
  Omission is valid; blank, dangling, or multiply-resolved values reject.
- **FR-005**: Every overview or artifacts-section full report MUST resolve
  exactly one catalog artifact matching kind `fullReport`, artifact ID,
  content SHA-256, raw URL, sidecar ID, and sidecar SHA-256. A mismatch in any
  one field, no match, or multiple matches MUST reject.
- **FR-006**: Externalization MUST support only the locked optional kinds
  `p2Finding`, `infoFinding`, `caseTimeline`, `individualMetric`,
  `feedbackLineage`, `agentRepeatMetric`, `importObservation`, and
  `optionalArtifact`. It MUST use reason `exceedsInlinePayloadLimit`, require a
  positive `encodedByteCount`, match the envelope sidecar, and bind exactly to
  the already-resolved full report. Mandatory-shaped or unknown kinds reject.
- **FR-007**: Structural and referential validation MUST remain in the Types
  implementation while the protocol witness in the Validation role reuses the
  unchanged central URL policy. Models MUST NOT depend on a Validation symbol.
- **FR-008**: Locked enums and all public payload types MUST round-trip exactly.
  Unknown locked values MUST propagate through the existing structured Core
  failure path without coercion.
- **FR-009**: An otherwise-valid final serialized `teamAudit` payload of
  exactly 262,144 bytes MUST be accepted; a mandatory payload of exactly
  262,145 bytes MUST be rejected using received bytes, not semantic
  re-encoding.
- **FR-010**: The complete valid payload surface MUST be constructible from the
  external AIDashCore test target without `@testable import`.
- **FR-011**: The implementation MUST preserve all accepted current-main card,
  schema-validator, URL-policy, and fallback behavior and MUST remove or weaken
  no existing test.

### Key Entities

- **Team Audit Payload**: One independently decodable card part with immutable
  snapshot/sidecar provenance and exactly one selected section.
- **Snapshot Reference Catalog**: Identity-only catalog for case, event,
  evidence, subject, finding, revision, and artifact references.
- **Artifact Manifest Entry**: Immutable artifact description with optional
  case binding and exact snapshot/sidecar provenance.
- **Full Report Reference**: Typed pointer that resolves to one immutable
  catalog artifact by kind, ID, hash, URL, and sidecar binding.
- **Externalized Entity Reference**: Optional-only replacement with a locked
  kind, positive source byte count, fixed reason, and exact full-report binding.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All eight valid variants compare exactly equal after round-trip
  and pass through both public card validation and production schema validation.
- **SC-002**: The artifact `caseID` suite includes omission, positive exact
  resolution, blank, dangling, and duplicate-catalog outcomes with zero false
  acceptance.
- **SC-003**: The report suite rejects every one-field mismatch for kind, ID,
  hash, URL, sidecar ID, and sidecar hash, plus missing and duplicate matches,
  for overview, artifacts, and externalized bindings.
- **SC-004**: The externalization suite proves the complete allowed-kind set,
  rejects unknown and mandatory-shaped values, accepts a positive byte count,
  and rejects zero and negative counts.
- **SC-005**: Exact otherwise-valid 262,144/262,145 byte fixtures produce one
  acceptance and one rejection through the production path.
- **SC-006**: The implementation diff is confined to the reviewed AIDashCore
  allowlist, and all resolver-selected Core gates pass with no Models-to-
  Validation dependency.

## Assumptions

- The broader Team Workflow Audit product contract in `006` remains historical
  source material; only the Core-owned, current-main-unsatisfied subset is
  carried into this successor.
- Downstream AIDashApp schema advertisement, DesignKit token, AIDashUI renderer,
  producer, and event work remain separate layer tasks and are not silently
  absorbed here.
- No new package, dependency, store, migration, network client, or public URL
  policy is required.

## Non-Goals

- Rendering audit cards or adding design tokens.
- Advertising the audit schema from AIDashApp or changing CLI commands.
- Importing, generating, or publishing audit data.
- Adding Owner decision events or remediation behavior.
- Mutating, publishing, or re-reviewing any preserved MY-1522 workspace,
  branch, metadata, or candidate.
