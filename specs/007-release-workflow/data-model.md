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
| `expected_remote_oid` | Exact remote marker object ID observed during eligibility, or expected absence for authorized bootstrap; consumed by the lease-guarded compare-and-swap |

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

## Secret-free summary facts

The workflow summary records only the candidate SHA/source, observed marker
relationship/object ID, relevance/force decision, whether the lane ran, marker
compare-and-swap result, native job conclusion, run URL on success, and any
cleanup warning. The summary is evidence, not durable workflow state, and
defines no phase-specific outcome taxonomy.

## Processing sequence (not persisted state)

```text
event -> validate/pin candidate -> fetch marker
  -> equal: skip
  -> invalid: fail
  -> missing + manual force: eligible bootstrap
  -> missing otherwise: fail
  -> ancestor: classify marker..candidate
       -> irrelevant and !force: skip
       -> eligible: existing lane
            -> pre-marker failure: cleanup, marker unchanged
            -> lane success: lease-guarded compare-and-swap observed marker to candidate
                 -> rejected: cleanup; this run did not mutate marker
                 -> accepted: release success; cleanup may warn only
```

There is no queue, cursor, attempt, confirmation, quarantine, recovery record,
annotated marker metadata, terminal-outcome state machine, or exactly-once
guarantee.
