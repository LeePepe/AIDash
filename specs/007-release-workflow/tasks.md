# Tasks: Minimal Post-Merge TestFlight Release

**Input**: Owner decision B on MY-1777, Owner decision `cd-on-merge`, and the
reviewed Spec 007 revision-5 package.

**Shape**: One goal, one RepoInfra implementation task, one issue, one PR.
The phases below are ordered work within T001, not separate Multica tasks.

## Vertical slice and dependency graph

| Slice | Outcome | Dependency |
|---|---|---|
| US1 | An app-relevant post-merge `main` push SHA uses the existing TestFlight lane and records success | none |
| US2 | Manual force remains available; pre-success failures leave the marker unchanged and post-success cleanup can only warn | US1 |

```text
T001 (US1 + US2, RepoInfra)
```

## Sole implementation task

- [ ] T001 [US1] [US2] Implement and verify the minimal marker-plus-relevance
  TestFlight release in `.github/workflows/testflight.yml`, delete/rename
  `scripts/ci/tests/test_testflight_manual_only.py`, add the concise
  `scripts/ci/tests/test_testflight_release.py`, and update
  `docs/testflight-handoff.md`.

### T001 metadata

| Field | Contract |
|---|---|
| Layer | `RepoInfra`; `scripts/CONTEXT.md` |
| In scope | The four paths named in T001, or fewer |
| Out of scope | build/review workflows, Fastlane, project/signing config, app/package/CLI/aidata code, routing/constitution/planning artifacts, host config, secrets/rulesets |
| Interface | Automatic and manual GitHub Actions release entrypoints plus the public `testflight/last-released` tag |
| Dependencies | Exact planning PASS before work resumes; refreshed MY-1692 proof and Owner `.github/**` approval before merge |
| Constitution | `.specify/memory/constitution.md` §Technical Constraints → Testing → Who runs tests (NON-NEGOTIABLE), §Cross-Cutting Quality Bars → A. Scope Discipline (P0), and §Development Workflow → Quality Gates |
| Verification | Python 3.9 harness executing the exact production classifier block; complete-workflow `actionlint`; resolver RepoInfra gates; context audit; hook/CI gates; exact manifest; `git diff --check` |

### Ordered phase A — entrypoint and exact candidate

- Register `push` scoped to `main` and preserve `workflow_dispatch.force`.
- Use one non-cancelling concurrency group, one AIDash self-hosted job, and
  ordinary job-level `contents: write`.
- Pin automatic work to exact `github.sha`; pin manual work to official `main`
  once. Check out exactly the selected candidate with full history and
  `persist-credentials: false`; validate official-main reachability before the
  release path and expose the job token only for marker movement.

### Ordered phase B — marker and relevance

- Fetch the public marker; equality skips, ancestor accumulates, automatic and
  non-force missing-marker execution fails, manual force may bootstrap, and unsafe
  relationships fail.
- Classify the exact AIDash allowlist. Force otherwise bypasses only classifier
  output.
- Leave the marker unchanged on every skip or failure before successful marker
  compare-and-swap.

### Ordered phase C — unchanged release lane and cleanup

- Preserve runner labels, existing secrets, login-keychain identity, runtime
  profile, global build number, tracked marketing version, and
  `fastlane ios beta` behavior.
- After lane success, use a lease-guarded compare-and-swap against the exact
  remote marker object ID observed during eligibility (or authorized expected
  absence). A rejected update means this run did not mutate the marker and
  fails after upload; a successful update is the successful release outcome.
- Use only `security unlock-keychain` on `login.keychain-db`; do not run
  `security set-keychain-settings`, mutate the user search list, or run
  `security set-key-partition-list`. Rely on the runner's preconfigured
  certificate ACL; an insufficient ACL fails before marker update. If unlock
  was attempted, `always()` unconditionally runs `security lock-keychain` and
  cleans workflow-created refs/signing artifacts.
- Catch all cleanup failures after marker success, emit only secret-free
  warnings, and preserve the successful outcome; before marker success, cleanup
  failures cannot mask the earlier failure.

### Ordered phase D — narrow replacement evidence

- Delete the manual-only regression and do not reuse/port the unpublished
  shadow-policy suite.
- Add Python 3.9 table-driven cases that extract and execute the exact
  production classifier block for every allowlisted family and representative
  excluded paths in isolated temporary Git repositories with temporary outputs;
  missing/ambiguous extraction fails, and the allowlist is not duplicated in
  Python.
- Add stable structural assertions for `push.branches: [main]`, exact automatic
  `github.sha`, manual dispatch, and the retained safety contract without
  reimplementing policy state machines; provision a pinned verification-only
  `actionlint` outside tracked paths, record its version, and run
  `actionlint .github/workflows/testflight.yml` without a host-wide install,
  then preserve every mandatory repository gate.
- Update the handoff guide and PR body to disclose removed coverage, job-level
  write permission, upload/tag non-atomicity, no retry/recovery, and the
  repository-specific signing flow.

## Task-local acceptance

T001 owns AC-01 through AC-10. Team Lead/PR Manager own AC-11 and AC-12.
Any changed planning or prohibited path, new durable state/secret/dependency,
or attempt to publish the revision-3 candidate fails scope.

## Final delivery gates

1. Freeze the new local candidate and obtain exact-tree AI Reviewer pre-push
   PASS under the new normal two-round budget.
2. Push only the reviewed SHA and create/update a non-Draft PR.
3. Do not merge until MY-1692 refreshed eligible proof, required checks, and
   Owner protected-path approval are present.
4. Record the first eligible post-merge `main` push run URL and build number.
