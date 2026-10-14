# Feature Specification: Minimal CI-Gated TestFlight Release

**Feature Branch**: `007-release-workflow`

**Created**: 2026-10-15

**Status**: Ready for planning review

**Input**: Owner decision B on MY-1777 dated 2026-10-15. Replace the
over-designed revision-3 release contract with the same minimal marker-plus-
relevance pattern used across AIDash, VitalStride, and VoxPocket, while
preserving this repository's runner, lane, build-number, and signing details.

## Authority and supersession

This revision supersedes MY-1767 planning revision 3 and the unpublished local
implementation candidates derived from it. Those candidates remain preserved
as evidence and MUST NOT be pushed or published. Implementation may resume
only from an exact revision of this package that receives AI Reviewer spec-gate
PASS.

This feature replaces only the current manual-only TestFlight trigger policy.
It does not change product code, the CI workflow, the Fastlane lane, signing
configuration, repository gates, or review policy. The repository has no
tracked `CODEOWNERS`; the Owner decision directly protects `.github/**` and
requires Owner approval before merge.

## Existing behavior

- `.github/workflows/testflight.yml` registers only `workflow_dispatch`,
  checks out moving `main`, and releases whenever HEAD differs from
  `testflight/last-released` or `force=true`.
- The workflow already uses concurrency group `testflight` with
  `cancel-in-progress: false` and runner labels `[self-hosted, aidash-mac]`.
- `fastlane ios beta` already fetches signing material at runtime, calculates
  the next globally increasing App Store Connect build number, uploads the
  build, and attempts internal-group distribution with existing credentials.
- The workflow uses five existing secrets and unlocks the runner's login
  keychain. No temporary signing keychain is created by the AIDash flow.
- `testflight/last-released` is a moving lightweight tag. No remote marker was
  present at the original planning base.
- `scripts/ci/tests/test_testflight_manual_only.py` asserts that automatic
  triggering is forbidden. `docs/testflight-handoff.md` describes manual-only
  operation.

## User scenarios and testing

### User Story 1 - Release an app-relevant verified main head (Priority: P1)

As the Owner, I receive an automatic TestFlight upload after the required CI
workflow succeeds for a trusted protected-`main` push whose accumulated range
contains an AIDash app change.

**Independent Test**: Workflow lint passes, the automatic event guard accepts
only the required same-repository successful `build.yml` push on `main`, and
focused relevance-classifier unit cases cover every included and excluded path
family.

**Acceptance Scenarios**:

1. **Given** the repository `build` workflow at `.github/workflows/build.yml`
   completed successfully for a same-repository push to `main`, **when** the
   marker-to-`head_sha` range contains an allowed path, **then** the one release
   job checks out that exact SHA with full history and invokes the existing
   lane.
2. **Given** the accumulated range contains only excluded paths, **when** the
   run evaluates relevance, **then** it skips upload, leaves the marker
   unchanged, and records the reason in the job summary.
3. **Given** the event is a PR/fork run, wrong workflow, wrong branch, failed or
   cancelled run, invalid SHA, or a SHA not reachable from official `main`,
   **when** the workflow evaluates it, **then** it fails closed before signing
   secrets or Fastlane are used.

### User Story 2 - Preserve manual force and failure safety (Priority: P1)

As the Owner, I can still run the workflow manually, optionally bypass path
relevance, without bypassing candidate, marker, signing, or upload safety.

**Independent Test**: Static workflow assertions cover `workflow_dispatch`,
the boolean `force` input, exact checkout, shared concurrency, success-only
marker movement, step-scoped signing secrets, and `always()` cleanup.

**Acceptance Scenarios**:

1. **Given** manual `force=false`, **when** current protected `main` is not
   app-relevant since the marker, **then** the run skips. With `force=true`,
   only relevance is bypassed.
2. **Given** the marker already equals the selected candidate, **when** either
   entrypoint runs, **then** it skips before upload even when forced.
3. **Given** build or upload fails, **when** the job terminates, **then** the
   marker remains unchanged, cleanup still runs, and no automatic retry or
   rollback is started.

## Requirements

### Functional requirements

- **FR-001 — Trusted automatic entry**: The workflow MUST register
  `workflow_run` for workflow `build`, branch `main`, type `completed`, and
  accept automatic work only when the source path is
  `.github/workflows/build.yml`, event is `push`, conclusion is `success`,
  head branch is `main`, and
  `head_repository.full_name == github.repository`.
