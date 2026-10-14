---
description: "Layer-scoped tasks for CI-gated TestFlight release"
---

# Tasks: CI-Gated TestFlight Release

**Input**: `spec.md`, `plan.md`, `research.md`, `data-model.md`,
`contracts/release-workflow.md`, and `quickstart.md`

**Execution model**: One Fullstack Engineer, one goal, one PR, one owning layer.
The three vertical slices are serialized because they intentionally modify the
same workflow, replacement test, and operating guide.

## Vertical slices and dependency graph

| Slice | User outcome | Upstream | Tasks | Acceptance |
|---|---|---|---|---|
| US1 | An eligible exact-CI-head merge releases automatically | None | T001 | AC-01, AC-02, AC-03, AC-07, AC-08 |
| US2 | Manual force remains available without bypassing safety | US1 | T002 | AC-02, AC-04 |
| US3 | Minor-version intent persists without regression | US2 | T003 | AC-05, AC-06, AC-09, AC-10 |

External gates AC-11 and AC-12 are not implementation tasks: Team Lead/PR
Manager own protected-path approval, delivery sequencing, and post-merge
production evidence.

```text
T001 [US1] ──> T002 [US2] ──> T003 [US3]
```

## Phase 1 — Automatic exact-head release

- [ ] **T001 [US1]** Replace the manual-only policy with exact-head, app-relevant,
  serialized automatic release behavior in `.github/workflows/testflight.yml`,
  replace `scripts/ci/tests/test_testflight_manual_only.py` with
  `scripts/ci/tests/test_testflight_release.py`, and update
  `docs/testflight-handoff.md` for the automatic operating model.

  **Files in scope** (PR may modify only these paths across this task):
  - `.github/workflows/testflight.yml`
  - `scripts/ci/tests/test_testflight_manual_only.py` (delete/rename)
  - `scripts/ci/tests/test_testflight_release.py` (replacement)
  - `docs/testflight-handoff.md`

  **Files NOT to touch** (touching is a scope failure):
  - `.github/workflows/build.yml` and every other `.github/**` path
  - `fastlane/**`, `project.yml`, and `Configs/**`
  - `scripts/ci/review-raven.py`, `scripts/ci/codex-review.sh`,
    `scripts/ci/tests/review_raven_contract.py`,
    `scripts/ci/tests/test_review_shell.py`, and
    `scripts/ci/raven-review-operations.md`
  - `.specify/memory/constitution.md`, `AGENTS.md`, `CONTEXT.md`,
    `scripts/CONTEXT.md`, and `specs/007-release-workflow/**`
  - Paths under Apps/, Packages/, CLI/, and aidata/

  **Functional acceptance**:
  - Implement FR-001–FR-006 and FR-011–FR-013: bind to completed successful
    `build` runs on `main`, checkout the exact verified SHA, preserve queued
    concurrency, enforce marker equality/ancestry, bootstrap safely, and apply
    the exact app-path allowlist.
  - Set strict internal-group distribution and retain only the existing runner,
    secrets, signing path, and Fastlane lane.
  - Every skip/failure stops before release side effects and writes its reason;
    no schedule, fallback, automatic retry, rollback, or extra credential path
    exists.
  - Replace manual-only assertions with representative automatic-trigger,
    exact-head, marker, path, strict-failure, and summary contract tests.

  **Quality bars**: Constitution cross-cutting quality bars apply automatically.

  **Layer / context**: `RepoInfra`; `scripts/CONTEXT.md`.

  **Contract impact**: Establishes `contracts/release-workflow.md` automatic
  entrypoint, pre-upload invariants, path allowlist, and outcome summary.

  **Verification**: Activate repository hooks; stage only the declared paths and
  let the resolver run the RepoInfra gate (`/usr/bin/python3 -m pytest
  scripts/ci/tests scripts/context/tests -q`); confirm `git diff --check` and
  resolver ownership. Do not run Xcode or a real upload.

  **Dependencies**: None.

## Phase 2 — Safe manual compatibility

