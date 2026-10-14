# Feature Specification: Minimal CI-Gated TestFlight Release

**Feature Branch**: `007-release-workflow`

**Created**: 2026-10-15

**Status**: Ready for independent planning review

**Input**: Delegated Owner decision `OD-2026-10-15-B`: discard the unpublished
complex candidate and implement a deliberately minimal marker-plus-relevance
release workflow.

## Authority and supersession

`OD-2026-10-15-B` supersedes every earlier Spec 007 requirement for a hosted
provenance job, a separate compare-and-swap permission boundary, strict marker
metadata, release-version inference, workflow-owned App Store Connect proof,
or a workflow-policy simulation suite. It preserves the existing Fastlane lane,
signing infrastructure, self-hosted Mac, manual dispatch, public moving marker,
protected-path approval, and MY-1692 merge dependency.

The discarded candidate `e8c353ce` is evidence only. It must stay preserved and
unpublished; no implementation PR may descend from it. Team Lead owns the
delivery-workspace recovery needed to start the revised implementation without
rewriting or publishing that candidate.

## Existing behavior

- `.github/workflows/testflight.yml` is manual-only. It checks out `main`, uses
  one `testflight` concurrency group with cancellation disabled, calls the
  existing `fastlane ios beta` lane on `[self-hosted, aidash-mac]`, and moves
  `testflight/last-released` after lane success.
- Manual dispatch exposes `force`; it may release even when the checked-out SHA
  equals the marker.
- The workflow exposes signing secrets across several steps and mutates keychain
  state without a run-scoped `always()` cleanup.
- `scripts/ci/tests/test_testflight_manual_only.py` rejects automatic triggers,
  and `docs/testflight-handoff.md` documents manual-only operation.
- The unpublished candidate replaced that small test with the Owner-described
  542-line
  workflow-policy shadow. It is not accepted implementation input.

## User scenarios and testing

### User Story 1 - Release an eligible exact head (Priority: P1)

As the Owner, I receive a TestFlight build for the exact successful `main` CI
head when the accumulated changes since the release marker include an app path,
while retaining the existing manual release escape.

**Independent Test**: Focused classifier unit tests prove included and excluded
paths; actionlint validates automatic and manual entrypoints; reviewer
inspection proves exact checkout, one concurrency group, upload-before-marker
ordering, secret scope, and cleanup.

**Acceptance Scenarios**:

1. **Given** the repository `build` workflow completed successfully for a
   same-repository `push` to `main`, **when** `marker..head_sha` includes an app
   path, **then** the one release job checks out exactly `head_sha` with full
   history, invokes the existing lane, and moves the marker only after success.
2. **Given** the same trigger and a valid marker, **when** the diff contains no
   app path, **then** the job performs no signing or upload and writes one clear
   skip line to `$GITHUB_STEP_SUMMARY`.
3. **Given** an unsuccessful, non-push, non-`main`, or different-repository
   source run, **when** the event is evaluated, **then** the release job does not
   run.
4. **Given** `workflow_dispatch` with `force=false`, **when** the marker is valid,
   **then** current `main` uses the same marker-range relevance decision.
5. **Given** `workflow_dispatch` with `force=true`, **when** the marker is
   missing, equal, or the range is irrelevant, **then** current `main` may build
   and upload; all upload, cleanup, and marker-ordering requirements remain.
6. **Given** any preflight, build, signing, or upload failure, **then** the run
   fails, does not move the remote marker, and schedules no retry.

## Functional requirements

- **FR-001 — Automatic trigger**: Register `workflow_run` for workflow `build`,
  type `completed`, branch `main`. The release job MUST run automatically only
  when conclusion is `success`, source event is `push`, head branch is `main`,
  and `head_repository.full_name == github.repository`. Keep
  `workflow_dispatch` with boolean `force`, default `false`.
- **FR-002 — Exact checkout**: Automatic execution MUST checkout exactly
  `github.event.workflow_run.head_sha`; manual execution MUST checkout current
  repository `main`. `actions/checkout` MUST use `fetch-depth: 0` and fetch tags.
  The automatic path MUST NOT substitute a newer `main` tip.
- **FR-003 — One release job**: Trigger validation, checkout, relevance, setup,
  build/upload, marker movement, summary, and cleanup MUST remain in one
  `[self-hosted, aidash-mac]` job. The job has plain job-level
  `permissions: contents: write`; there is no separate provenance, token, or
  compare-and-swap job.
- **FR-004 — Serialization**: Automatic and manual runs MUST share one
  concurrency group `testflight` with `cancel-in-progress: false`.
- **FR-005 — Marker relevance**: Without manual force, fetch and dereference
  `testflight/last-released`, then classify exactly the paths emitted by
  `git diff --name-only <marker>..<checked-out-head>`. Missing, invalid, or
  unusable marker/diff state MUST fail closed. No cursor, skip record, journal,
  recovery ref, or second durable state may be added.
- **FR-006 — App path filters**: Relevant paths are exactly
  `Apps/AIDashApp/**`, `Packages/AIDashCore/**`, `Packages/AIDashUI/**`,
  `Packages/DesignKit/**`, `Configs/**`, `project.yml`, and `fastlane/**`.
  Every other path is irrelevant. An irrelevant non-forced run MUST stop before
  secrets/signing/upload and append one concise skip line to the step summary.