- **FR-002 — Exact candidate**: Automatic work MUST pin
  `github.event.workflow_run.head_sha`; manual work MUST resolve official
  protected `main` once and pin it. The job MUST reject a malformed candidate
  or one not reachable from fetched official `main`, and MUST check out only
  that candidate with `fetch-depth: 0` and `persist-credentials: false`. It
  MUST NOT substitute a newer tip; the job token is supplied only to marker
  movement despite the job-level write permission.
- **FR-003 — One serialized release job**: Automatic and manual execution MUST
  use one AIDash concurrency group with `cancel-in-progress: false`, one
  `[self-hosted, aidash-mac]` release job, and plain job-level
  `permissions: contents: write` as explicitly authorized by Owner decision B.
  No separate hosted provenance or CAS-only permission job is required.
- **FR-004 — Marker relationship**: The sole durable release state MUST remain
  `testflight/last-released`. Equality MUST skip before upload. An ancestor
  marker permits relevance evaluation; a marker that is not an ancestor MUST
  fail closed rather than rewind. Skips and failures MUST leave it unchanged.
- **FR-005 — Missing-marker bootstrap**: An automatic or non-force manual run
  MUST fail closed when the marker is absent. Manual `force=true` MAY bootstrap
  the exact pinned current-main candidate and create the marker only after the
  existing lane succeeds. No implicit first-parent/root comparison is allowed.
- **FR-006 — AIDash relevance classifier**: Without manual force, at least one
  changed path MUST match `Apps/AIDashApp/**`, `Packages/AIDashCore/**`,
  `Packages/AIDashUI/**`, `Packages/DesignKit/**`, `Configs/**`,
  `project.yml`, or `fastlane/**`. Docs, specs, `.github/**`, `scripts/**`,
  `CLI/**`, and `aidata/**` alone MUST not release.
- **FR-007 — Manual compatibility**: `workflow_dispatch` and boolean `force`
  MUST remain. Force MAY bypass only FR-006; it MUST NOT bypass exact-candidate,
  marker-equality/ancestry, secret, signing, build, or upload failures.
- **FR-008 — Existing build number**: The workflow MUST preserve the unchanged
  lane's App Store Connect global maximum-plus-one build-number allocation.
- **FR-009 — Existing marketing version**: The workflow MUST preserve the
  tracked `project.yml` marketing version consumed by the unchanged lane. It
  MUST NOT add label lookup, marker-carried version state, or a project rewrite.
- **FR-010 — Success-only marker movement**: Only a successful return from the
  existing lane MAY move `testflight/last-released` to the exact candidate.
  The minimal design uses the existing moving tag and ordinary contents-write
  push; it does not add annotated marker metadata, a compare-and-swap protocol,
  or another durable ref.
- **FR-011 — Fail-closed lane and cleanup**: Invalid secrets, tooling, signing,
  build, or upload MUST fail the run and leave the marker unchanged. An
  `always()` cleanup step MUST remove workflow-created
  local temporary tags and signing artifacts and restore/lock any keychain
  state this workflow changed. AIDash MUST preserve its login-keychain-specific
  signing flow rather than inventing a cross-app temporary-keychain design.
- **FR-012 — Existing infrastructure**: Preserve `[self-hosted, aidash-mac]`,
  the five existing secrets, runtime provisioning-profile fetch, login-keychain
  flow, existing lane/internal-group behavior, and tracked identity boundaries.
  Signing and ASC secrets MUST be referenced only by the build/upload path. No
  new secret, identity, lane, or signing configuration is allowed.
- **FR-013 — Observable outcome**: Every run that evaluates eligibility MUST
  write a concise secret-free summary containing candidate, marker state,
  relevance/force result, and final outcome. Success MUST include the run URL;
  build number remains visible in the existing lane log.
- **FR-014 — Failure without recovery machinery**: Invalid provenance, history,
  marker, marker push, or release work MUST fail the run and leave the marker
  unchanged. There is no automatic retry, rollback, queue, cursor, skip record,
  attempt journal, recovery ref, or alternate runner.
- **FR-015 — Focused verification**: Delete the manual-only regression and do
  not port the unpublished shadow-policy suite. The replacement test MUST be a
  small Python 3.9-compatible relevance-classifier unit suite plus structural
  assertions for the stable entrypoint/safety contract. Action/workflow lint
  MUST validate the workflow. The implementation PR MUST list the removed
  manual-only and shadow-policy coverage explicitly.

## Compatibility

- `workflow_dispatch` and `force` remain available; force remains a
  relevance-only override.
- Runner labels, lane name, five secrets, runtime signing/profile fetch,
  internal-group behavior, global build-number allocation, and tracked
  `MARKETING_VERSION` behavior remain unchanged.
