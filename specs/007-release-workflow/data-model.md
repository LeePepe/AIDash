# Data Model: Minimal Release Workflow

This feature adds no product or durable workflow schema. It uses one ephemeral
candidate, one existing Git marker, one ephemeral relevance result, and one
secret-free ephemeral keychain snapshot.

## ReleaseCandidate

| Field | Source | Rule |
|---|---|---|
| `entry_kind` | GitHub event | `automatic` or `manual` |
| `sha` | `workflow_run.head_sha` or checked-out `main` | Automatic is exact event SHA; manual is current `main` |
| `force` | manual input | Defaults false; automatic is always false |

Automatic candidates exist only for a successful same-repository `build` push
on `main`. Checkout uses full history and tags.

## ReleaseMarker

| Field | Source | Rule |
|---|---|---|
| `ref` | Git | Constant `refs/tags/testflight/last-released` |
| `commit` | Dereferenced ref | Required for non-forced relevance; invalid/missing fails closed |

The marker contains no workflow-owned schema, version, build number, lease,
cursor, or journal. It moves to the candidate only after successful upload.

## RelevanceResult

| Field | Type | Rule |
|---|---|---|
| `changed_paths` | newline-delimited paths | Exact output of `git diff --name-only marker..candidate` |
| `relevant` | boolean | True when any path matches an allowed app root |
| `reason` | string | Concise secret-free result for logs/summary |

Allowed roots are `Apps/AIDashApp/`, `Packages/AIDashCore/`,
`Packages/AIDashUI/`, `Packages/DesignKit/`, `Configs/`, `fastlane/`, plus the
exact root file `project.yml`. Matching is anchored at repository root.

## EphemeralKeychainState

This secret-free, permission-restricted run-scoped file exists only when the
build/upload path prepares signing state.

| Field | Source | Restore rule |
|---|---|---|
| `search_list` | `security list-keychains -d user` before mutation | Restore the exact ordered list |
| `default_keychain` | `security default-keychain -d user` before mutation | Restore the exact prior default |
| `login_was_locked` | non-mutating pre-unlock probe | Relock only when true |
| `login_settings` | `security show-keychain-info` before mutation | Restore timeout/lock-on-sleep exactly |
| `temporary_keychain` | unique path under the run temp directory | Delete during cleanup |
| `snapshot_path` | unique path under the run temp directory | Delete during cleanup |

Partition ACLs are not captured or mutated. Existing non-interactive
`apple-tool`/`codesign` access is a runner prerequisite and fails closed when
absent. The snapshot contains no password, credential, or signing secret.

## State flow

```text
event -> guard -> exact checkout -> marker diff -> classifier
                                      ├─ irrelevant/no force -> summary + stop
                                      └─ relevant/force -> build+upload
                                                            ├─ failure -> stop; marker unchanged
                                                            └─ success -> move marker
always -----------------------------------------------------> restore/delete temp state
                                                              ├─ success -> released
                                                              └─ failure after marker
                                                                 -> failed_cleanup_after_release;
                                                                    marker stays advanced
```

No queue, cursor, skip record, attempt record, confirmation record, annotated
marker metadata, recovery entity, version intent, or distribution-proof entity
exists. `EphemeralKeychainState` is deleted by cleanup and is never a durable
workflow cursor or release record.
