# Data Model: Release Workflow State

This feature adds no product database or app schema. The model defines an
ephemeral release candidate, the sole durable public release marker, the
comparison range, release intent, distribution evidence, and per-run outcomes.
No queue, cursor, skip, upload journal, quarantine, or recovery entity exists.

## ReleaseCandidate

| Field | Type | Source | Validation |
|---|---|---|---|
| `sha` | 40-character Git object ID | `workflow_run.head_sha` or once-resolved protected `main` | Resolves to a commit reachable from freshly fetched official protected `main` |
| `entry_kind` | `automatic` or `manual` | GitHub event | Known value only |
| `source_run_id` | positive integer | GitHub Actions | Recorded for provenance/summary, never as durable release state |
| `source_workflow_path` | string or absent | Actions API | Exactly `.github/workflows/build.yml` for automatic |
| `source_event` | string | event/API | Exactly `push` for automatic |
| `source_repository` | string | event/API | Equals `github.repository` |
| `source_conclusion` | string | event/API | Exactly `success` for automatic |
| `head_branch` | string | event/API | Exactly `main` |
| `force` | boolean | manual input | Automatic is false; manual true changes only relevance |
| `provenance_state` | enum | validation | `untrusted`, `proven`, or `invalid`; only `proven` reaches the release worker |

The candidate is immutable for the run. Automatic processing never substitutes
a newer `main` tip for the CI-verified SHA. Manual processing resolves official
protected `main` once in hosted read-only provenance and pins that SHA.

## ReleaseMarker

| Field | Type | Source | Validation |
|---|---|---|---|
| `ref` | constant | Git | `refs/tags/testflight/last-released` |
| `object_shape` | `missing`, `lightweight`, or `annotated` | Git object type | Only a genuine lightweight tag receives legacy fallback |
| `tag_object_id` | Git object ID or absent | fetched remote ref | Compare-and-swap lease for update |
| `commit_sha` | Git commit ID or absent | dereferenced tag | Equality/ancestry/no-rewind checks |
| `schema` | integer or absent | annotated message | Exactly `1`; absent only for missing/lightweight state |
| `marketing_version` | semantic version or absent | annotated message | Exactly one valid field for annotated state |
| `build_number` | positive integer or absent | annotated message | Exactly one valid field for annotated state |

An annotated marker with no metadata is not legacy. Missing, empty, malformed,
duplicate, or unknown annotated metadata, or a marker that does not dereference
to a commit, fails preflight. The marker advances only after build, upload, and
exact distribution proof, and only by compare-and-swap against the fetched
prior tag-object ID (or confirmed
absence for bootstrap). It is the only durable release-progress state.

## MarkerRelationship

| State | Meaning | Release behavior |
|---|---|---|
| `missing` | No public marker exists | Use missing-marker bootstrap range |
| `equal` | Marker commit equals candidate | Absolute no-upload skip |
| `ancestor` | Marker is an ancestor of candidate | Evaluate accumulated `marker..candidate` range |
| `descendant` | Marker is a descendant of stale candidate | Skip; never rewind |
| `unrelated` | Neither commit is ancestor of the other | Fail closed |
| `invalid` | Marker cannot be strictly parsed/dereferenced | Fail closed |

## ChangeRange

| Marker state | Base | Head | Meaning |
|---|---|---|---|
| Existing ancestor marker | marker commit | candidate | All changes since last recorded successful release |
| Missing marker, non-root candidate | candidate first parent | candidate | Only the candidate's introducing delta |
| Missing marker, root candidate | empty tree | candidate | Root contents |

`app_relevant` is true when at least one changed path matches the exact spec
allowlist. Manual `force=true` may override only this boolean. Skips and failures
do not persist anything; because the marker remains unchanged, a later
descendant naturally sees the accumulated existing-marker range. Missing-marker
bootstrap deliberately remains a single-commit delta so a workflow-only
enabling merge does not release the entire repository.

## VersionIntent

| Field | Type | Rule |
|---|---|---|
| `project_version` | semantic version | Parsed from tracked `project.yml` |
| `marker_version` | semantic version or absent | Valid annotated marker, or absent for missing/genuine lightweight legacy marker |
| `baseline_version` | semantic version | Maximum of valid project/marker values |
| `exact_pr` | PR identity or absent | Provably associated with candidate |
| `minor_label` | boolean | Exact candidate PR contains `release:minor` |
| `effective_version` | semantic version | Baseline, or one minor increment when labelled |

API failure or contradictory associations are invalid. A proven direct push or
no-associated-PR candidate is valid and implies `minor_label=false`.

## DistributionProof

| Field | Type | Rule |
|---|---|---|
| `intended_groups` | canonical non-empty list | Comma split, trimmed, unique; every exact group exists before Fastlane |
| `selected_build_number` | positive integer | Exactly one value parsed from the existing lane output |
| `selected_version` | semantic version | Equals `effective_version` |
| `group_membership` | set of group names | ASC proves the selected version/build belongs to every intended group |

The marker cannot advance until all fields are exact and unambiguous. Strict
mode alone is not proof of group distribution.

## ReleaseOutcome

| State | Meaning | Durable side effect |
|---|---|---|
| `rejected_provenance` | Event is not a trusted protected-main source | None |
| `skipped_released` | Marker equals candidate | None |
| `skipped_stale` | Marker is a descendant of candidate | None |
| `skipped_irrelevant` | Applicable range has no app path and no force | None |
| `failed_preflight` | Invalid marker/history/version/group/secrets | None |
| `failed_release` | Build, lane, or distribution proof failed | None |
| `failed_marker_update` | Release/proof completed but marker CAS failed | None; external upload may exist |
| `released` | Build/upload/distribution proof and marker CAS succeeded | Annotated public marker advances to candidate |

Every run reaching eligibility evaluation summarizes its own outcome. A
platform-replaced pending run is not assigned an eventual surrogate summary.

## State transitions

```text
event
  ├─ untrusted ─────────────────────────────> rejected_provenance
  └─ proven ──> serialized release worker ──> refetch/revalidate marker
                                              ├─ equal ─────> skipped_released
                                              ├─ descendant > skipped_stale
                                              ├─ unrelated/invalid > failed_preflight
                                              └─ ancestor/missing > change range
                                                                     ├─ irrelevant/no force > skipped_irrelevant
                                                                     └─ eligible > version/group/secret preflight
                                                                                   ├─ fail > failed_preflight
                                                                                   └─ Fastlane
                                                                                       ├─ fail > failed_release
                                                                                       └─ exact ASC distribution proof
                                                                                           ├─ fail > failed_release
                                                                                           └─ marker CAS
                                                                                               ├─ fail > failed_marker_update
                                                                                               └─ released
```

The concurrency group is a lock, not durable state. Any non-success outcome
leaves the marker unchanged. A later merge or manual run performs a new
evaluation; no automatic retry/rollback occurs. If an external upload succeeded
before marker failure, this marker-only model cannot identify it and does not
promise exactly-once upload.
