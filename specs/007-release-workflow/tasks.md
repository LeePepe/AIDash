# Tasks: Minimal CI-Gated TestFlight Release

**Input**: Owner decision B on MY-1777 and the reviewed Spec 007 package.

**Shape**: One goal, one RepoInfra implementation task, one issue, one PR.
The phases below are ordered work within T001, not separate Multica tasks.

## Vertical slice and dependency graph

| Slice | Outcome | Dependency |
|---|---|---|
| US1 | A trusted app-relevant CI head uses the existing TestFlight lane and records success | none |
| US2 | Manual force remains available and failures leave the marker unchanged with cleanup | US1 |

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
| Verification | Python 3.9 focused tests and repository-local workflow lint; resolver RepoInfra gates; context audit; hook/CI gates; exact manifest; `git diff --check` |

### Ordered phase A — entrypoint and exact candidate

- Register trusted `workflow_run` and preserve `workflow_dispatch.force`.
- Use one non-cancelling concurrency group, one AIDash self-hosted job, and
  ordinary job-level `contents: write`.
- Pin and check out exactly the selected candidate with full history and
  `persist-credentials: false`; validate official-main reachability before the
  release path and expose the job token only for marker movement.

### Ordered phase B — marker and relevance

- Fetch the public marker; equality skips, ancestor accumulates, automatic and
  non-force missing-marker execution fails, manual force may bootstrap, and unsafe
  relationships fail.
- Classify the exact AIDash allowlist. Force otherwise bypasses only classifier
  output.
- Leave the marker unchanged on every skip or failure.

### Ordered phase C — unchanged release lane and cleanup

- Preserve runner labels, existing secrets, login-keychain flow, runtime
  profile, global build number, tracked marketing version, and
  `fastlane ios beta` behavior.
- Move the lightweight marker only after lane success.
- Run summary and workflow-created ref/signing/keychain cleanup with
  `always()`.

### Ordered phase D — narrow replacement evidence

- Delete the manual-only regression and do not reuse/port the unpublished
  shadow-policy suite.
- Add Python 3.9 classifier unit cases for every allowlisted family and
  representative excluded paths.
- Add stable structural assertions without reimplementing policy state
  machines; run repository-local workflow lint and repository gates.
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
4. Record the first eligible post-merge run URL and build number.
