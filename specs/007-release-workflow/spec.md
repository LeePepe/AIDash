# Feature Specification: CI-Gated TestFlight Release

**Feature Branch**: `007-release-workflow`

**Created**: 2026-10-15

**Status**: Ready for planning review

**Input**: Owner decision dated 2026-10-14: publish every app-relevant merge to
`main` automatically after the required CI workflow succeeds, while preserving
the manual release entry point and existing signing infrastructure.

## Authority and supersession

This feature replaces only the TestFlight trigger policy in Spec 004 section C
and task T205, plus the later manual-only policy introduced by commit
`a542b31256a49168e380dd7c28f26c07e52ed9d6`. It does not reopen any completed
iOS application work from Spec 004 and does not restore Spec 004's obsolete
scheduled release.

The repository has no tracked `CODEOWNERS` file. The Owner decision for this
feature explicitly classifies `.github/**` as protected and requires Owner
approval for the implementation PR.

## Existing behavior

- `.github/workflows/testflight.yml` registers only `workflow_dispatch`, checks
  out the moving `main` ref, and can bypass its no-new-commit check with
  `force=true`. A merge never starts a TestFlight release.
- `testflight/last-released` is the configured idempotency marker, but no remote
  marker exists at the planning base.
- The release job already uses concurrency group `testflight` with
  `cancel-in-progress: false` and runner labels `[self-hosted, aidash-mac]`.
- Fastlane already queries App Store Connect for the maximum build number
  across all marketing versions and uses the next integer. Signing profiles
  are fetched at runtime and the existing ASC/keychain secrets are reused.
- Internal-group distribution is best-effort unless the workflow sets
  `TESTFLIGHT_STRICT_UPLOAD=1`.
- `scripts/ci/tests/test_testflight_manual_only.py` intentionally rejects any
  automatic trigger, and `docs/testflight-handoff.md` documents manual-only
  operation.

## User scenarios and testing

### User Story 1 - Release an eligible verified merge automatically (Priority: P1)

As the Owner, I receive one TestFlight build for an app-relevant `main` merge
only after the repository's required `build` workflow succeeds for that exact
commit.

**Independent Test**: Feed representative `workflow_run` payloads and repository
histories to the workflow contract tests. Only a completed successful `build`
run on `main`, for an exact head newer than the release marker and with an
app-relevant diff, reaches the release steps.

**Acceptance Scenarios**:

1. **Given** the required `build` workflow completed successfully on `main`,
   **when** its exact head contains an app-relevant change since the last
   released marker, **then** exactly that head is queued on the self-hosted Mac
   and uploaded once.
2. **Given** a successful run whose diff is docs-, spec-, CI-, CLI-, review-, or
   aidata-only, **when** eligibility is evaluated, **then** no build or upload
   runs and the job summary names the skip reason.
3. **Given** a failed, cancelled, non-`main`, wrong-workflow, stale, or
   non-ancestral event, **when** the release workflow evaluates it, **then** it
   fails closed before signing or upload and records the reason.

---

### User Story 2 - Preserve safe manual control (Priority: P1)

As the Owner, I can still dispatch the release workflow manually and use
`force=true` to release a new, safe `main` head even when its diff is not
app-relevant.

**Independent Test**: Exercise manual payloads with and without `force`, with a
missing marker, a prior marker, and a same-SHA marker.

**Acceptance Scenarios**:

1. **Given** a new `main` head, **when** manual dispatch runs with `force=true`,
   **then** path eligibility may be bypassed but exact-SHA idempotency, ancestry,
   secret, signing, and upload safety checks remain mandatory.
2. **Given** the marker already resolves to the selected head, **when** any
   manual or automatic run evaluates it, **then** it skips before upload; the
   same SHA is never uploaded twice.

---

### User Story 3 - Carry release version intent without drift (Priority: P2)

As the Owner, normal releases keep the current effective marketing version,
while a merged PR labelled `release:minor` advances the minor version once and
later releases continue on that version.

**Independent Test**: Validate version selection for no marker, legacy
lightweight marker, annotated marker, labelled merged PR, unlabelled PR, direct
push, ambiguous PR association, and API failure.

**Acceptance Scenarios**:

1. **Given** an exact merged PR associated with the verified head and carrying
   `release:minor`, **when** release metadata is selected, **then** the current
   effective `major.minor` version advances by one minor step for that upload
   and is persisted in the successful release marker metadata.
2. **Given** no `release:minor` label, **when** a later eligible release runs,
   **then** it uses the greater of the project-configured version and the last
   successfully released effective version; it never regresses after a prior
   label-driven bump.
