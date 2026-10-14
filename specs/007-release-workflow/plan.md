# Implementation Plan: Minimal CI-Gated TestFlight Release

**Branch**: `007-release-workflow` | **Date**: 2026-10-15 | **Spec**: `spec.md`

## Summary

Replace AIDash's manual-only release entry with the Owner-approved cross-app
minimal pattern: one self-hosted release job, one non-cancelling concurrency
group, one moving last-released marker, exact CI-head checkout with full
history, focused path relevance, the unchanged Fastlane lane, success-only
marker movement, and unconditional cleanup. Keep manual force. Delete the
manual-only regression and discard the unpublished shadow-policy suite; verify
only the relevance classifier, stable workflow structure, and workflow lint.

## Technical context

**Language/Version**: GitHub Actions YAML and Bash; focused Python tests must
remain compatible with `/usr/bin/python3` (Python 3.9 on the planning base)

**Dependencies**: `actions/checkout@v4`, Git history/tags, existing
`fastlane ios beta`; no new action, package, service, or secret

**State**: Only the existing lightweight `testflight/last-released` tag

**Target**: GitHub Actions plus `[self-hosted, aidash-mac]`

**Scope**: One RepoInfra implementation task/issue/PR, four owned paths or
fewer

## Repository authority and base

- Repository: `https://github.com/LeePepe/AIDash`
- Revision-4 planning starts from reviewed revision-3 SHA
  `efc5760d496a92934fba096ef54e48fb4d1fe86e` on
  `agent/planner-lead/389b2a66f633`.
- Authority: `AGENTS.md` → `.specify/memory/constitution.md` →
  `CONTEXT.md` → `scripts/CONTEXT.md`; no shared-ci pin exists.
- All planning and implementation paths resolve to dependency-free layer
  `RepoInfra`.
- Owner decision B on MY-1777 authorizes this re-scope and ordinary job-level
  `contents: write`; `.github/**` still requires Owner approval before merge.

## Constitution check

- Scope remains one layer and one PR goal.
- No product schema, dependency, identity, or credential is added.
- Existing hook/CI gates and host-test safety rules remain unchanged.
- Removed test coverage is explicitly Owner-authorized and replaced by the
  narrower relevance/structure/lint surface.
- No constitutional exception is required.

## Planning artifacts and implementation paths

The planning package remains the two routing authorities plus these eight
Spec 007 artifacts. They are frozen after exact-revision PASS.

