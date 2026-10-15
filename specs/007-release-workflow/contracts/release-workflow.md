# Contract: Minimal TestFlight Release Workflow

## Entrypoints

### Automatic

- Event: `workflow_run`
- Workflow: `build`
- Activity/branch: `completed` on `main`
- Job guard: conclusion `success`, source event `push`, head branch `main`, and
  source repository equal to `github.repository`
- Candidate: exact `github.event.workflow_run.head_sha`

### Manual

- Event: `workflow_dispatch`
- Candidate: current repository `main`
- Input: existing boolean `force`, default `false`
- Force bypasses marker availability/equality and relevance only; it does not
  bypass build, signing, upload, cleanup, or marker-after-upload ordering.

## Job and checkout

- One job runs on `[self-hosted, aidash-mac]`.
- Automatic and manual runs share concurrency group `testflight` with
  `cancel-in-progress: false`.
- The job has `permissions: contents: write`. No separate provenance or marker
  permission job exists.
- `actions/checkout@v4` uses the selected candidate, `fetch-depth: 0`, and tags.
  Automatic checkout must be the exact workflow-run SHA.

## Relevance

For non-forced execution:

1. Fetch and dereference `testflight/last-released`.
2. Run `git diff --name-only <marker>..<checked-out-head>`.
3. Pass those exact newline-delimited paths to the production classifier at
   `scripts/ci/tests/test_testflight_relevance.py`.
4. Treat these roots as relevant:

   ```text
   Apps/AIDashApp/**
   Packages/AIDashCore/**
   Packages/AIDashUI/**
   Packages/DesignKit/**
   Configs/**
   project.yml
   fastlane/**
   ```

5. If irrelevant, append one concise line to `$GITHUB_STEP_SUMMARY` and stop
   before any secret-bearing step.

Missing/invalid marker, Git failure, classifier error, or ambiguous output
fails closed. The workflow creates no cursor, skip record, queue, journal,
recovery ref, or second marker.

## Build and upload

- Reuse the existing `fastlane ios beta` lane and self-hosted tooling checks.
- Exactly one build/upload step owns all five secret references:
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `ASC_TEAM_ID`, and
  `KEYCHAIN_PASSWORD`.
- That step validates secret presence, captures the exact original user
  keychain search list, default keychain, login-keychain lock state, and
  login-keychain auto-lock settings in a permission-restricted secret-free
  run-state file; creates a run-scoped temporary keychain and uses it as the
  temporary user default/search-list head while retaining login in the list;
  unlocks login and temporarily adjusts auto-lock only as needed; and invokes
  the lane.
- The workflow does not call `set-key-partition-list` or otherwise mutate a
  private-key partition ACL. Existing non-interactive `apple-tool`/`codesign`
  access is a runner prerequisite and is checked before the lane; absence fails
  closed.
- No earlier/later step references those secrets. Fastlane, global build-number
  allocation, signing/profile lookup, and internal distribution remain unchanged.

## Marker movement

- Only a successful build/upload step enables marker movement.
- Move the plain `testflight/last-released` tag to the checked-out candidate and
  push it with the job's normal contents-write token.
- Do not add an annotated metadata schema, CAS-only token/job, lease protocol,
  or alternate release record.
- Any failure before successful marker movement leaves the remote marker
  unchanged. There is no retry, rollback, alternate runner, or fallback
  credential path.

## Cleanup

A final step with `if: always()`:

- restores the exact captured user keychain search list and default keychain;
- restores the captured login-keychain auto-lock settings;
- relocks the login keychain only when it began locked;
- deletes the run-scoped temporary keychain and secret-free state file;
- deletes only local temporary release tags created by the run;
- does not reference signing secrets or modify/delete the remote marker;
- fails the job if restoration/removal is incomplete.

The snapshot is written before any mutation. When build/upload never began and
no snapshot exists, cleanup treats restoration as a no-op and still removes any
local temporary release tag created by the run.

If cleanup fails before marker movement, the remote marker remains unchanged.
If it fails after upload and successful marker movement, the terminal outcome
is `failed_cleanup_after_release`; the marker remains at the uploaded SHA, and
the workflow performs no rollback or automatic retry.

## Summary

- Irrelevant non-forced execution writes one clear skip line naming the range
  and reason without secrets.
- Successful execution records the candidate and marker movement.
- Failure uses the failed step/action outcome. Cleanup failure after marker
  movement is identified as `failed_cleanup_after_release`; no durable
  survivor/retry record or broader policy taxonomy is required.

## Validation

- Normal hook-selected RepoInfra gate, which collects the classifier units
  under the repository-owned `/usr/bin/python3` command exactly once; do not
  invoke that focused test or full suite directly or repeat it
- `actionlint .github/workflows/testflight.yml` with recorded tool version
- Repository structural checks
- Independent review of secret scope, step ordering, exact checkout, cleanup,
  and final path manifest
