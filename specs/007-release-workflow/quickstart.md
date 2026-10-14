# Quickstart: Verify the Release-Workflow Change

## Scope check

The implementation candidate may change only:

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py  # deletion/rename
scripts/ci/tests/test_testflight_release.py      # replacement
docs/testflight-handoff.md
```

Planning files in this directory are reviewed inputs and remain byte-identical.

## Required local evidence

1. Activate the repository hooks in the issue-scoped delivery workspace.
2. Confirm every changed implementation path resolves to `RepoInfra` with the
   repository context resolver.
3. Stage the candidate and let the normal hook flow run the RepoInfra local
   gates. The declared gate is:

   ```text
   /usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q
   ```

4. Confirm `git diff --check` is clean and the diff contains only the declared
   paths.
5. Freeze the candidate and obtain independent AI Reviewer PASS before commit,
   push, or PR publication.

The pinned planning base currently fails this gate before reaching this
feature's assertions because its review launcher imports `tomllib` under the
machine's Python 3.9. That failure belongs to the separate review-machinery
repair and is not waived. Use the Team Lead-approved refreshed delivery base and
require a fully green fresh gate; otherwise return the exact blocker.

Do not run `xcodebuild`, host-based app tests, a real TestFlight upload, or a
second copy of hook-owned suites during implementation.

## Contract cases the replacement test must cover

- automatic event success/failure, main/non-main, exact SHA checkout;
- shared queued concurrency and no cancel-in-progress;
- missing, duplicate, ancestor, non-ancestor, and out-of-order markers;
- every app-relevant path family and representative excluded path family;
- manual force bypass of path relevance only;
- configured, legacy-marker, persisted-marker, labelled, unlabelled, direct
  push, ambiguous-PR, and API-failure version states;
- strict internal distribution, no new secrets, no retry/rollback/fallback;
- success, skip, and failure summary fields.

## Publication and shipping

The PR is protected-path work and requires Owner approval. It may be prepared
after planning readiness, but Team Lead/PR Manager must not ship it until the
separate review-machinery landing and fresh parked-PR proof satisfy the accepted
delivery sequence. Any refresh creates a new candidate requiring renewed exact-
head review and approval.

After merge, the next app-relevant `main` merge supplies production evidence:
record its release run URL and build number on the delivery issue. Do not create
a manual smoke-test issue.