Owned implementation paths:

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py   # delete/rename
scripts/ci/tests/test_testflight_release.py       # concise replacement
docs/testflight-handoff.md
```

Prohibited paths include `.github/workflows/build.yml`, `fastlane/**`,
`project.yml`, `Configs/**`, app/package/CLI/aidata source, review machinery,
repository routing/constitution, and every planning artifact.

## Minimal architecture

```text
trusted workflow_run head_sha ─┐
                               ├─> one serialized self-hosted release job
manual pinned official main ───┘        permissions: contents: write
                                           │ checkout exact SHA, depth 0
                                           │ validate official-main reachability
                                           v
                             fetch testflight/last-released
                               │ equal -> skip
                               │ ancestor -> marker..candidate
                               │ absent + manual force -> bootstrap
                               │ absent otherwise -> fail closed
                               │ otherwise -> fail closed
                                           v
                          focused AIDash relevance classifier
                               │ irrelevant and not force -> skip
                                           v
                    existing secret/signing setup + fastlane ios beta
                                           v
                         success only: move last-released tag
                                           v
                     always: summary + local tag/keychain cleanup
```

The job-level event guard must reject PR/fork/wrong-workflow/wrong-branch/
non-success payloads. `actions/checkout` pins the selected SHA with
`fetch-depth: 0` and `persist-credentials: false`; the job token is supplied
only to marker movement. This is credential hygiene inside the Owner-authorized
job permission, not a separate CAS boundary. No newer `main` tip is
substituted. The release worker may
fetch official `main` and tags as metadata but must not execute another ref.

## Relevance and marker rules

The classifier allowlist is exactly:

```text
Apps/AIDashApp/**
Packages/AIDashCore/**
Packages/AIDashUI/**
Packages/DesignKit/**
Configs/**
project.yml
fastlane/**
```

An existing ancestor marker accumulates all changes through the candidate.
Equality skips. Non-ancestor state fails closed. Missing marker fails automatic
and non-force execution; manual `force=true` may bootstrap the exact pinned
current-main candidate. Force otherwise bypasses only classifier output.

The public marker stays lightweight and moves with the existing ordinary
contents-write push only after `fastlane ios beta` succeeds. There is no CAS
protocol, marker metadata, label-derived version, distribution readback,
attempt journal, recovery state, retry, or rollback.

## Repository-specific release preservation

- Keep `[self-hosted, aidash-mac]` and concurrency group `testflight`.
- Keep the five existing secrets and the login-keychain unlock/signing flow.
- Keep runtime provisioning-profile fetch and the unchanged lane.
- Keep the lane's global build-number allocation and current internal-group
  distribution behavior.
- Scope ASC/keychain secrets to the build/upload path. An `always()` cleanup
  removes workflow-created temporary refs/artifacts and restores keychain state
  changed by the workflow. Do not invent a temporary keychain where AIDash
  currently uses the login keychain.

## Verification design

Replace the current manual-only test with a concise Python 3.9 suite that:

1. unit-tests the AIDash allowlist with every included family and representative
   excluded docs/specs/workflow/scripts/CLI/aidata paths;
2. asserts the stable YAML contract: both entrypoints, exact head checkout,
   full history, one concurrency group, force limited to relevance, success-
   only marker movement, signing-secret step scope, and `always()` cleanup;
3. contains no copied provenance, marker, version, distribution, or outcome
   state machine.

AIDash has no installed or repository-declared `actionlint` binary. Keep the
four-path scope by making the replacement test perform repository-local
workflow lint (YAML parse/structure plus syntax checks for the exact extracted
classifier block), then run resolver-selected RepoInfra gates,
`scripts/context/audit`, task freshness, placeholder/pointer checks, and
`git diff --check`. Do not add a lint dependency or fifth path, and do not run
app tests, `xcodebuild`, or a real upload.

## Delivery sequencing

1. Commit and publish only this planning revision on the existing Planner
   branch; obtain AI Reviewer spec-gate PASS bound to its exact SHA.
2. Reconcile MY-1777 only after PASS. The preserved unpublished candidate
   `e8c353ce61e5cc3b6167481598b35556bb4dc02a` remains parked and is not an
   implementation base or publication candidate.
3. Team Lead authorizes reuse of the registered delivery workspace and the
   exact reviewed planning base. Fullstack replaces the superseded four-path
   candidate rather than pushing or incrementally repairing it.
4. The normal two-round implementation review budget restarts for this new
   accepted plan version. A blocking round-2 verdict parks delivery and returns
   to Owner without another escalation or review round.
5. Implementation and PR preparation may proceed after PASS. Merge still waits
   for refreshed eligible MY-1692 proof and Owner approval of `.github/**`.
6. After merge, record the next eligible run URL and build number on the
   delivery issue; do not create a manual smoke-test issue.

## Acceptance traceability

| Acceptance | Requirements | Task |
|---|---|---|
| AC-01 | FR-001–FR-002 | T001 |
| AC-02 | FR-004–FR-005 | T001 |
| AC-03 | FR-006 | T001 |
| AC-04 | FR-003, FR-007 | T001 |
| AC-05 | FR-008 | T001 |
| AC-06 | FR-009–FR-011 | T001 |
| AC-07 | FR-012 | T001 |
| AC-08 | FR-003, FR-013–FR-014 | T001 |
| AC-09 | FR-015 + repository gates | T001 |
| AC-10 | owned/prohibited paths | T001 |
| AC-11 | protected approval + MY-1692 | Team Lead / PR Manager |
| AC-12 | post-merge evidence | Team Lead / PR Manager |

## Risks and explicit tradeoffs

- Job-level `contents: write` is broader than revision 3's proposed CAS-only
  boundary. Owner decision B explicitly accepts this simpler design.
- Upload and marker movement are non-atomic; a marker-push failure can permit a
  later duplicate external upload. No exactly-once claim is made.
- Existing Fastlane internal-group distribution remains best-effort unless the
  lane itself fails. This revision does not add workflow-owned ASC proof.
- GitHub may replace pending concurrency members. Accumulated relevance is
  retained only through the unchanged ancestor marker range.
- The planning-base RepoInfra gate's known Python 3.9/`tomllib` failure remains
  MY-1692-owned and is not waived. Delivery needs a fresh green gate on its
  approved refreshed base.

## Complexity tracking

The revision removes complexity; no constitutional waiver is required.
