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
  "overview": {},
  "findings": [],
  "caseTimelines": [],
  "individualMetrics": [],
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
- `findings` shows fingerprint, axis, priority, canonical state, evidence,
  and remediation owner. It emits optional decision intents but never writes.
- `caseTimelines` shows ordered redacted events/attempts with stable IDs,
  roles, timestamps, revision SHA, and limitations.
- `individualMetrics` shows definition, numerator/denominator, window, and
  limitation. Copy is descriptive and never causal or evaluative of a person.
- `artifacts` shows artifact identity/hash/evidence relationships. A URL is a
  `Link` only when `URLPolicy.validate` accepts it; otherwise it is text.
- P0/P1 event-chain entries display finding fingerprint, event IDs, and
  revision evidence together.
- Invalid payloads use the existing generic card fallback.

## Bounded publication

- Each card payload is at most 256 KB encoded.
- L5 partitions collections on whole entity boundaries and records
  `partIndex`/`partCount`; it never splits or truncates an individual finding
  or evidence reference.
- The overview is always first. All P0/P1 finding and event-chain parts are
  emitted before P2/info details.
- If the daily briefing card budget prevents complete local detail, the
  overview contains an explicit omitted count/limitation and a validated full
  report artifact entry. No omission is silent.

## Accessibility and localization

- Controls meet 44 pt iOS/iPadOS and 28 pt macOS hit targets.
- Status is communicated by localized text plus tokenized pill/icon, not color
  alone.
- Repeated finding/event rows combine accessibility children.
- All user-visible strings live in the AIDashUI String Catalog.
- At least two previews cover overview and findings in different CardSize
  values without changing typography by size.