3. **Given** the PR/label API is unavailable or returns contradictory exact-head
   associations, **when** version intent cannot be proven, **then** the run fails
   closed before upload. A direct push or a proven no-associated-PR head means
   no label and does not bump the minor version.

## Requirements

### Functional requirements

- **FR-001 — Automatic trigger**: The workflow MUST register
  `workflow_run` for the repository workflow named `build`, type `completed`,
  branch `main`, and MUST release automatically only when the conclusion is
  `success`.
- **FR-002 — Exact verified head**: Automatic execution MUST select and check
  out `github.event.workflow_run.head_sha`. It MUST NOT replace that immutable
  SHA with the current `main` tip. Manual execution MUST resolve `main` once and
  pin the resulting SHA for the entire run.
- **FR-003 — Serialized safety**: All entry points MUST share one per-app
  concurrency group and MUST use `cancel-in-progress: false`. A release MUST
  never be retried automatically or rolled back automatically.
- **FR-004 — Marker ordering and idempotency**: Before upload, the workflow
  MUST dereference `testflight/last-released` to a commit, reject an identical
  candidate, and require an existing marker to be an ancestor of the candidate.
  It MUST never move the marker backwards. `force` MUST NOT bypass these rules.
- **FR-005 — Missing-marker bootstrap**: If the marker is absent, an automatic
  run MUST compare the verified candidate with its first parent (or the empty
  tree for a root commit) and release only when that candidate commit is
  app-relevant. A manual `force=true` run MAY bootstrap a new marker. A
  workflow-only enabling merge MUST therefore skip rather than upload.
- **FR-006 — App relevance**: Without manual force, at least one changed path in
  the comparison range MUST match this exact allowlist:
  `Apps/AIDashApp/**`, `Packages/AIDashCore/**`, `Packages/AIDashUI/**`,
  `Packages/DesignKit/**`, `Configs/**`, `project.yml`, or `fastlane/**`.
  Docs, specs, `.github/**`, `scripts/**`, `CLI/**`, and `aidata/**` alone MUST
  not trigger an upload.
- **FR-007 — Manual compatibility**: `workflow_dispatch` and its boolean
  `force` input MUST remain. Without force it follows the same relevance gate;
  with force it bypasses only FR-006, never FR-002–FR-005 or any signing,
  secret, version, and upload validation.
- **FR-008 — Build number**: The existing App Store Connect global counter
  (`maximum build across all marketing versions + 1`) MUST remain the sole
  build-number allocator. Concurrency MUST prevent two runs from reserving the
  same number. The selected build number MUST be visible in the run log and
  final summary.
- **FR-009 — Marketing version**: The workflow MUST derive an effective version
  from `project.yml` plus the last successful marker metadata. A proven exact
  merged PR labelled `release:minor` increments the minor component once and
  resets any patch component to zero. Other releases retain the effective
  version. The override MAY exist only in the isolated release checkout; the
  workflow MUST NOT push a version commit to `main`.
- **FR-010 — Durable release marker**: Only after build, upload, and internal
  distribution all succeed, the workflow MUST atomically replace
  `testflight/last-released` with an annotated tag pointing at the uploaded
  commit and containing the effective marketing version. Legacy lightweight
  markers remain readable and fall back to the project version.
- **FR-011 — Fail-closed upload**: The workflow MUST set
  `TESTFLIGHT_STRICT_UPLOAD=1`. Missing secrets, Xcode/tooling failure, signing
  failure, upload failure, internal distribution failure, invalid metadata,
  label lookup failure, or marker push failure MUST make the run fail. There is
  no automatic retry, rollback, alternate runner, or alternate credential path.
- **FR-012 — Existing infrastructure**: The job MUST run on
  `[self-hosted, aidash-mac]`, reuse the existing ASC API key and keychain
  secrets, runtime-fetched provisioning profile, and existing Fastlane lane.
  It MUST introduce no new secret or tracked identity.
- **FR-013 — Observable outcome**: Every skip or failure MUST record a concise
  reason in `$GITHUB_STEP_SUMMARY`. A success MUST record candidate SHA,
  effective marketing version, build number, and the GitHub run URL.
- **FR-014 — Post-merge evidence**: After the implementation merges, the next
  eligible app-relevant `main` merge MUST produce exactly one successful
  TestFlight upload. Its run URL and build number are recorded on the delivery
  issue; no separate manual smoke-test issue is created.

## Compatibility

- The manual entry point, `force` input, runner labels, concurrency behavior,
  five existing secrets, runtime signing/profile fetch, Fastlane upload lane,
  internal group, and moving marker name remain compatible.
- Existing lightweight `testflight/last-released` tags, if later restored, are
  accepted. Their missing version metadata falls back safely to `project.yml`.
- Current app binaries, schemas, product behavior, CLI behavior, aidata, CI
  build/review policy, rulesets, and required-check names are unchanged.