- **FR-007 — Focused classifier**: The production relevance classifier MUST be
  a small executable/importable Python 3.9-compatible unit used directly by the
  workflow. Its unit tests MUST cover every included family, representative
  excluded paths, mixed input, empty input, and exact-root near misses. Tests
  MUST exercise this classifier, not reimplement workflow policy.
- **FR-008 — Existing lane and infrastructure**: Reuse `fastlane ios beta`, its
  existing global build-number allocation, signing/profile behavior, five
  existing secrets, and self-hosted runner. Do not edit Fastlane, project,
  signing configuration, app code, or secret inventory.
- **FR-009 — Secret scope**: All five signing/upload secrets MUST appear only on
  the single build/upload step. Secret validation, keychain preparation, and
  lane invocation happen inside that step. No preceding, marker, summary, or
  cleanup step may reference them.
- **FR-010 — Marker movement**: Move the plain public
  `testflight/last-released` tag to the checked-out head only after the existing
  lane exits successfully. Use the job's ordinary contents-write token; do not
  add a CAS-only permission boundary, annotated marker schema, or alternate
  release state.
- **FR-011 — Cleanup and failure**: A final `if: always()` step MUST restore the
  prior keychain search list and remove only run-scoped temporary keychain files
  and local temporary release tags. Failures leave the remote marker unchanged.
  No automatic retry, rollback, alternate runner, or fallback credential path
  is permitted.
- **FR-012 — Validation and scope**: Run focused classifier unit tests under
  `/usr/bin/python3`, actionlint as the workflow linter, repository planning
  checks, and the normal hook-selected RepoInfra gate. The final implementation
  diff MUST contain the same four paths or fewer.

## Compatibility

- The `workflow_dispatch(force)` entrypoint, `testflight` concurrency group,
  public marker name, existing Fastlane lane, global build-number behavior,
  runner labels, five secrets, signing/profile path, and internal distribution
  behavior remain compatible.
- Product behavior, project settings, Fastlane sources, CI build workflow,
  review machinery, rulesets, and required-check names are unchanged.
- Planning remains one `RepoInfra` task, one implementation issue, and one PR.

## Removed behavior

`OD-2026-10-15-B` authorizes removal of:

- manual-only triggering and its regression assertions;
- the unpublished 542-line shadow-policy suite in
  `scripts/ci/tests/test_testflight_release.py`; it is discarded, not ported,
  and its removal MUST be stated in the PR body;
- separate hosted provenance and CAS-only permission jobs;
- strict marker metadata, ancestry taxonomies, cursor/skip/journal/recovery
  state, PR-label marketing-version logic, workflow-owned ASC group/readback
  proof, and exactly-once/recovery claims;
- broad tests that mirror YAML policy rather than unit-testing relevance.

The old manual-only test is replaced by focused production-classifier unit
tests. No product or Fastlane test is removed or weakened.

## Explicit non-goals

- No scheduled release, queue, cursor, journal, recovery mode, retry, rollback,
  second marker, separate permission boundary, or general workflow simulator.
- No edit to `.github/workflows/build.yml`, `fastlane/**`, `project.yml`,
  `Configs/**`, app/package/CLI/aidata sources, review machinery, planning
  infrastructure, rulesets, runners, credentials, or secrets.
- No real TestFlight upload, Xcode test, or manual smoke-test issue during
  implementation verification.

## Stable acceptance criteria

- **AC-01**: Automatic trigger guards and exact `head_sha` checkout with full
  history satisfy FR-001–FR-002; manual dispatch still targets `main`.
- **AC-02**: One self-hosted job, one concurrency group, and plain job-level
  contents-write permission satisfy FR-003–FR-004.
- **AC-03**: The actual production classifier and its focused unit tests satisfy
  FR-005–FR-007, including a one-line irrelevant summary and fail-closed marker
  errors.
- **AC-04**: Existing lane/runner/build-number/signing behavior is preserved;
  all five secrets occur only on the build/upload step.
- **AC-05**: The marker moves only after successful upload; every earlier
  failure leaves it untouched and no retry/fallback path exists.
- **AC-06**: The `always()` cleanup restores keychain state and removes only
  run-scoped temporary keychain/local-tag artifacts on success, skip, or
  failure.
- **AC-07**: `/usr/bin/python3` classifier tests, actionlint workflow lint,
  repository hooks/RepoInfra gate, context audit, task freshness, and exact-path
  checks provide fresh evidence.
- **AC-08**: The final PR changes no more than the four declared paths, records
  the discarded shadow suite in its Removed/weakened-tests section, receives
  protected-path Owner approval, and remains blocked from merge by MY-1692
  until that unchanged gate is satisfied.

## Success criteria

- **SC-001**: A relevant successful `main` CI head is the exact commit uploaded
  and then recorded by the marker.
- **SC-002**: An irrelevant non-forced range performs no signing/upload and
  leaves a concise summary line.
- **SC-003**: A failed run moves no remote marker and starts no retry.
- **SC-004**: The implementation is materially smaller than the discarded
  candidate and contains no workflow-policy shadow suite.
