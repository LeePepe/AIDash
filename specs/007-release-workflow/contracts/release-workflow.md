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
- That step validates secret presence, prepares the run-scoped keychain state,
  unlocks the signing identity as needed, and invokes the lane.
- No earlier/later step references those secrets. Fastlane, global build-number
  allocation, signing/profile lookup, and internal distribution remain unchanged.

## Marker movement

- Only a successful build/upload step enables marker movement.
- Move the plain `testflight/last-released` tag to the checked-out candidate and
  push it with the job's normal contents-write token.
- Do not add an annotated metadata schema, CAS-only token/job, lease protocol,
  or alternate release record.
- Any failure before marker movement leaves the remote marker unchanged. There
  is no retry, rollback, alternate runner, or fallback credential path.

## Cleanup

A final step with `if: always()`:

- restores the prior user keychain search list;
- removes the run-scoped temporary keychain file, if created;
- deletes only local temporary release tags created by the run;
- does not reference signing secrets or modify/delete the remote marker.

## Summary

- Irrelevant non-forced execution writes one clear skip line naming the range
  and reason without secrets.
- Successful execution records the candidate and marker movement.
- Failure uses the failed step/action outcome; no synthetic policy taxonomy or
  survivor/retry record is required.

## Validation

- `/usr/bin/python3 -m pytest scripts/ci/tests/test_testflight_relevance.py -q`
- `actionlint .github/workflows/testflight.yml` with recorded tool version
- Normal hook-selected RepoInfra gate and repository structural checks
- Independent review of secret scope, step ordering, exact checkout, cleanup,
  and final path manifest
