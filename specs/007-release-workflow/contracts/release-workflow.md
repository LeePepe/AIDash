# Contract: Minimal TestFlight Release Workflow

## Entrypoints

### Automatic

Register `workflow_run` for `build`, `main`, `completed`. Continue only for
the exact `.github/workflows/build.yml` workflow, same-repository `push`,
successful conclusion, `main` head branch, and valid `head_sha`.

### Manual

Keep `workflow_dispatch.force` as a boolean defaulting to false. Pin official
protected `main` once. Force bypasses only path relevance and may bootstrap a
missing marker; non-force missing-marker execution fails.

## Job and candidate

- One job on `[self-hosted, aidash-mac]`.
- One `testflight` concurrency group, `cancel-in-progress: false`.
- Plain job-level `permissions: contents: write`.
- Checkout the pinned candidate with `fetch-depth: 0` and
  `persist-credentials: false`; never substitute a newer ref. Supply the job
  token only to the marker-movement step.
- Validate candidate reachability from fetched official `main` before signing
  secrets or Fastlane.

## Marker and relevance

The only durable state is lightweight tag `testflight/last-released`.

- equal candidate: skip, even with force;
- ancestor marker: classify `marker..candidate`;
- missing marker with manual force: bootstrap the pinned candidate;
- missing marker otherwise or any unsafe relationship: fail without moving the
  marker.

The AIDash allowlist is:

```text
Apps/AIDashApp/**
Packages/AIDashCore/**
Packages/AIDashUI/**
Packages/DesignKit/**
Configs/**
project.yml
fastlane/**
```

## Release and credentials

Invoke unchanged `fastlane ios beta`. Preserve the five current secrets,
login-keychain signing, runtime profile fetch, global build-number allocation,
tracked marketing version, and lane-owned internal distribution behavior.
Reference ASC and keychain secrets only in the release path.

Move the marker to the exact candidate only after the lane returns success.
Use ordinary contents-write tag update; no CAS-only job, annotated metadata, or
additional ref.

## Failure and cleanup

Every invalid state or command failure is terminal. No automatic retry,
rollback, or recovery state exists. An `always()` step removes workflow-created
temporary refs/signing artifacts, restores keychain state changed by the run,
and writes a secret-free summary.

Upload and marker movement are not atomic. If upload succeeds and tag push
fails, a later run may upload again. This contract does not promise exactly
once.

## Verification contract

- concise Python 3.9 relevance-classifier cases;
- stable structural assertions for entrypoints, exact checkout, concurrency,
  force boundary, success-only marker movement, credential step scope, and
  cleanup;
- action/workflow lint and repository RepoInfra gates;
- no shadow provenance/marker/version/distribution/outcome policy model.