- [ ] **T002 [US2]** Preserve `workflow_dispatch(force)` in
  `.github/workflows/testflight.yml` and extend
  `scripts/ci/tests/test_testflight_release.py` plus
  `docs/testflight-handoff.md` so force bypasses path relevance only.

  **Files in scope**:
  - `.github/workflows/testflight.yml`
  - `scripts/ci/tests/test_testflight_release.py`
  - `docs/testflight-handoff.md`

  **Files NOT to touch**:
  - Every prohibition listed by T001, including the deleted legacy test path
  - Any new workflow, script, secret, marker name, or implementation path

  **Functional acceptance**:
  - Implement FR-007 while preserving T001 behavior.
  - `force=false` uses the normal path gate; `force=true` may release a new safe
    head with no app-relevant diff or bootstrap a missing marker.
  - Neither force value can bypass immutable candidate selection, same-SHA
    idempotency, ancestry, version/label validation, secret/signing checks,
    strict upload, or marker persistence.
  - Tests cover missing/existing marker, force false/true, same SHA,
    non-ancestor, and immutable manual candidate selection.

  **Quality bars**: Constitution cross-cutting quality bars apply automatically.

  **Layer / context**: `RepoInfra`; `scripts/CONTEXT.md`.

  **Contract impact**: Completes the manual entrypoint and absolute-invariant
  portions of `contracts/release-workflow.md`.

  **Verification**: Same resolver/hook-driven RepoInfra evidence as T001; no
  Xcode, host-based tests, or real release.

  **Dependencies**: T001 (hard; same files and shared eligibility state).

## Phase 3 — Durable version intent and final integration

- [ ] **T003 [US3]** Add exact-PR `release:minor` resolution, effective-version
  derivation, ephemeral checkout override, annotated success marker, and final
  build/run summary to `.github/workflows/testflight.yml`; complete coverage in
  `scripts/ci/tests/test_testflight_release.py` and operations in
  `docs/testflight-handoff.md`.

  **Files in scope**:
  - `.github/workflows/testflight.yml`
  - `scripts/ci/tests/test_testflight_release.py`
  - `docs/testflight-handoff.md`

  **Files NOT to touch**:
  - Every prohibition listed by T001 and T002
  - `fastlane/Fastfile` and tracked `project.yml`; the version override exists
    only in the isolated workflow checkout
  - Reviewed planning artifacts in `specs/007-release-workflow/**`

  **Functional acceptance**:
  - Preserve Fastlane's existing App Store Connect global maximum-plus-one build
    allocator and expose the selected build number in the success summary.
  - Implement FR-009–FR-010 for project, legacy-marker, annotated-marker,
    labelled/unlabelled exact PR, direct-push, ambiguous-association, API-failure,
    and post-bump non-regression states.
  - Move the annotated marker only after strict build/upload/distribution
    success; fail if success metadata or marker persistence is invalid.
  - Complete replacement tests for AC-01–AC-09 and confirm the final
    implementation diff satisfies AC-10 exactly.

  **Quality bars**: Constitution cross-cutting quality bars apply automatically.

  **Layer / context**: `RepoInfra`; `scripts/CONTEXT.md`.

  **Contract impact**: Completes marker metadata, version state, success summary,
  and failure semantics in `contracts/release-workflow.md`.

  **Verification**: Activate hooks and collect one fresh resolver-selected
  RepoInfra result for the final candidate; `git diff --check`; exact four-path
  add/delete/modify manifest; no Xcode or real upload. Freeze the candidate and
  obtain independent AI Reviewer PASS before publication.

  **Dependencies**: T002 (hard; same files and final integrated state).

## Final delivery gates

- The exact reviewed planning revision remains unchanged.
- The planning base's known Python 3.9/`tomllib` RepoInfra failure is not an
  accepted baseline. The refreshed delivery candidate must obtain a fully green
  resolver-selected RepoInfra gate or return blocked evidence to Team Lead.
- Fullstack's frozen candidate receives AI Reviewer prepublication PASS before
  commit/push/PR.
- The pushed SHA, remote branch SHA, and PR `headRefOid` match exactly.
- Owner approval is required for the protected workflow path.
- Merge/ship waits for the separately governed review-machinery landing and
  fresh parked-PR terminal proof. A later base refresh invalidates prior
  exact-head review/check evidence.
- After merge, Team Lead/PR Manager records the next eligible release run URL
  and build number on the delivery issue; no manual smoke-test issue is created.

## Traceability validation

- Every AC maps to an implementation task or an explicit external delivery gate.
- Every implementation task owns exactly one layer and declares exact paths,
  contract impact, acceptance, verification, and dependencies.
- The graph is acyclic; no task is incorrectly marked parallel.
- No task requires Fullstack to invent product behavior or broaden scope.
