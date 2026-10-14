# Data Model: Release Workflow State

This feature adds no product database or app schema. The model defines
ephemeral workflow state, App Store Connect evidence, and strict operational Git
refs. Every operational tag points to the exact candidate commit. Unknown,
missing, empty, duplicate, malformed, or target-mismatched metadata is invalid
unless the public-marker legacy rule explicitly permits a lightweight tag.

## ReleaseCandidate

| Field | Type | Source | Validation |
|---|---|---|---|
| `sha` | 40-character Git object ID | `workflow_run.head_sha` or once-resolved protected `main` | Resolves to a commit reachable from fetched protected `main` |
| `entry_kind` | `automatic` or `manual` | GitHub event | Known value only |
| `source_run_id` | positive integer | GitHub Actions | Exact run is queryable |
| `source_run_attempt` | positive integer | GitHub Actions | Exact attempt is queryable |
| `source_workflow_path` | string | Actions API | `.github/workflows/build.yml` for automatic |
| `source_event` | string | Actions API | `push` for automatic |
| `source_repository` | string | event/API | Equals `github.repository` |
| `source_conclusion` | string | Actions API | `success` for automatic |
| `head_branch` | string | event/API | `main` |
| `force` | boolean | manual input | Automatic is always false; changes only relevance |
| `provenance_state` | enum | validation | `untrusted`, `proven`, or `invalid`; only `proven` may enqueue |

## ReleaseQueueBoundary

| Field | Type | Rule |
|---|---|---|
| `ref` | constant | `refs/tags/testflight/queue-start` |
| `commit_sha` / `candidate` | Git commit ID | Unique protected-`main` first-parent commit introducing `release-contract-schema: 1` |
| `schema` | integer | Exactly `1` in an annotated tag |
| `boundary_kind` | constant | `release-contract-activation` |

The workflow file contains exactly one literal sentinel. With no public marker,
zero/multiple first-parent introductions or an activation commit later than the
candidate fail closed. The boundary is create-only and contains no source-run
identity. Concurrent creators may produce
different annotated tag object IDs; an exact target plus semantic-metadata
re-observation is accepted after refetch. Replacement, deletion, lightweight
shape, wrong target, or mismatched metadata fails closed.

## ReleaseQueueEntry

| Field | Type | Rule |
|---|---|---|
| `ref` | unique ref | `refs/tags/testflight/queue/<run-id>-<attempt>-<sha>` |
| `commit_sha` | Git commit ID | Equals the candidate and the SHA encoded in the ref |
| `schema` | integer | Exactly `1` |
| `entry_kind` | enum | `automatic` or `manual` |
| `source_run_id` / `source_run_attempt` | positive integers | Revalidated through Actions API before drain |
| `force` | boolean | `false` for automatic; manual value affects relevance only |

Admission creates the annotated tag before job-level release concurrency. An
exact retry is idempotent; a collision or mismatch fails. The drain worker
reconciles all successful protected-main build runs in the bounded range,
creates missing automatic entries, de-duplicates candidate SHAs, and sorts
entries along protected `main` first-parent ancestry.

## ReleaseMarker

| Field | Type | Source | Validation |
|---|---|---|---|
| `ref` | constant | Git | `refs/tags/testflight/last-released` |
| `object_shape` | `lightweight` or `annotated` | Git object type | Only a genuine lightweight tag receives legacy fallback |
| `commit_sha` | Git commit ID | Dereferenced tag | Equality/ancestry and no-rewind checks |
| `schema` | integer or absent | Annotated message | Exactly `1`; absent only for genuine lightweight legacy |
| `marketing_version` | semantic version or absent | Annotated message | Exactly one valid field; absent only for lightweight legacy |
| `build_number` | positive integer or absent | Annotated message | Exactly one valid field; absent only for lightweight legacy |

An annotated marker with no metadata is not legacy. Missing, empty, malformed,
duplicate, or unknown annotated fields fail preflight. The marker moves only
after a durable confirmation and only by compare-and-swap against the fetched
prior tag-object ID.

## ReleaseAttempt

| Field | Type | Rule |
|---|---|---|
| `ref` | candidate-keyed ref | `refs/tags/testflight/attempted/<sha>` |
| `commit_sha` / `candidate` | Git commit ID | Both equal the candidate and ref suffix |
| `schema` | integer | Exactly `1` |
| `marketing_version` | semantic version | Effective version selected by preflight |
| `groups` | canonical non-empty list | Trimmed, unique intended internal groups |
| `source_run_id` / `source_run_attempt` | positive integers | Release worker that crosses the attempt boundary |

