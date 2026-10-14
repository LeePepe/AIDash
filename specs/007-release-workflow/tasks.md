---
description: "Single RepoInfra implementation task for CI-gated TestFlight release"
---

# Tasks: CI-Gated TestFlight Release

**Input**: `spec.md`, `plan.md`, `research.md`, `data-model.md`,
`contracts/release-workflow.md`, and `quickstart.md`

**Execution model**: One Fullstack Engineer, one goal, one Multica
implementation issue, and one PR in the `RepoInfra` layer. `T001` is the sole
dispatchable task. US1–US3 below are ordered internal phases of that task, not
separate tasks, issues, commits, or PRs.

## Vertical slices and dependency graph

| Internal phase | User outcome | Upstream | Dispatchable task | Acceptance |
|---|---|---|---|---|
| US1 | Trusted exact candidates serialize and accumulated relevance is safe | None | T001 | AC-01, AC-02, AC-03, AC-08 |
| US2 | Manual force and failure pickup preserve marker safety | US1 | T001 | AC-04, AC-07, AC-08 |
| US3 | Build/version/distribution intent persists without regression | US2 | T001 | AC-05, AC-06, AC-09, AC-10 |

External gates AC-11 and AC-12 are not implementation tasks. Team Lead and PR
Manager retain protected-path approval, MY-1692 sequencing, and post-merge
production evidence.

```text
T001: US1 trusted provenance/marker accumulation
   -> US2 manual/failure/distribution safety
   -> US3 version/final integration
```

## Sole implementation task

- [ ] **T001** Replace the manual-only TestFlight policy with a trusted,
  serialized exact-head release state machine using only the existing public
  marker; preserve safe manual control and version intent; replace the obsolete
  contract test; and update operations.

  **Files in scope** (the implementation PR may modify only these paths):
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
  - `.specify/memory/constitution.md`, `.specify/feature.json`, `AGENTS.md`,
    `CONTEXT.md`, `scripts/CONTEXT.md`, and
    `specs/007-release-workflow/**`
  - Paths under Apps/, Packages/, CLI/, and aidata/

  **Allowed release state**:
  - Preserve `testflight/last-released` as the sole durable release-progress
    marker.
  - Do not add queue-start, queue/cursor/skip, attempted, confirmed,
    quarantine, recovery, or any other ref namespace, database, artifact,
    recovery input, credential path, or durable state.
  - Update the marker only through the strict metadata and compare-and-swap
    rules in `contracts/release-workflow.md`; never blind-force it.

  **Ordered internal phase US1 — trusted provenance and marker accumulation**:
  - Implement FR-001–FR-006: require exact `build.yml`/`build`, `push`,
    same-repository, successful `main` provenance and protected-main
    reachability in a hosted read-only stage before candidate checkout,
    self-hosted capacity, write authority, or release secrets.
  - Pin the automatic `workflow_run.head_sha`; pin current official protected
    `main` once for manual runs. Never substitute a moving tip later.
  - Serialize trusted automatic and manual release workers in the one AIDash
    group `testflight` with `cancel-in-progress: false`; refetch/revalidate the
    candidate and marker under the lock before release side effects.
  - Enforce marker equality/ancestor/descendant/unrelated behavior. With an
    existing marker, evaluate the exact `marker..candidate` range; with no
    marker, use candidate first-parent delta or empty tree for a root.
  - With an existing ancestor marker, prove several irrelevant merges keep the
    marker fixed and remain accumulated; a later relevant descendant includes
    them. With no marker, prove each candidate uses only its own first-parent/
    root delta. Do not claim every intermediate head survives pending
    replacement or uploads once.
  - Apply the exact app-path allowlist and emit this run's secret-free outcome
    for every executed eligibility result.

  **Ordered internal phase US2 — manual, failure, and distribution safety**:
  - Preserve `workflow_dispatch(force)`. `force=false` uses the normal range
    gate; `force=true` bypasses only path relevance and never candidate pinning,
    released-SHA equality, ancestry, version, secrets, signing, group proof, or
    marker compare-and-swap.
  - Cover mixed same-candidate automatic/manual order: automatic irrelevant
    skip permits later manual force; the first successful marker advance makes
    the other run skip.
  - Normalize the intended groups, prove each group exists before Fastlane, set
    `TESTFLIGHT_STRICT_UPLOAD=1`, then independently prove exact selected-build
    membership in every group before marker movement. Do not edit the Fastfile.
  - On preflight, build, upload, postflight, or marker-update failure, leave the
    marker unchanged and start no automatic retry/rollback. With an existing
    ancestor marker, prove a later descendant includes the failed change. With
    no marker, prove pickup requires a later independently app-relevant
    candidate or manual force; the manual run pins current main.
  - Do not add an attempt/confirmation journal, quarantine, marker-only
    reconciliation, or an exactly-once claim. An upload/marker split may be
    uploaded again by a later run under the accepted Owner tradeoff.

  **Ordered internal phase US3 — version and final integration**:
  - Preserve Fastlane's existing App Store Connect global maximum-plus-one build
    allocator and expose exactly one selected build number in log/summary. Do
    not add a second allocator.
  - Implement FR-009–FR-010 for project version, genuine lightweight marker,
    strict annotated marker metadata, labelled/unlabelled exact PR, direct
    push, ambiguous association, API failure, ephemeral project override,
    post-bump non-regression, and public-marker compare-and-swap.
  - Keep build/sign/upload only on `[self-hosted, aidash-mac]`, reuse exactly the
    five existing secrets and signing/profile path, and add no fallback, retry,
    rollback, tracked identity, alternate runner, or secret.
  - Make every failure leave the marker unchanged; update it only after lane
    success plus exact selected-build/all-group proof.

  **Replacement test and documentation acceptance**:
  - Replacement tests prove AC-01–AC-08 with payload/history/state fixtures:
    PR/fork/unreachable rejection and privilege ordering; exact candidates;
    missing-root/non-root/equal/ancestor/descendant/unrelated markers; existing-
    marker accumulated irrelevant merges; pending replacement without durable
    queue; absent-marker non-carry-forward/bootstrap; mixed auto/manual force;
    qualified failure pickup; strict public-marker metadata; group existence;
    exact-build membership; and no journal/recovery state.
  - Tests MUST remain compatible with the resolver gate's
    `/usr/bin/python3`, currently Python 3.9; do not use Python 3.10+ syntax or
    Python 3.11-only modules unless an approved refreshed base first changes
    the gate contract.
  - `docs/testflight-handoff.md` documents automatic operation, accumulated
    marker ranges, manual force, missing-marker bootstrap, distribution proof,
    failure pickup, the upload/marker split tradeoff, and absence of recovery
    state. It removes manual-only and superseded queue/journal guidance.
  - T001 completion proves AC-09–AC-10: the obsolete test is replaced, the fresh
    resolver-selected RepoInfra gate is green on the approved refreshed base,
    and the final implementation diff is exactly the four declared paths.

  **Quality bars**: Constitution cross-cutting quality bars apply automatically.

  **Layer / context**: `RepoInfra`; `scripts/CONTEXT.md`.

  **Contract impact**: Implements the complete
  `contracts/release-workflow.md` entrypoint, provenance, marker/range,
  version, distribution, failure, and summary contract.

  **Verification**: Activate repository hooks; stage only the four declared
  implementation paths and let the resolver run the RepoInfra gate
  (`/usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q`);
  confirm Python 3.9 compatibility, `git diff --check`, resolver ownership, and
  the exact path manifest. Do not run Xcode, host-based tests, a real upload, or
  a duplicate copy of hook-owned suites. Freeze the integrated candidate and
  obtain independent AI Reviewer PASS before commit/push/PR.

  **Dependencies**: No source dependency. Delivery/merge remains blocked by the
  Team Lead-owned MY-1692 repair landing and fresh eligible parked-PR terminal
  proof described below.

