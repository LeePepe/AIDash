# Quickstart: Verify the Release-Workflow Change

## Scope check

The implementation candidate may change only:

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py  # deletion/rename
scripts/ci/tests/test_testflight_release.py      # replacement
docs/testflight-handoff.md
```

The exact reviewed package remains byte-identical during implementation:
`.specify/feature.json`, the Spec Kit marker block in `AGENTS.md`, and every
file under `specs/007-release-workflow/`.

## Required local evidence

1. Activate the repository hooks in the issue-scoped delivery workspace.
2. Confirm every changed implementation path resolves to `RepoInfra` with the
   repository context resolver.
3. Stage the candidate and let the normal hook flow run the RepoInfra local
   gates. The declared gate is:

   ```text
   /usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q
   ```

   The replacement test must be compatible with this interpreter (Python 3.9
   on the planning base): no Python 3.10+ syntax or Python 3.11-only standard-
   library module unless the approved refreshed base first changes the gate.

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

- Same-repository `build.yml` push success is admitted; pull-request-origin,
  fork repository with head branch named `main`, wrong workflow/path,
  non-main, non-success, invalid SHA, and candidate not reachable from freshly
  fetched protected `main` are rejected before checkout/self-hosted/secrets.
- Automatic and manual candidates are pinned; manual force bypasses path
  relevance only.
- The workflow has one `release-contract-schema: 1` sentinel. Queue-start is
  derived from its unique protected-main first-parent introducing commit and
  excludes source-run identity; missing/multiple/mismatched activation or an
  activation later than the candidate fails closed. Simultaneous creators
  converge after refetch even when their annotated tag object IDs differ.
- Queue-start/queue metadata is strict; exact semantic replay is idempotent;
  collision, malformed/lightweight/mismatched/unknown queue state fails closed.
- A/B/C admissions with B's pending drain replaced still drain all proven
  heads. Out-of-order follower intake triggers exhaustive Actions API
  reconciliation, missing-entry materialization, SHA de-duplication, and
  first-parent order; simultaneous first admissions and newer-before-older
  intake with no public marker retain both heads; incomplete pagination/range
  proof fails closed.
- Missing, duplicate, ancestor, non-ancestor, root, same-SHA, and out-of-order
  public-marker histories; every app path and representative docs/specs/CI/
  review/CLI/aidata-only exclusion.
- Only a genuine lightweight public marker falls back. A valid annotated
  marker succeeds; annotated missing/empty, malformed, duplicate, unknown, or
  target-mismatched metadata fails before attempt.
- Attempt creation is create-only and precedes exactly one lane invocation.
  Attempted-only state blocks same-SHA force and descendants; ambiguous push
  response refetches state and never repeats the lane.
- Confirmation is create-only after exact build/all-group proof. Confirmation
  with marker behind performs marker-only CAS reconciliation; equal/ahead never
  rewinds; neither branch invokes Fastlane.
- Explicit attempted-only recovery requires exact SHA/build inputs plus ASC
  version/build/all-group proof and can only create confirmation/reconcile the
  marker. It uses only required ASC readback credentials, creates no new
  attempt, and cannot checkout, invoke Fastlane, build, sign, distribute, or
  upload. Missing proof leaves quarantine.
- Group normalization rejects empty/duplicate names; absent group fails before
  attempt; group deleted or selected build missing any intended membership
  fails after attempt without confirmation; all memberships allow confirmation.
- Configured, lightweight-marker, persisted-marker, labelled, unlabelled,
  direct-push, ambiguous-PR, and API-failure version states; existing global
  build allocator and exactly one parsed selected build number.
- Existing five secrets/signing path and exact self-hosted build runner labels;
  no release-secret exposure before provenance, new secret, alternate release
  runner, upload retry, rollback, or fallback.
- Per-candidate success, skip, failure, quarantine, and reconciliation summary
  fields, including the eventual survivor's evidence after pending replacement.

## Publication and shipping

The PR is protected-path work and requires Owner approval. It may be prepared
after planning readiness, but Team Lead/PR Manager must not ship it until the
separate review-machinery landing and fresh parked-PR proof satisfy the accepted
delivery sequence. Any refresh creates a new candidate requiring renewed exact-
head review and approval.

After merge, the next app-relevant `main` merge supplies production evidence:
record its release run URL and build number on the delivery issue. Do not create
a manual smoke-test issue.
