# Research: CI-Gated TestFlight Release

## R1 — Repository authority

**Decision**: Use repository-local rules without a shared-ci overlay.

**Evidence**: `AGENTS.md` points to the constitution and recursive context
router. No `shared-ci@<SHA>` reference or tracked `CODEOWNERS` file exists.
`.github/**`, `scripts/**`, and `docs/**` resolve to `RepoInfra` through
`scripts/CONTEXT.md`.

**Alternatives rejected**: Inventing CODEOWNERS patterns or editing protection
configuration. The Owner decision directly supplies approval authority.

## R2 — New Spec Kit feature rather than rewriting Spec 004

**Decision**: Create `specs/007-release-workflow/` and preserve Spec 004 as
completed history.

**Evidence**: Spec 004 describes the original iOS/TestFlight rollout and an
obsolete scheduled release. Commit `a542b312…` later established manual-only
behavior without updating it. The current Owner decision is a new release-policy
revision with new acceptance and operational state.

**Alternatives rejected**: Rewriting completed T205 would erase the chronology;
using active Spec 006 would mix unrelated team-workflow scope.

## R3 — Trigger and immutable candidate

**Decision**: Bind `workflow_run` to workflow name `build`, type `completed`,
branch `main`, conclusion `success`, and checkout the event's `head_sha`.

**Evidence**: `.github/workflows/build.yml` is named `build` and runs on
`main`. Checking out the moving branch after CI creates a race and can upload a
different commit from the one CI verified.

**Alternatives rejected**: `push` cannot itself prove the required workflow
finished; checking out `main` violates exact-head evidence; scheduled release is
explicitly obsolete.

## R4 — Path relevance

**Decision**: Compute a Git diff after checkout because `workflow_run` has no
native paths filter. Use the exact allowlist in the spec.

**Evidence**: App product sources are the app target and three packages; signing
and build inputs are `Configs/**`, `project.yml`, and `fastlane/**`. CLI, aidata,
docs, specs, CI/review scripts, and workflow-only changes do not alter the app
archive.

**Alternatives rejected**: Treating every merge as app-relevant wastes signing
and TestFlight builds; an unrestricted repo diff contradicts the Owner decision.

## R5 — Missing marker bootstrap

**Decision**: On no marker, inspect only the candidate's first-parent delta (or
empty-tree delta for a root commit). Auto-release only an app-relevant candidate;
allow manual force to bootstrap.

**Evidence**: The remote marker does not currently exist. Diffing the entire
repository against the empty tree would classify the workflow-only enabling
merge as app-relevant, violating the path-skip requirement.

**Alternatives rejected**: Always fail on a missing marker would prevent the
Owner's first automatic release; empty-tree whole-history comparison would
release a CI-only merge.

## R6 — Idempotency and delayed events

**Decision**: Same-SHA is an absolute skip and existing marker ancestry is
mandatory. Manual force bypasses path relevance only.

**Evidence**: The Owner requires that a SHA never upload twice. Shared queued
concurrency does not itself prevent an older completed workflow event from
running after a newer release.

**Alternatives rejected**: Preserving current force semantics violates the
explicit idempotency requirement; blindly force-moving the tag can move release
state backward.

## R7 — Build number and strict upload

**Decision**: Preserve Fastlane's App Store Connect global maximum plus one;
enable strict internal-group distribution from the workflow.

**Evidence**: `fastlane/Fastfile` already supplies a global monotonic counter
across marketing versions. It only fails on group distribution when
`TESTFLIGHT_STRICT_UPLOAD=1`.

**Alternatives rejected**: A second workflow counter risks collision or reuse;
best-effort distribution contradicts fail-closed release semantics.

## R8 — Marketing-version persistence

**Decision**: Persist the effective marketing version in an annotated
`testflight/last-released` tag. Use the greater of the project version and the
last effective version; apply one minor bump for a proven exact merged PR label.

**Evidence**: A transient bump alone would regress on the next unlabelled
release because tracked `project.yml` remains unchanged. Pushing a version
commit would mutate `main` with code CI did not verify and create a release loop.

**Alternatives rejected**: Editing/pushing `project.yml`; adding a new secret or
database; relying on mutable PR state without exact-head association.

## R9 — Exact implementation scope

**Decision**: Keep all implementation in RepoInfra: workflow, replacement
contract test, and operating guide. The workflow performs any version override
only in its isolated checkout.

**Evidence**: This preserves one layer and reuses the existing Fastlane lane.

**Alternatives rejected**: Editing `fastlane/Fastfile` or tracked
`project.yml` would introduce an XcodeWorkspace slice and broaden the issue.

## R10 — Delivery dependency

**Decision**: Planning and PR preparation can proceed, but merge/ship waits for
the separately governed review-machinery repair to land and for a fresh
eligible parked-PR event to produce a real terminal verdict.

**Evidence**: The accepted sequencing contract distinguishes planning/source
work from release of dependent AIDash PRs. Setup failures or pre-landing reruns
are not proof.

**Alternatives rejected**: Treating the dependency as source overlap; assuming
repair behavior exists on the planning base; refreshing a parked branch early.

## R11 — Planning-base gate failure

**Decision**: Record and carry the existing RepoInfra gate failure as a hard
delivery dependency; do not edit or waive it in this feature.

**Evidence**: On the pinned base, the resolver-selected local gate runs with
`/usr/bin/python3` 3.9. `scripts/ci/review-raven.py` imports `tomllib`, producing
two direct review-machinery test failures and one cascading hook-regression
failure. The failing implementation/test paths are owned by the separate repair
plan and are prohibited here. Spec Kit prerequisites, context audit, task
freshness, placeholder scan, and whitespace checks pass for this package.

**Alternatives rejected**: Adding a dependency or editing review machinery
would violate exact scope; ignoring the result would fabricate green evidence.
Fullstack must obtain a fresh passing gate on its approved refreshed base.
