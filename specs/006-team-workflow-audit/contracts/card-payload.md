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
`data-model.md`.

## Rendering contract

- `overview` shows scope, mode, cohort or cursors, evidence coverage,
  provenance, limitations, the three core axes side-by-side, and Task
  Effectiveness in its own group.
- `findings` shows explicit subject ID and responsibility layer plus
  fingerprint, axis, priority, canonical state, evidence, and remediation
  owner. It never parses source identity from the fingerprint; it emits
  optional decision intents but never writes.
- `caseTimelines` shows ordered redacted events/attempts with stable IDs,
  roles, timestamps, revision SHA, and limitations.
- `individualMetrics` shows definition, numerator/denominator, window, and
  limitation. Copy is descriptive and never causal or evaluative of a person.
- `feedbackLineage` shows problem, origin/delivery, PR/merge,
  release/build/availability, observation/related-feedback identities, and the
  exact pending/effectiveness state.
- `agentRepeatMetrics` shows each role independently with common counters,
  cycle/cause breakdowns, role-specific counters, and supporting subject/event
  identities. It never computes a cross-role efficiency score.
- `importObservations` shows each collision observation identity, time, source,
  explicit parent snapshot ID/hash, entity identity, accepted/rejected hashes,
  disposition, and limitation while keeping accepted content unchanged.
- `artifacts` shows artifact identity/hash/evidence relationships and the
  sidecar identity/hash provenance. Mandatory artifact URLs have already passed
  publication validation; optional artifact/grill URLs become a `Link` only
  when `URLPolicy.validate` accepts them and otherwise remain text.
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

Boundary fixtures encode the final payload and prove: 262,144 bytes accepted;
262,145 bytes rejected or externalized only for optional detail; oversized
overview rejected; optional detail with/without full report; oversized
mandatory P0/P1 chain rejected; and every mandatory required/published count
equal.

## Accessibility and localization

- Controls meet 44 pt iOS/iPadOS and 28 pt macOS hit targets.
- Status is communicated by localized text plus tokenized pill/icon, not color
  alone.
- Repeated finding/event rows combine accessibility children.
- All user-visible strings live in the AIDashUI String Catalog.
- At least two previews cover overview and findings in different CardSize
  values without changing typography by size.