- `testflight/last-released` remains the public moving lightweight marker and
  the only durable release-progress state.
- App binaries, schemas, CLI, aidata, CI/review workflows, rulesets, required
  checks, Fastlane, project configuration, and signing files are unchanged.
- All three app repositories share the control-flow shape, but each keeps its
  repository-specific runner labels, secrets, lane, signing, paths, and gates.

## Removed behavior

Owner decision B authorizes removal of current manual-only trigger behavior and
its regression test. It also removes these unimplemented revision-3 planning
requirements: separate hosted provenance; CAS-only permission isolation;
annotated marker metadata; `release:minor` label/API automation; workflow-owned
group existence and exact-membership readback; terminal phase taxonomy;
per-head or exactly-once claims; and the large workflow-policy/history/state
fixture matrix. The unpublished 542-line shadow-policy candidate suite is
discarded, not ported.

No shipped product behavior or Fastlane test is removed. Replacement coverage
is intentionally limited to the relevance classifier, stable workflow
structure, and action/workflow lint required by the Owner's minimal v1.

## Explicit non-goals and prohibitions

- No scheduled release, new state store, new ref namespace, new secret,
  automatic retry, rollback, or alternate runner.
- No change to `.github/workflows/build.yml`, Fastlane, project/signing files,
  app/package/CLI/aidata sources, review machinery, rulesets, branch protection,
  required checks, or host configuration.
- No marketing-version mutation or `release:minor` lookup in this v1. The
  existing tracked `MARKETING_VERSION` continues to feed the existing lane.
- No workflow-owned App Store Connect group preflight/postflight. Existing lane
  behavior is preserved.
- No publication or reuse of candidates built against planning revision 3.

## Edge cases

- Several irrelevant merges leave the marker fixed, so a later candidate uses
  the accumulated `marker..candidate` range.
- Missing marker fails automatic and non-force execution; manual force may
  bootstrap the exact pinned current-main candidate after a successful upload.
- Manual force cannot re-upload the SHA already recorded by the marker.
- A marker not ancestral to the candidate fails closed and never rewinds.
- Upload success and marker push are not atomic. If upload succeeds but marker
  push fails, the marker remains unchanged and a later run may upload again.
  The minimal design records no recovery journal and makes no exactly-once
  claim.
- GitHub concurrency may replace a pending run. The unchanged marker range
  retains accumulated relevance for the next executed descendant; the workflow
  does not promise execution or a summary for every intermediate head.

## Stable acceptance criteria

- **AC-01**: Trusted automatic and manual candidates are pinned exactly,
  fetched with full history, and unsafe automatic payloads fail before signing
  secrets or Fastlane.
- **AC-02**: Marker equality, ancestor accumulation, non-ancestor failure, and
  force-only missing-marker bootstrap match FR-004–FR-005.
- **AC-03**: Every included and representative excluded AIDash path family is
  covered by focused classifier unit cases; skips leave the marker unchanged.
- **AC-04**: Manual force bypasses relevance only, and automatic/manual work
  shares one non-cancelling concurrency group.
- **AC-05**: The unchanged lane and global build-number allocator are preserved.
- **AC-06**: Tracked marketing version remains unchanged; marker movement occurs
  only after lane success and every failure leaves it unchanged.
- **AC-07**: Runner labels, five secrets, provisioning, login-keychain signing,
  lane/internal-group behavior, and step-scoped secret exposure are preserved.
- **AC-08**: One non-cancelling group, fail-closed behavior, `always()` cleanup,
  no retry/recovery state, and a secret-free skip/outcome summary are proven.
- **AC-09**: Python 3.9 classifier/structure tests, repository-local workflow
  lint, RepoInfra routing, and repository hook/CI gates pass.
- **AC-10**: The diff is limited to the four owned paths or fewer; the planning
  package and all prohibited paths remain unchanged during implementation.
- **AC-11**: Owner approval is recorded for `.github/**`, and MY-1692's
  refreshed eligible proof is satisfied before merge.
- **AC-12**: After merge, the next eligible run records its run URL on the
  delivery issue; its build number is captured from the existing lane log.

## Success criteria

- **SC-001**: A trusted app-relevant CI head reaches the unchanged lane once in
  its executed run and advances the marker only after lane success.
- **SC-002**: Irrelevant, duplicate, untrusted, or unsafe runs perform no build
  or upload and expose a concise reason.
- **SC-003**: Manual force, existing signing, existing global build numbers,
  and existing internal-group behavior remain operational without new state or
  credentials.
