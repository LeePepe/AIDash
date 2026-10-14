# Data Model: Minimal Release Workflow

This feature adds no product schema. It uses one ephemeral candidate, one
existing Git marker, and one ephemeral relevance result.

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

## State flow

```text
event -> guard -> exact checkout -> marker diff -> classifier
                                      ├─ irrelevant/no force -> summary + stop
                                      └─ relevant/force -> build+upload
                                                            ├─ failure -> stop
                                                            └─ success -> move marker
always -----------------------------------------------------> cleanup temp state
```

No queue, cursor, skip record, attempt record, confirmation record, annotated
marker metadata, recovery entity, version intent, or distribution-proof entity
exists.
