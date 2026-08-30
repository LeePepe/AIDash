# Contract: `teamAudit` Card Payload

## Card registration

- `CardType.rawValue`: `teamAudit`
- Design classification token: `Classification.teamAudit`
- Badge tint: system-pink pair, light `#FF2D55`, dark `#FF375F`
- Badge symbol: `checkmark.shield.fill`
- Effective size: authored size is preserved; no content-derived downgrade
  until a future spec defines per-section richness thresholds.

The card remains subject to the existing type/size/style orthogonality and
shared card chrome. Audit priority/state pills are payload-driven content
signals, never `CardStyle` or whole-card background changes.

## Payload envelope

```json
{
  "snapshotID": "audit-snapshot-001",
  "capturedAt": "2026-08-30T00:00:00Z",
  "scope": {
    "owner": "Owner",
    "projectID": "project-ref",
    "repository": "https://example.com/org/repo"
  },
  "mode": "baseline",
  "section": "overview",
  "partIndex": 0,
  "partCount": 1,
  "contentSHA256": "<64 lowercase hex characters>",
  "artifactSidecarID": "audit-snapshot-001:artifact-sidecar:v1",
  "artifactSidecarSHA256": "<64 lowercase hex characters>",
  "overview": {},
  "findings": [],
  "caseTimelines": [],
  "individualMetrics": [],
  "feedbackLineage": [],
  "agentRepeatMetrics": [],
  "importObservations": [],
  "artifacts": []
}
```

Exactly one section collection is populated according to `section`; the
others are absent or empty. The detailed field types and invariants are in
`data-model.md`; the complete T005 type, invariant, referential, round-trip,
public-API, and byte-boundary proof is normative in
`t005-acceptance-matrix.md`.

The overview is not a bag of display strings. Baseline uses a typed cohort
with stable case IDs and no cursors; incremental uses typed per-source cursors
and no cohort. Evidence coverage is typed and reconciled. The core summary set
contains exactly Workflow Conformance, Workflow Fitness, and Outcome Integrity
with their own locked verdict vocabularies. Task Effectiveness is a separate
summary and cannot appear as a core axis.

All `*SHA256` fields are exactly 64 lowercase hexadecimal characters. Finding
priority wire values are exactly `P0`, `P1`, `P2`, and `info`.
`ReleaseChannel` and `ImportObservationDisposition` are locked enums. Unknown
locked values fail with the existing structured payload-decode error so the
caller uses the generic card fallback; no unknown value is coerced to a known
semantic case.

## Rendering contract

- `overview` shows scope, mode, typed cohort/case IDs or typed cursors,
  reconciled evidence coverage, provenance, limitations, the three locked core
  axes side-by-side, and Task Effectiveness in its own group.
- `findings` shows explicit subject ID and responsibility layer plus
  fingerprint, axis, priority, canonical state, evidence, and remediation
  owner. It never parses source identity from the fingerprint; it emits
  optional decision intents but never writes.
- `caseTimelines` embeds ordered redacted events/attempts with stable case,
  event, attempt, actor-role, and cycle identities; the ordered reference arrays
  must resolve exactly to the embedded values.
- `individualMetrics` shows definition, numerator/denominator, window, and
  limitation. Copy is descriptive and never causal or evaluative of a person.
- `feedbackLineage` shows problem, origin/delivery, PR/merge,
  release/build/availability, observation/related-feedback identities, and the
  exact pending/effectiveness state.
- `agentRepeatMetrics` shows each role independently with common counters,
  cycle/cause breakdowns, one of five role-specific tagged counter sets, and
  supporting subject/event identities. The tag matches `actorRole`; every
  counter is non-negative and reconciles to its applicable attempt/repeat
  total. It never computes a cross-role efficiency score.
- `importObservations` shows each collision observation identity, time, source,
  explicit parent snapshot ID/hash, entity identity, accepted/rejected hashes,
  disposition, and limitation while keeping accepted content unchanged.
- `artifacts` is a typed section containing artifact entries, optional grill
  links, an optional full-report reference, and externalized optional-entity
  references. Every value binds to the envelope sidecar ID/hash. The full
  report resolves to exactly one matching `fullReport` artifact. Mandatory
  artifact URLs pass `URLPolicy`; optional artifact/grill strings remain
  untrusted and become a `Link` only when `URLPolicy.validate` accepts them.
- P0/P1 event-chain entries display finding fingerprint, event IDs, and
  revision evidence together.
- Invalid payloads use the existing generic card fallback.

## Bounded publication

The hard limit is the actual serialized UTF-8 payload size, including the
common envelope: **≤262,144 bytes**.

L5 uses deterministic two-pass packing:

1. Stable-sort entities by their contract identity.
2. Pack whole entities without splitting or truncating fields/arrays.
3. Set final `partIndex`/`partCount`, re-encode, and move the last entity to the
   next part until every final encoded payload is within the limit.

L4 supplies required entities/count inputs only. L5 computes final
published/omitted/externalized counts after packing and emits the mandatory set
before any discretionary detail budget:

- the complete overview with `PublicationCoverage`;
- every P0/P1 finding;
- the generic workflow artifact;
- every team/repository relationship artifact;
- every current P0/P1 `findingEventChain` entry.

Every required chain retains its direct URL, artifact ID, finding fingerprint,
event IDs, revision evidence, and content hash. Required/published counts in
`PublicationCoverage` must reconcile exactly. If the briefing/card budget
cannot contain every mandatory part, publication of that snapshot is rejected;
a full-report link never substitutes for a mandatory item.
`requiredP0P1FindingCount` is derived from L4's immutable mandatory-finding
input, while `publishedP0P1FindingCount` is computed only after L5 packs each
complete finding. Finding and chain count pairs reconcile independently; a
published chain cannot satisfy a missing finding.
Mandatory URLs must satisfy the same HTTPS+host rule at L5 publication and are
revalidated by `URLPolicy` at render; an unsafe mandatory URL rejects
publication rather than producing a false “published” count.

Oversized behavior is deterministic:

- An overview or individually oversized mandatory finding/artifact rejects the
  snapshot's publication.
- An individually oversized optional detail becomes an
  `ExternalizedEntityReference` only when a typed, validated full-report
  reference exists; without it, publication is rejected.
- Optional detail parts may be omitted only with reconciled
  `omittedOptionalEntityCount`/`externalizedEntityCount` and the typed full
  report. No arbitrary string truncation or array clipping is permitted.

Boundary fixtures measure the received final serialized UTF-8 `Data.count` in
the CardType/schema validation path and prove: 262,144 bytes accepted; 262,145
bytes rejected or externalized only for optional detail; oversized
overview rejected; optional detail with/without full report; oversized
mandatory P0/P1 finding or chain rejected; and the mandatory P0/P1-finding,
generic-workflow, team-relationship, and P0/P1-chain required/published pairs
equal independently.

## Accessibility and localization

- Controls meet 44 pt iOS/iPadOS and 28 pt macOS hit targets.
- Status is communicated by localized text plus tokenized pill/icon, not color
  alone.
- Repeated finding/event rows combine accessibility children.
- All user-visible strings live in the AIDashUI String Catalog.
- At least two previews cover overview and findings in different CardSize
  values without changing typography by size.
