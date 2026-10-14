# Quickstart: Implement the Minimal Release Pattern

## Scope check

Use the exact reviewed planning revision and registered MY-1777 workspace.
The unpublished revision-3 candidate is preserved evidence, not a base to push
or incrementally repair. Confirm the implementation diff is limited to:

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py
scripts/ci/tests/test_testflight_release.py
docs/testflight-handoff.md
```

## Implementation order

1. Replace the manual-only trigger with trusted `workflow_run` plus existing
   `workflow_dispatch`.
2. Select and check out the exact candidate with full history.
3. Add marker ancestry/missing/equality handling and the AIDash relevance
   classifier; keep force as relevance-only. Automatic and non-force missing-
   marker execution fails closed; manual force may bootstrap.
4. Preserve the existing runner, lane, secrets, global build number, login
   keychain, runtime profile, and internal distribution behavior.
5. Move the lightweight marker only after lane success.
6. Add `always()` cleanup and a concise secret-free summary.
7. Delete the manual-only test and add only focused classifier/structure tests.
8. Update the handoff guide for automatic operation, failure behavior, and the
   explicit upload/tag non-atomicity.

## Required evidence

- Every owned path resolves to `RepoInfra`; `scripts/context/audit` is clean.
- Repository hook-selected RepoInfra checks pass on the approved delivery base.
- Replacement tests run with `/usr/bin/python3` Python 3.9.
- Repository-local workflow lint passes without a new tool dependency.
- `git diff --check` is clean and the manifest contains four paths or fewer.
- Planning artifacts and prohibited paths match the reviewed revision.

Do not run app tests, `xcodebuild`, or a real upload during implementation.

## Publication and shipping

Freeze the replacement candidate and obtain AI Reviewer pre-push PASS on that
exact tree. Any remaining blocker after implementation review round 2 parks the
delivery without another review round or Owner escalation. Team Lead controls
publication, refreshed MY-1692 merge proof, and Owner approval for `.github/**`.

After merge, record the next eligible workflow URL and its build number on the
delivery issue.
