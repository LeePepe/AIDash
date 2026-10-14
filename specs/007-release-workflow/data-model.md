# Data Model: Minimal CI-Gated TestFlight Release

This workflow stores no product data. Its sole durable release-progress state
is the existing Git tag `testflight/last-released`.

## ReleaseCandidate

| Field | Meaning |
|---|---|
| `source` | `automatic` or `manual` |
| `sha` | Pinned 40-hex commit selected from `workflow_run.head_sha` or official `main` |
| `force` | Manual relevance-only override; false for automatic runs |

Validation: automatic payload identity, same-repository push provenance,
successful `main`, valid commit, and reachability from fetched official main.

## ReleaseMarker

| Field | Meaning |
|---|---|
| `ref` | `refs/tags/testflight/last-released` |
| `sha` | Commit currently recorded by the lightweight tag |
| `state` | `missing`, `equal`, `ancestor`, or `invalid` |

`invalid` includes a non-commit target or a marker not ancestral to the
candidate. It fails closed. The marker has no schema/version/build metadata.
Missing state fails automatic execution; manual `force=true` may bootstrap.

## ComparisonRange

| Marker state | Range |
|---|---|
| ancestor | `marker..candidate` |
| missing + manual force | no range required; bootstrap exact candidate |
| missing + other execution | none; fail |
| equal | none; skip |
| invalid | none; fail |

## RelevanceDecision

| Field | Meaning |
|---|---|
| `matched` | At least one changed path matches the AIDash allowlist |
| `force` | Manual force input |
| `eligible` | safe marker state and (`matched` or `force`) |
| `reason` | concise secret-free explanation |

## ReleaseOutcome

- `skipped_released`
- `skipped_irrelevant`
- `failed_preflight`
- `failed_release`
- `failed_marker_update`
- `released`

The outcome is summary-only, not durable state. Every failure leaves the public
marker unchanged. `released` requires lane success followed by marker movement.

## State transitions

```text
event -> validate/pin candidate -> fetch marker
  -> equal: skip
  -> invalid: fail
  -> missing + manual force: eligible bootstrap
  -> missing otherwise: fail
  -> ancestor: classify marker..candidate
       -> irrelevant and !force: skip
       -> eligible: existing lane
            -> failure: cleanup, marker unchanged
            -> success: move marker
                 -> push failure: cleanup, marker unchanged
                 -> push success: released
```

There is no queue, cursor, attempt, confirmation, quarantine, recovery record,
annotated marker metadata, or exactly-once guarantee.
