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

## R3 — Trusted trigger and immutable candidate

**Decision**: Bind `workflow_run` to `.github/workflows/build.yml` / workflow
name `build`, type `completed`, source event `push`, branch `main`, conclusion
`success`, and the same head repository as the current repository. Before any
candidate checkout, self-hosted job, write authority, or release secret, a
hosted read-only stage bare-fetches official protected `main` and proves the
event's `head_sha` is a reachable commit.

**Evidence**: `.github/workflows/build.yml` is named `build` and runs on both
`pull_request` and `push`. GitHub's `workflow_run` follower may receive secrets
and write permission even when the source workflow did not, so workflow name,
branch label, conclusion, and SHA alone admit a fork PR head named `main`.
Checking out the moving branch after CI also creates a race and can upload a
different commit from the one CI verified.

**Alternatives rejected**: `push` alone cannot prove the required workflow
finished; branch/name-only `workflow_run` trust can elevate PR provenance;
checking out `main` violates exact-head evidence; scheduled release is obsolete.

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

## R6 — Durable queue, concurrency, and delayed events

**Decision**: Persist every trusted candidate in a strict workflow-owned queue
ref before job-level concurrency. Only the self-hosted drain worker uses group
`testflight` with `cancel-in-progress: false`. Under that lock, reconcile the
authoritative successful protected-main `build.yml` push runs across the
release/activation boundary, materialize missing queue entries, revalidate
provenance, de-duplicate by SHA, and drain first-parent order. With no public
marker, derive activation from the unique protected-main first-parent commit
that introduces the workflow's `release-contract-schema: 1` sentinel. The
queue-start ref targets that commit with run-independent strict metadata, so
simultaneous creators converge after refetch even if their annotated tag object
IDs differ. Missing/multiple/mismatched activation evidence or an activation
commit later than the candidate fails closed. Same-SHA remains an absolute skip and marker ancestry is
mandatory. Manual force bypasses path relevance only.

**Evidence**: GitHub concurrency retains at most one running and one pending
member; a new pending member replaces the old pending member even when
`cancel-in-progress` is false. Durable refs before the group preserve intent.
Queue refs alone still leave an event-delivery race where a later candidate
could drain before an earlier follower enqueues, so authoritative Actions API
reconciliation and exhaustive pagination are also required. A first-admission-
derived boundary is likewise unsafe when a newer head wins creation before an
older follower; the sentinel-derived boundary is independent of arrival order.

**Alternatives rejected**: Workflow-level concurrency can discard pending
heads; queue-only intake can reorder heads; blind tag movement can move release
state backward; preserving current force semantics violates idempotency.

## R7 — Build number and proven internal distribution

**Decision**: Preserve Fastlane's App Store Connect global maximum plus one;
set strict mode, and add workflow-owned two-sided ASC verification. Normalize
the existing group-name contract and require every group to exist before the
attempt. After the lane, parse exactly one selected build number and require ASC
to show that exact build in every intended group before confirmation.

**Evidence**: `fastlane/Fastfile` already supplies a global monotonic counter
across marketing versions. Its missing-group branch logs and skips without
raising, so `TESTFLIGHT_STRICT_UPLOAD=1` alone does not make a misspelled or
absent group fatal. Preflight prevents known absence; postflight catches a race,
silent skip, missing membership, or ambiguous build result.

**Alternatives rejected**: A second workflow counter risks collision or reuse;
editing the prohibited Fastfile broadens scope; best-effort distribution or a
strict-mode-only assertion does not prove that testers received the build.

## R8 — Marketing-version persistence

**Decision**: Persist the effective marketing version in strict annotated
confirmation and `testflight/last-released` tags. Use the greater of the project
version and the last effective version; apply one minor bump for a proven exact
merged PR label. Only a genuine lightweight legacy public marker falls back to
the project version; invalid annotated metadata fails preflight.

**Evidence**: A transient bump alone would regress on the next unlabelled
release because tracked `project.yml` remains unchanged. Pushing a version
commit would mutate `main` with code CI did not verify and create a release loop.

**Alternatives rejected**: Editing/pushing `project.yml`; adding a new secret or
database; treating malformed annotated state as legacy; relying on mutable PR
state without exact-head association.

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

## R12 — At-most-once upload and marker-only recovery

**Decision**: Use create-only annotated
`testflight/attempted/<sha>` and `testflight/confirmed/<sha>` journal refs around
the irreversible upload. The attempt is remotely confirmed immediately before
the sole lane invocation. Confirmation is remotely persisted only after exact
build/all-group proof, then the public marker moves with compare-and-swap. A
confirmed-but-unmarked SHA reconciles without Fastlane. An attempted-only SHA is
quarantined and blocks descendants; explicit reconciliation can only confirm it
after exact operator SHA/build input and ASC-backed version/build/all-group
evidence. Recovery uses only existing ASC readback credentials, creates no new
attempt, and can never checkout, build, sign, distribute, invoke Fastlane, or
upload; the normal five-secret release preflight is inapplicable.

**Evidence**: App Store Connect upload and a Git ref update are not one atomic
transaction. If upload succeeds but the process or marker push fails, a marker-
only design cannot distinguish success from failure and may upload the same SHA
again. A durable pre-upload attempt makes automatic invocation at-most-once; a
post-upload confirmation supports eventual marker repair without a second lane.

**Alternatives rejected**: Retrying an unknown attempt violates same-SHA
idempotency; writing `last-released` before upload can suppress a failed release;
blind force-push loses concurrent state; automatic deletion of quarantine
silently chooses a product/release policy not authorized by the Owner.

## R13 — Gate interpreter and one implementation unit

**Decision**: Keep the replacement tests compatible with the RepoInfra gate's
`/usr/bin/python3`, currently 3.9, and model all three user-story phases inside
one Spec Kit task `T001`, one Multica implementation issue, and one PR.

**Evidence**: `scripts/CONTEXT.md` is the gate authority and names
`/usr/bin/python3`; the planning base reports Python 3.9. The constitution maps
each `tasks.md` task to a Multica issue, while `AGENTS.md` makes one PR the unit
of one issue. The phases intentionally edit the same workflow/test/guide.

**Alternatives rejected**: Requiring Python 3.11 contradicts the mandatory local
gate. Three T-numbers would imply three issues/PRs while claiming one delivery
unit and would create overlapping ownership of the same files.