- The reviewed planning artifacts remain byte-identical during implementation;
  implementation changes are limited to the owned paths declared in the plan.

## Removed behavior

The Owner decision dated 2026-10-14 authorizes these removals:

- manual-only triggering and the regression assertions that reject automatic
  `workflow_run` events;
- checkout of a moving `main` tip for an automatic release;
- `force=true` re-upload of the already released SHA;
- treating every new commit as release-worthy without app-path filtering;
- best-effort success when internal TestFlight group distribution failed.

No test is deleted or weakened without replacement. The manual-only regression
is replaced by automatic-trigger, immutable-head, idempotency, path-gate,
version, strict-failure, and manual-compatibility coverage.

## Explicit non-goals and prohibitions

- No scheduled/cron release is restored.
- No change to `.github/workflows/build.yml`, review workflows, rulesets,
  branch protection, required checks, runner/host configuration, credentials,
  or secret inventory.
- No change to tracked `project.yml`, `fastlane/**`, `Configs/**`, application,
  package, CLI, or aidata sources. A marketing-version override is an ephemeral
  release-checkout transformation owned by the workflow.
- No edit to the review-machinery repair paths
  `scripts/ci/review-raven.py`, `scripts/ci/codex-review.sh`,
  `scripts/ci/tests/review_raven_contract.py`,
  `scripts/ci/tests/test_review_shell.py`, or
  `scripts/ci/raven-review-operations.md`.
- No release bypass, force-push of a branch, manual required-check bypass,
  automatic rollback, or automatic retry.

## Edge cases

- Multiple successful events queue without cancelling; ancestry checks make an
  older event fail closed after a newer commit has been released.
- A marker that resolves to a tag object is dereferenced to its commit before
  equality or ancestry checks.
- A candidate missing locally after checkout/fetch, an invalid SHA, a deleted
  marker target, or a non-ancestor marker fails before secrets are used.
- A release upload that succeeds but cannot persist its marker remains a failed
  run requiring explicit diagnosis. The next run does not happen
  automatically.
- A label added or removed after the merged PR's exact head is selected is read
  once during the serialized run and recorded in the summary.

## Stable acceptance criteria

- **AC-01**: FR-001–FR-003 are proven by workflow contract tests for automatic
  and manual payloads, exact checkout SHA, shared concurrency, and no
  cancellation.
- **AC-02**: FR-004–FR-005 are proven for marker missing, same SHA, ancestor,
  non-ancestor, root commit, and out-of-order event histories.
- **AC-03**: FR-006 is proven with every included path family and representative
  docs/specs/CI/review/CLI/aidata-only exclusions; every skip records a reason.
- **AC-04**: FR-007 is proven for manual force false/true, including proof that
  force cannot bypass same-SHA, ancestry, or exact-head safety.
- **AC-05**: FR-008 preserves the existing global ASC counter and exposes the
  selected build number without introducing a second allocator.
- **AC-06**: FR-009–FR-010 are proven for configured version, legacy marker,
  annotated marker, labelled and unlabelled exact merged PRs, direct pushes,
  label API failure, and persistent non-regression after a minor bump.
- **AC-07**: FR-011–FR-012 are proven by workflow assertions for strict internal
  distribution, existing secrets, runtime signing, exact runner labels, and no
  fallback/retry/rollback path.
- **AC-08**: FR-013 success/skip/failure summaries include the required fields
  without secrets or tracked identity values.
- **AC-09**: The manual-only test is replaced, not merely removed; the new tests
  cover AC-01–AC-08 and the RepoInfra resolver-selected local gate passes.
- **AC-10**: The final implementation diff contains only
  `.github/workflows/testflight.yml`, the renamed/replacement TestFlight
  workflow contract test under `scripts/ci/tests/`, and
  `docs/testflight-handoff.md`; reviewed planning artifacts are unchanged.
- **AC-11**: Owner approval is recorded for the protected-path PR. No merge or
  ship occurs until the separately governed review-machinery bootstrap has
  landed and its fresh parked-PR proof has produced a real terminal verdict.
- **AC-12**: After merge, the next eligible app-relevant `main` merge produces
  one upload and the delivery issue records its run URL and build number.

## Success criteria

- **SC-001**: Every eligible successful `main` CI head results in one and only
  one TestFlight upload of that exact commit.
- **SC-002**: Ineligible, stale, duplicate, unsafe, or non-app-relevant events
  perform zero signing and zero upload operations and expose a reason.
- **SC-003**: Build numbers remain globally increasing, and a label-driven minor
  version never regresses on later releases.
- **SC-004**: The existing manual release entry point and signing setup continue
  to work without any new secret or identity in version control.
