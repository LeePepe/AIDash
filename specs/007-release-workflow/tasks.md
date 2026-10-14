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
| US1 | Every trusted exact-CI-head intent survives scheduling and releases safely | None | T001 | AC-01, AC-02, AC-03, AC-07, AC-08 |
| US2 | Manual force and explicit marker-only recovery remain safe | US1 | T001 | AC-02, AC-04, AC-07 |
| US3 | Build/version intent persists without regression | US2 | T001 | AC-05, AC-06, AC-09, AC-10 |

External gates AC-11 and AC-12 are not implementation tasks. Team Lead and PR
Manager retain protected-path approval, MY-1692 sequencing, and post-merge
production evidence.

```text
T001: US1 trusted admission/drain
   -> US2 manual/recovery compatibility
   -> US3 version/journal/final integration
```

## Sole implementation task

- [ ] **T001** Replace the manual-only TestFlight policy with a trusted,
  durable, exact-head release state machine; preserve safe manual control and
  version intent; replace the obsolete contract test; and update operations.

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

  **Allowed release refs**:
  - Preserve `testflight/last-released` as the public moving release marker.
  - The workflow may add only the reviewed operational namespaces
    `testflight/queue-start`, `testflight/queue/**`,
    `testflight/attempted/**`, and `testflight/confirmed/**`.
  - Queue/journal refs use strict annotated metadata and the ownership,
    create-only, compare-and-swap, cleanup, and fail-closed rules in
    `contracts/release-workflow.md`. No other marker, branch, ref namespace,
    database, artifact store, or credential path may be introduced.

  **Ordered internal phase US1 — trusted automatic admission and drain**:
  - Implement FR-001–FR-006: require exact `build.yml`/`build`, `push`,
    same-repository, successful `main` provenance and protected-main
    reachability in a hosted read-only stage before checkout, self-hosted
    capacity, write authority, or release secrets.
  - Durably enqueue every proven candidate before job-level concurrency. Only
    the self-hosted drain worker uses group `testflight` with
    `cancel-in-progress: false`.
  - Add one unique `release-contract-schema: 1` workflow sentinel. With no
    public marker, derive queue-start from its unique protected-main first-
    parent introducing commit, exclude source-run metadata, and make concurrent
    creators converge by refetching and validating semantic target/metadata.
  - Under the lock, exhaustively reconcile successful protected-main build runs
    across the release/activation boundary, materialize missing queue entries,
    revalidate provenance, de-duplicate SHA entries, and drain in first-parent
    order. Pending-worker replacement or out-of-order follower delivery must
    not lose a candidate.
  - Enforce absolute marker equality/ancestry, safe missing-marker bootstrap,
    the exact app-path allowlist, per-candidate summaries, and zero release
    side effects for rejected/irrelevant candidates.

  **Ordered internal phase US2 — manual and recovery compatibility**:
  - Preserve `workflow_dispatch(force)`. `force=false` uses the normal path
    gate; `force=true` bypasses only app relevance and never provenance,
    candidate pinning, journal, equality, ancestry, version, secrets, signing,
    group proof, confirmation, or marker compare-and-swap.
  - Create a remote, create-only attempt immediately before the sole permitted
    Fastlane invocation. Attempted-only state is quarantined, blocks descendants,
    and cannot be cleared or re-uploaded by force.
  - Provide the explicit marker-only reconciliation branch defined by the
    contract: exact operator-supplied SHA/build evidence must match the attempt
    and independently verified ASC version/build/all-group membership; it may
    create confirmation and repair the marker but cannot checkout candidate
    code, create another attempt, invoke Fastlane, sign, build, distribute, or
    upload. Apply the common and recovery-only invariants, requiring only the
    existing ASC credentials needed for readback rather than the normal five-
    secret signing/release preflight.
  - Treat ambiguous state-ref pushes by refetching and validating remote state;
    never infer failure as permission to repeat an upload.

  **Ordered internal phase US3 — version, distribution, and final integration**:
  - Preserve Fastlane's existing App Store Connect global maximum-plus-one build
    allocator and expose exactly one selected build number in the success
    summary. Do not add a second allocator.
  - Implement FR-009–FR-010 for configured version, genuine lightweight public
    marker, strict annotated metadata, labelled/unlabelled exact PR, direct
    push, ambiguous association, API failure, ephemeral project override,
    create-only confirmation, post-bump non-regression, and public-marker
    compare-and-swap.
  - Normalize the intended internal groups; verify every exact group exists
    before the attempt; set `TESTFLIGHT_STRICT_UPLOAD=1`; after the lane,
    independently verify that the exact selected build belongs to every group.
    Missing group, missing membership, or absent/duplicate build metadata fails
    without confirmation. Do not edit `fastlane/Fastfile`.
  - Keep build/sign/upload only on `[self-hosted, aidash-mac]`, reuse exactly the
    five existing secrets and signing/profile path, and add no fallback, retry,
    rollback, tracked identity, alternate release runner, or secret.

  **Replacement test and documentation acceptance**:
  - Replacement tests prove AC-01–AC-08 with payload/history/state fixtures,
    including PR/fork/unreachable rejection, ordering before checkout/secrets,
    sentinel-derived activation, simultaneous first admissions, newer-before-
    older first intake, A/B/C pending-worker replacement, out-of-order API
    reconciliation, queue collision/deduplication, malformed refs, strict
    public/journal metadata,
    attempted-only quarantine, confirmed marker-only recovery, older attempt
    blocking a descendant, recovery-specific credential/side-effect boundaries,
    group existence, exact-build membership, and manual force boundaries.
  - Tests MUST remain compatible with the resolver gate's
    `/usr/bin/python3`, currently Python 3.9; do not use Python 3.10+ syntax or
    Python 3.11-only modules unless an approved refreshed base first changes
    the gate contract.
  - `docs/testflight-handoff.md` documents automatic operation, queue/journal
    states, group proof, quarantine, explicit marker-only recovery, and the ban
    on rerunning an attempted SHA. It removes manual-only and "rerun after
    interruption" guidance.
  - T001 completion proves AC-09–AC-10: the obsolete test is replaced, the fresh
    resolver-selected RepoInfra gate is green on the approved refreshed base,
    and the final implementation diff is exactly the four declared paths.

  **Quality bars**: Constitution cross-cutting quality bars apply automatically.

  **Layer / context**: `RepoInfra`; `scripts/CONTEXT.md`.

  **Contract impact**: Implements the complete
  `contracts/release-workflow.md` entrypoint, provenance, durable queue,
  marker/journal, version, distribution, recovery, and summary contract.

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

- T001 is the sole Spec Kit task and therefore the sole Multica
  implementation issue/PR. US1–US3 are non-dispatchable internal phases.
- T001 implements FR-001–FR-015. Its replacement contract tests prove
  AC-01–AC-08; integrated completion proves AC-09–AC-10; external Team Lead/PR
  Manager gates prove AC-11–AC-12.
- T001 owns exactly one layer and declares exact paths, exclusions, release-ref
  namespaces, contract impact, acceptance, verification, and dependency.
- The internal phase graph is acyclic and serialized because all phases modify
  the same workflow, test, and guide.
- No phase requires Fullstack to invent product behavior or broaden scope.
