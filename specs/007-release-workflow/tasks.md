---
description: "Single RepoInfra task for the minimal CI-gated TestFlight release"
---

# Tasks: Minimal CI-Gated TestFlight Release

**Execution model**: One Fullstack Engineer, one RepoInfra issue, one PR, and
one dispatchable task. Internal steps below are not separate issues or commits.

## Vertical slice and dependency graph

| Slice | User outcome | Upstream | Tasks | Acceptance |
|---|---|---|---|---|
| US1 | Release an eligible exact CI or manual head with minimal marker relevance and safe cleanup | None | T001 | AC-01–AC-08 |

```text
T001 implementation -> AI Reviewer prepublication review -> protected-path approval
                   -> MY-1692 merge gate -> PR Manager ship
```

## US1 — Release an eligible exact head

- [ ] T001 [US1] Replace the manual-only TestFlight trigger with the accepted
  one-job marker-plus-relevance workflow in `.github/workflows/testflight.yml`,
  `scripts/ci/tests/test_testflight_manual_only.py`,
  `scripts/ci/tests/test_testflight_relevance.py`, and
  `docs/testflight-handoff.md`.

  **T001 metadata**:

  | Field | Value |
  |---|---|
  | Owning layer / context | `RepoInfra` / `scripts/CONTEXT.md` |
  | Slice | US1 |
  | Blocking tasks | None |
  | Contract | External release-workflow behavior in `contracts/release-workflow.md`; no product API |
  | Acceptance | AC-01–AC-08 |
  | Governing constitution | §Testing → Who runs tests; §Development Workflow → Spec-Driven, Multica-Executed; §Cross-Cutting Quality Bars → A. Scope Discipline; §Development Workflow → No Identity in Version Control |
  | Verification | Normal hook-selected RepoInfra gate (collects classifier units once); distinct `actionlint .github/workflows/testflight.yml`; structural checks |

  **Final files in scope** (no more than these four paths):
  - `.github/workflows/testflight.yml`
  - `scripts/ci/tests/test_testflight_manual_only.py` (delete)
  - `scripts/ci/tests/test_testflight_relevance.py` (add focused production
    classifier/CLI and its unit tests)
  - `docs/testflight-handoff.md`

  **Candidate-removal requirement**:
  - The preserved unpublished `scripts/ci/tests/test_testflight_release.py`
    shadow suite from `e8c353ce` must not exist in the final tree or PR diff.
  - The PR body's Removed/weakened-tests section must state that the 542-line
    unaccepted workflow-policy shadow was discarded rather than ported, while
    the obsolete manual-only test was replaced by focused classifier units.
  - Do not publish a commit descending from `e8c353ce`; Team Lead supplies the
    recovered non-descendant implementation line.

  **Files NOT to touch**:
  - every other `.github/**` path, including `build.yml`;
  - `fastlane/**`, `project.yml`, `Configs/**`;
  - review machinery, `.specify/**`, `AGENTS.md`, contexts, and Spec 007;
  - app, package, CLI, and aidata sources.

  **Implementation requirements**:
  - Implement FR-001–FR-004: automatic successful same-repository `build` push
    on `main`, exact event SHA/full-history checkout, retained manual force,
    one self-hosted job, job-level `contents: write`, and one non-cancelling
    concurrency group.
  - Implement FR-005–FR-007: exact marker-to-head diff, root-anchored app-path
    classifier used by both workflow and unit tests, fail-closed marker errors,
    and one-line irrelevant summary before secrets.
  - Implement FR-008–FR-011: existing lane and infrastructure, all five secrets
    only on build/upload, marker only after lane success, no retry/fallback, and
    reversible keychain handling. Capture search-list/default/login-lock/
    auto-lock state before mutation; make the temporary keychain the temporary
    default/search-list head while retaining login; do not mutate partition
    ACLs; require the existing non-interactive signing ACL; and use secret-free
    `always()` cleanup to restore state and delete the temporary
    keychain/state/local tags. A
    pre-marker failure leaves the marker unchanged; cleanup failure after marker
    movement fails as `failed_cleanup_after_release` and leaves it advanced.
  - Update the handoff guide to describe automatic and manual operation,
    relevance, force bootstrap, secret scope, the preconfigured signing-ACL
    prerequisite, cleanup, failure behavior, and removed policy machinery
    without promising recovery or exactly-once state.

  **Acceptance**: AC-01 through AC-08.

  **Layer/context**: `RepoInfra`; `scripts/CONTEXT.md`.

  **Verification**:
  - stage only the declared paths and let the normal hook-selected RepoInfra
    gate collect `test_testflight_relevance.py` once; do not directly invoke or
    repeat the focused file or full suite
  - record `actionlint -version`; run
    `actionlint .github/workflows/testflight.yml`
  - context audit, task freshness, `git diff --check`, and exact
    four-path-or-fewer manifest
  - independent review of exact checkout, secret scope, upload/marker ordering,
    exact keychain capture/restore and no partition mutation, both ordered
    marker outcomes, and absence of superseded machinery
  - no Xcode test or real upload

  **Dependencies**: Team Lead recovery of the preserved unpublished candidate;
  protected-path Owner approval; unchanged MY-1692 merge gate.

## Completion and review budget

- This task is complete only on the exact reviewed candidate with all evidence.
- The normal two-round implementation review budget applies to the re-scoped
  candidate. A round-2 `NEEDS_WORK` is parked and reported to the Owner delegate
  by Team Lead, without a third round or Owner escalation.
- The pushed SHA, remote branch SHA, and PR head must match. Planning artifacts
  remain byte-identical during implementation.