The remote annotated attempt is create-only and must be positively observed
immediately before the sole permitted `fastlane ios beta` invocation. Existing
valid attempt without confirmation is `quarantined_unknown`; automatic or
manual force cannot invoke the lane again. An unresolved attempt on the
candidate ancestry blocks later candidates.

## ReleaseConfirmation

| Field | Type | Rule |
|---|---|---|
| `ref` | candidate-keyed ref | `refs/tags/testflight/confirmed/<sha>` |
| `commit_sha` / `candidate` | Git commit ID | Equal candidate and ref suffix |
| `schema` | integer | Exactly `1` |
| `marketing_version` | semantic version | Exactly matches the attempt |
| `build_number` | positive integer | The single parsed Fastlane selection or explicit recovery evidence |
| `groups` | canonical non-empty list | Exactly matches attempt groups |
| `source_run_id` / `source_run_attempt` | positive integers | Upload run, or explicit reconciliation run |

Confirmation is create-only and may be published only after ASC proves the
exact version/build and membership in every intended group. A normal release
creates it after the lane; an explicit marker-only recovery may create it for an
attempted-only SHA after the same ASC proof. Neither path permits another
upload.

## ChangeRange

| State | Base | Head |
|---|---|---|
| Existing public marker | marker commit | candidate commit |
| Missing marker, non-root | candidate first parent | candidate commit |
| Missing marker, root | empty tree | candidate commit |

`app_relevant` is true when at least one changed path matches the spec allowlist.
Manual force may override only this boolean. After each successful candidate,
the advanced public marker becomes the next candidate's base.

## VersionIntent

| Field | Type | Rule |
|---|---|---|
| `project_version` | semantic version | Parsed from tracked `project.yml` |
| `marker_version` | semantic version or absent | Valid annotated marker, or absent for genuine lightweight legacy |
| `baseline_version` | semantic version | Maximum of valid project/marker values |
| `exact_pr` | PR identity or absent | Provably associated with candidate |
| `minor_label` | boolean | Exact PR contains `release:minor` |
| `effective_version` | semantic version | Baseline, or one minor increment when labelled |

API failure or contradictory associations are invalid states. A proven direct
push/no-PR association is valid and implies `minor_label=false`.

## ReleaseOutcome

| State | Meaning | Side effects |
|---|---|---|
| `rejected_provenance` | Event is not a trusted protected-main source | Summary only; no checkout/self-hosted/secrets |
| `queued` | Proven intent is durable before release concurrency | Queue entry only |
| `skipped_duplicate` | Public marker equals candidate | Summary + queue cleanup; no upload |
| `skipped_irrelevant` | Safe range has no app path and no force | Summary + queue cleanup; no upload |
| `failed_preflight` | Invalid queue/state/ancestry/label/version/group/secrets | No attempt or upload |
| `quarantined_unknown` | Attempt exists without confirmation | Attempt and queue retained; descendants blocked; no re-upload |
| `confirmed_pending_marker` | Confirmation exists but public marker lags | Marker-only reconciliation; no Fastlane |
| `failed_release` | Lane or postflight proof failed after attempt | Quarantined attempt; no confirmation/marker move |
| `reconciled` | Existing/new confirmation advanced public marker | CAS marker + queue cleanup; no upload in recovery run |
| `released` | One lane, ASC proof, confirmation, and marker CAS succeeded | Confirmation + annotated public marker + summary |

## State transitions

```text
event
  ├─ untrusted ───────────────────────────────> rejected_provenance
  └─ proven ──> durable queue ──> serialized/revalidated
                                  ├─ duplicate ─> skipped_duplicate
                                  ├─ irrelevant ─> skipped_irrelevant
                                  ├─ invalid ─────> failed_preflight
                                  ├─ confirmed ───> marker-only CAS ─> reconciled
                                  ├─ attempted-only ────────────────> quarantined_unknown
                                  └─ eligible ─> preflight groups
                                                  ├─ fail ─> failed_preflight
                                                  └─ create attempt
                                                       └─ invoke lane once
                                                            ├─ fail/unknown ─> quarantined_unknown
                                                            └─ ASC build/group proof
                                                                 ├─ fail ─> quarantined_unknown
                                                                 └─ create confirmation
                                                                      └─ marker CAS
                                                                           ├─ fail ─> confirmed_pending_marker
                                                                           └─ released
```

The public marker is release progress, not a lock. Job-level concurrency
serializes drain workers; durable queue refs survive pending-worker replacement;
attempt/confirmation refs prevent a scheduler or network ambiguity from
authorizing a second upload.