## Final delivery gates

- The exact reviewed package—`.specify/feature.json`, the Spec Kit marker block
  in `AGENTS.md`, and `specs/007-release-workflow/**`—remains byte-identical.
- The planning base's known Python 3.9/`tomllib` RepoInfra failure is not an
  accepted baseline. The refreshed delivery candidate must obtain a fully green
  resolver-selected RepoInfra gate or return blocked evidence to Team Lead.
- Fullstack's frozen candidate receives AI Reviewer prepublication PASS before
  commit/push/PR.
- The pushed SHA, remote branch SHA, and PR `headRefOid` match exactly.
- Owner approval is required for the protected workflow path.
- Merge/ship waits for the separately governed MY-1692 review-machinery landing
  and fresh parked-PR terminal proof. A later base refresh invalidates prior
  exact-head review/check evidence.
- After merge, Team Lead/PR Manager records the next eligible release run URL
  and build number on the delivery issue; no manual smoke-test issue is created.

## Traceability validation

- T001 is the sole Spec Kit task and therefore the sole Multica implementation
  issue/PR. US1–US3 are non-dispatchable internal phases.
- T001 implements FR-001–FR-015. Its replacement tests prove AC-01–AC-08;
  integrated completion proves AC-09–AC-10; external Team Lead/PR Manager gates
  prove AC-11–AC-12.
- T001 owns exactly one layer and declares exact paths, exclusions, the sole
  allowed release marker, contract impact, acceptance, verification, and
  dependency.
- The internal phase graph is acyclic and serialized because all phases modify
  the same workflow, test, and guide.
- No phase requires Fullstack to invent product behavior or broaden scope.
