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

1. Activate repository hooks in the issue-scoped delivery workspace.
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

The pinned planning base currently fails the RepoInfra gate before reaching
this feature's assertions because its review launcher imports `tomllib` under
the machine's Python 3.9. That failure belongs to MY-1692 and is not waived. Use
the Team Lead-approved refreshed delivery base and require a fully green fresh
gate; otherwise return the exact blocker.

Do not run `xcodebuild`, host-based app tests, a real TestFlight upload, or a
second copy of hook-owned suites during implementation.

## Contract cases the replacement test must cover

- Same-repository `build.yml` push success is trusted; pull-request-origin,
  fork repository with head branch named `main`, wrong workflow/path, non-main,
  non-success, invalid SHA, and candidate not reachable from freshly fetched
  protected `main` are rejected before checkout/self-hosted/secrets.
- Automatic candidate is exact `workflow_run.head_sha`; manual candidate is
  once-pinned current protected `main`. Manual force bypasses relevance only.
- Automatic and manual release work share one AIDash concurrency group with
  `cancel-in-progress: false`. The workflow creates no queue-start, queue,
  cursor, skip, attempt, confirmation, quarantine, or recovery state.
- Existing-marker relevance uses `marker..candidate`. Several irrelevant
  automatic merges each skip and leave the marker fixed; the later range still
  contains them and a later app-relevant descendant releases its exact head.
- An irrelevant automatic run followed by manual `force=true` releases pinned
  current main. Same-candidate automatic/manual runs serialize: an automatic
  skip permits later force, while the first success makes the other equality-
  skip.
- With an existing ancestor marker, a failed eligible release leaves the marker
  unchanged and a later descendant's range includes the failed relevant change.
  With no marker, a later docs-only descendant still skips; pickup requires an
  independently app-relevant candidate or manual force on pinned current main.
  No automatic retry or rollback is created.
- Missing marker plus workflow-only enabling merge skips. The first later
  app-relevant candidate bootstraps from its first-parent delta. Root candidate
  bootstrap uses the empty tree.
- Existing marker equal to candidate is an absolute no-upload skip; ancestor is
  the normal accumulated range; descendant means stale/no-rewind skip;
  unrelated history fails closed.
- Every included app path and representative docs/specs/CI/review/CLI/aidata-
  only exclusions are covered.
- Only a genuine lightweight public marker receives legacy fallback. A valid
  annotated marker succeeds; annotated absent/empty, malformed, duplicate,
  unknown, or non-commit marker state fails before release side effects.
- Configured, missing/lightweight/persisted marker, labelled/unlabelled exact
  merged PR, direct-push, ambiguous-PR, and API-failure version states; existing
  global build allocator and exactly one parsed selected build number.
- Group normalization rejects empty/duplicate names; absent group fails before
  Fastlane; group deleted or selected build missing any intended membership
  fails after the lane and leaves the marker unchanged; all memberships permit
  marker compare-and-swap.
- Existing five secrets/signing path and exact self-hosted runner labels; no
  release-secret exposure before provenance/eligibility, new secret, alternate
  release runner, upload retry, rollback, or fallback.
- Marker compare-and-swap succeeds only against the fetched prior object (or
  confirmed absence). Every preflight/release/postflight/CAS failure leaves the
  marker unchanged.
- Upload success followed by proof/marker failure has no journal or recovery;
  a later run may upload again. Tests and docs assert same-recorded-SHA
  protection and do not claim exactly-once for unrecorded external outcomes.
- Each executed run summarizes its own success, skip, or failure fields. No
  surviving run synthesizes a summary for a platform-replaced pending run.

## Publication and shipping

The PR is protected-path work and requires Owner approval. It may be prepared
after planning readiness, but Team Lead/PR Manager must not ship it until the
MY-1692 repair landing and fresh parked-PR proof satisfy the accepted delivery
sequence. Any refresh creates a new candidate requiring renewed exact-head
review and approval.

After merge, the next eligible app-relevant accumulated range supplies
production evidence: record its release run URL and build number on the
delivery issue. Do not create a manual smoke-test issue.
