# Data Model: Release Workflow State

This feature adds no product database or app schema. The model below defines
ephemeral workflow state and the durable Git marker contract.

## ReleaseCandidate

| Field | Type | Source | Validation |
|---|---|---|---|
| `sha` | 40-character Git object ID | `workflow_run.head_sha` or once-resolved `main` | Must resolve to a commit |
| `event_kind` | `automatic` or `manual` | GitHub event | Known value only |
| `ci_workflow` | string | `workflow_run.name` | `build` for automatic |
| `ci_conclusion` | string | `workflow_run.conclusion` | `success` for automatic |
| `head_branch` | string | event | `main` |
| `force` | boolean | manual input | Automatic is always false |

## ReleaseMarker

| Field | Type | Source | Validation |
|---|---|---|---|
| `ref` | constant | Git | `refs/tags/testflight/last-released` |
| `commit_sha` | Git commit ID | Dereferenced tag | Candidate equality/ancestry check |
| `marketing_version` | semantic version or absent | Annotated tag message | One validated metadata field |
| `legacy` | boolean | Tag shape | Lightweight/no metadata is accepted |

The marker is replaced only after strict release success. It is not a lock;
GitHub concurrency serializes the app's release jobs.

## ChangeRange

| State | Base | Head |
|---|---|---|
| Existing marker | marker commit | candidate commit |
| Missing marker, non-root | candidate first parent | candidate commit |
| Missing marker, root | empty tree | candidate commit |

`app_relevant` is true when at least one changed path matches the spec allowlist.
Manual force may override only this boolean.

## VersionIntent

| Field | Type | Rule |
|---|---|---|
| `project_version` | semantic version | Parsed from tracked `project.yml` |
| `marker_version` | semantic version or absent | Parsed from marker metadata |
| `baseline_version` | semantic version | Maximum of valid project/marker values |
| `exact_pr` | PR identity or absent | Must be provably associated with candidate |
| `minor_label` | boolean | Exact PR contains `release:minor` |
| `effective_version` | semantic version | Baseline, or one minor increment when labelled |

API failure or contradictory associations are invalid states. A proven direct
push/no-PR association is valid and implies `minor_label=false`.

## ReleaseOutcome

| State | Meaning | Side effects |
|---|---|---|
| `skipped_duplicate` | Marker already equals candidate | Summary only |
| `skipped_irrelevant` | Safe range has no app path and no force | Summary only |
| `failed_preflight` | Invalid event, object, ancestry, label, version, or secrets | No upload/marker move |
| `failed_release` | Tooling/signing/build/upload/distribution failed | No marker move |
| `failed_marker` | Upload succeeded but marker persistence failed | Failed run, no automatic retry |
| `released` | Strict lane and marker update succeeded | Annotated marker + success summary |

## State transitions

```text
selected
  ├─ unsafe/invalid ─> failed_preflight
  ├─ duplicate ──────> skipped_duplicate
  └─ safe
      ├─ irrelevant ─> skipped_irrelevant
      └─ eligible ───> releasing
                         ├─ lane failure ─> failed_release
                         └─ lane success ─> persisting_marker
                                              ├─ failure ─> failed_marker
                                              └─ success ─> released
```
