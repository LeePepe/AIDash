# Research: Hidden Team Audit Core Residuals

## Decision 1: Create a distinct successor feature

**Decision**: Keep the broad `006-team-workflow-audit` artifacts unchanged and
record Decision B in `007-team-audit-core-residuals`.

**Rationale**: The current accepted version deliberately supersedes the stale
predecessor delivery path and removes registration/UI scope. Editing 006 in place
would blur historical authority with the new narrow contract.

**Rejected alternative**: Rewrite 006 and mark most tasks removed. That would
destroy useful historical evidence and make the exact successor review harder
to audit.

## Decision 2: Keep the substrate internal and unregistered

**Decision**: Define the value graph only inside
`TeamAuditPayload.swift`; do not add `CardType.teamAudit`, public initializers,
schema dispatch, effective-size behavior, or another consumer.

**Rationale**: Current main already satisfies the Owner's exclusion: ten card
types and no discovery. The two unresolved invariants can be made precise and
proved without opening a product surface.

**Rejected alternatives**:

- Restore the historical 11-file T005 surface: violates Decision B by adding
  registration and discovery.
- Add only tests against the historical candidate: the candidate is not in
  current main and is evidence only.
- Expose public model types now: creates a discoverable API before the later
  coordinated release is authorized.

## Decision 3: Use one Types file and one focused invariant suite

**Decision**: The complete implementation allowlist is the hidden model file
and `TeamAuditPayloadInvariantTests.swift`.

**Rationale**: Both residuals are structural rules over the same value graph.
SwiftPM already discovers both paths through the AIDashCore target, so no
manifest or context change is needed. A single focused suite can round-trip
the locked enum without modifying generic enum tests.

**Rejected alternative**: Modify generic round-trip, schema, or public API
tests. Those files test registered/public behavior, which is a non-goal.

## Decision 4: Resolve a present artifact case exactly once

**Decision**: Nil remains valid. A present `caseID` must be trimmed/non-empty
and match one unique catalog case identity. Duplicate catalog identities,
blank values, and dangling values reject the payload.

**Rationale**: Optionality and referential integrity are independent. Treating
nil as invalid would change the historical contract; accepting a dangling
present value would preserve the round-2 defect.

## Decision 5: Match full reports by the complete immutable tuple

**Decision**: Full-report resolution uses kind, artifact ID, content hash, raw
URL, sidecar ID, and sidecar hash. Each field receives an independent negative
fixture for both overview and artifact-section paths where applicable.

**Rationale**: Matching by ID alone permits content, location, or provenance
substitution. Requiring one catalog match makes independently decoded values
self-validating.

## Decision 6: Bind externalization to the resolved report

**Decision**: Each externalized entity uses the fixed reason, a positive byte
count, one of eight optional-only kinds, and a full report equal to the report
already resolved for the section.

**Rationale**: Re-resolving only an artifact ID is not enough; it could select
a different valid report. The closed enum makes mandatory content
unrepresentable by construction.

## Decision 7: Preserve URL-policy ownership without adding a validator

**Decision**: Compare raw URL strings for identity but do not parse, validate,
or make them actionable in this hidden substrate. Keep `URLPolicy.swift`
forbidden and unchanged.

**Rationale**: AIDashCore already owns the single policy. There is no
registered decode or rendering path in this successor, so copying the policy
into Types would create drift without a consumer. The later registration
feature must connect the hidden value to the existing policy under separate
authority.

## Decision 8: Treat prior closed findings as evidence, not work

**Decision**: Do not re-plan axis decoding, lineage/OID validation, role-round
bounds, chain priority, artifact-ID uniqueness, eight-section equality,
structured schema errors, byte-boundary tests, or AIDashUI fallback.

**Rationale**: Reviewer round 2 explicitly closed those findings. Current
Decision B authorizes only the two remaining residual groups.

## Decision 9: Pin the PASSed planning commit as implementation base

**Decision**: The exact commit receiving the single final plan-gate PASS is the
recommended base. Any later base must carry byte-identical planning artifacts.

**Rationale**: This keeps the implementation diff limited to the two product
paths and prevents a stale or broadened plan from becoming authority. The
named review-machinery dependency affects later merge eligibility only.

## Resolved ambiguities

- “Undiscoverable” means no `CardType`, schema, command, public API, App, data,
  or rendered consumer surface.
- “URL match” means exact raw-string identity within the immutable tuple; it
  does not authorize a second URL policy.
- “Exactly once” includes rejecting duplicate catalog identities, not merely
  finding at least one equal value.
- “Locked externalizable kind” means eight optional-only raw values; mandatory
  kinds are absent rather than rejected at a later semantic layer.
- The review-machinery item is a merge dependency, not a source or planning
  dependency.
