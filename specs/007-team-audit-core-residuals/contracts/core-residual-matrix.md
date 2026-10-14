# Contract: Hidden Team Audit Core Residual Matrix

This matrix is the complete implementation acceptance for Decision B. It does
not authorize registration, discovery, a public API, or another product layer.

## Exact implementation surface

Allowed:

1. `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`
2. `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`

Every other path is forbidden. In particular, do not modify `CardType.swift`,
`EffectiveCardSize.swift`, `CardPayloadProtocol.swift`, `Validation/**`, generic
Core tests, public API tests, AIDashUI, DesignKit, Apps, CLI, aidata, specs,
context, hooks, workflows, or the constitution during implementation.

## Normative matrix

| ID | Positive proof | Required negative proof | Expected result |
|---|---|---|---|
| CR-001 | Artifact `caseID == nil` | — | Accept |
| CR-002 | Present artifact case matches one unique catalog case | Blank present case; dangling case | Accept positive; reject negatives |
| CR-003 | Unique catalog case identities | Duplicate catalog case identity | Reject duplicate before reference resolution |
| CR-004 | Overview full report matches one `fullReport` artifact by the complete tuple | Mutate kind only | Reject |
| CR-005 | Same valid overview fixture | Mutate artifact ID only | Reject |
| CR-006 | Same valid overview fixture | Mutate content hash only | Reject |
| CR-007 | Same valid overview fixture | Mutate raw URL only | Reject |
| CR-008 | Same valid overview fixture | Mutate sidecar ID only | Reject |
| CR-009 | Same valid overview fixture | Mutate sidecar hash only | Reject |
| CR-010 | Artifact-section full report matches the same complete tuple | No match; more than one complete match | Reject |
| CR-011 | Externalized report equals the already resolved report | Mutate embedded artifact ID only | Reject |
| CR-012 | Same valid externalization | Mutate embedded content hash only | Reject |
| CR-013 | Same valid externalization | Mutate embedded raw URL only | Reject |
| CR-014 | Same valid externalization | Mutate embedded sidecar ID only | Reject |
| CR-015 | Same valid externalization | Mutate embedded sidecar hash only | Reject |
| CR-016 | `encodedByteCount == 1` and another representative positive count | Zero; negative | Accept positives; reject non-positive |
| CR-017 | Fixed reason `exceedsInlinePayloadLimit` | Unknown reason raw value | Accept fixed value; decoding fails for unknown |
| CR-018 | Each of the eight allowed externalizable kinds round-trips | Unknown raw value | Exact equality; decoding fails for unknown |
| CR-019 | Enum contains optional-only values | Compile-time/API inspection finds mandatory kind | No mandatory kind is representable |
| CR-020 | Neutral IDs, hashes, and `https://example.com/...` raw URLs | Any real account/workspace/employer/machine identity | Fixture hygiene passes |
| CR-021 | Baseline forbidden anchor files are unchanged | Any change outside two-path allowlist | Diff rejected |
| CR-022 | `CardType.allCases.count == 10` existing tripwire remains | `teamAudit` appears in registration/discovery/public API | Diff rejected |

## Complete tuple definitions

Catalog resolution tuple:

```text
(kind == fullReport,
 artifactID,
 contentSHA256,
 rawURL,
 sidecarID,
 sidecarSHA256)
```

Resolved-versus-externalized equality tuple:

```text
(artifactID,
 contentSHA256,
 rawURL,
 sidecarID,
 sidecarSHA256)
```

`kind` is checked while resolving the catalog value; the embedded
`FullReportReference` does not carry a second kind discriminator.

## Exact optional-only wire vocabulary

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

There is no unknown fallback and no overview, P0/P1 finding, generic workflow,
team relationship, or finding-chain value.

## Compatibility assertions

- Existing ten-card behavior is unchanged.
- Nil artifact case bindings remain valid.
- Existing AIDashCore URL policy remains unchanged and is not copied into the
  Types model. Exact raw URL equality is referential identity, not
  actionability.
- No existing test is deleted, weakened, renamed, or replaced.
- Historical closed findings are outside this matrix and need no duplicate
  proof.
