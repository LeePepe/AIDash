# Quickstart: Implement the Minimal Post-Merge Release Pattern

## Scope check

Use the exact reviewed planning revision and registered MY-1767 workspace.
The unpublished revision-3 candidate is preserved evidence, not a base to push
or incrementally repair. Confirm the implementation diff is limited to:

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py
scripts/ci/tests/test_testflight_release.py
docs/testflight-handoff.md
```

## Implementation order

1. Replace the manual-only trigger with `push` scoped to `main` plus existing
   `workflow_dispatch`.
2. For push, select exact `github.sha`; for manual dispatch, pin official
   `main` once. Check out only that candidate with full history.
3. Add marker ancestry/missing/equality handling and the AIDash relevance
   classifier; keep force as relevance-only. Automatic and non-force missing-
   marker execution fails closed; manual force may bootstrap.
4. Preserve the existing runner, lane, secrets, global build number, login
   keychain identity, runtime profile, and internal distribution behavior. Use
   only `security unlock-keychain` on `login.keychain-db`: no
   `security set-keychain-settings`, search-list mutation, or
   `security set-key-partition-list`. Rely on the preconfigured certificate ACL.
5. After lane success, use a lease-guarded compare-and-swap from the exact
   remote marker object ID observed during eligibility (or expected absence for
   authorized bootstrap) to the candidate; marker success is release success.
6. If unlock was attempted, make `always()` cleanup unconditionally run
   `security lock-keychain`, plus local-artifact cleanup and a concise
   secret-free summary. Catch post-success cleanup errors as warnings and never
   let cleanup mask an earlier failure.
7. Delete the manual-only test. Make table-driven cases extract and execute the
   exact production classifier block; keep structural assertions narrow.
8. Update the handoff guide for automatic operation, failure behavior, and the
   explicit upload/tag non-atomicity.

## Required evidence

- Every owned path resolves to `RepoInfra`; `scripts/context/audit` is clean.
- Repository hook-selected RepoInfra checks pass on the approved delivery base.
- Replacement tests run with `/usr/bin/python3` Python 3.9 and execute the exact
  production classifier block.
- Pinned verification-only `actionlint`, provisioned outside tracked paths with
  its version recorded, runs as
  `actionlint .github/workflows/testflight.yml` without a tracked dependency or
  host-wide install; mandatory repository gates also pass.
- `git diff --check` is clean and the manifest contains four paths or fewer.
- Planning artifacts and prohibited paths match the reviewed revision.

Do not run app tests, `xcodebuild`, or a real upload during implementation.

## Publication and shipping

Freeze the replacement candidate and obtain AI Reviewer pre-push PASS on that
exact tree. Any remaining blocker after implementation review round 2 parks the
delivery without another review round or Owner escalation. Team Lead controls
publication, refreshed MY-1692 merge proof, and Owner approval for `.github/**`.

After merge, record the next eligible `main` push workflow URL and its build
number on the delivery issue.
