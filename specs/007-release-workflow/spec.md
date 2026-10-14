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
- `.github/workflows/build.yml` runs for both `pull_request` and `push`, so a
  workflow name, branch label, conclusion, and SHA alone are not trusted
  protected-`main` provenance for a credentialed `workflow_run` follower.
- `testflight/last-released` is the configured idempotency marker, but no remote
  marker exists at the planning base.
- The release job already uses concurrency group `testflight` with
  `cancel-in-progress: false` and runner labels `[self-hosted, aidash-mac]`;
  GitHub retains at most one pending member of a concurrency group, so this
  setting protects the running upload but cannot by itself preserve every head.
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

**Independent Test**: Feed representative `workflow_run` payloads, Actions API
histories, and Git histories to the workflow contract tests. Only a completed
successful same-repository `build.yml` push on protected `main`, for an exact
reachable head newer than the release marker and with an app-relevant diff,
reaches the release steps.

**Acceptance Scenarios**:

1. **Given** the required `build` workflow completed successfully from a
   same-repository `push` to protected `main`, **when** its exact reachable head
   contains an app-relevant change since the last released marker, **then**
   that head is durably admitted before the serialized self-hosted worker and
   is uploaded once on the successful path.
2. **Given** a successful run whose diff is docs-, spec-, CI-, CLI-, review-, or
   aidata-only, **when** eligibility is evaluated, **then** no build or upload
   runs and the job summary names the skip reason.
3. **Given** a pull-request-origin, fork-origin, failed, cancelled, non-`main`,
   wrong-workflow, stale, unreachable, or non-ancestral event, **when** the
   release workflow evaluates it, **then** it fails closed before candidate
   checkout, the self-hosted runner, signing, or upload and records the reason.

---

### User Story 2 - Preserve safe manual control (Priority: P1)

As the Owner, I can still dispatch the release workflow manually and use
`force=true` to release a new, safe `main` head even when its diff is not
app-relevant.

**Independent Test**: Exercise normal manual payloads with and without `force`,
plus explicit marker-only reconciliation, with missing/prior/same-SHA markers
and attempted/confirmed journal states.

**Acceptance Scenarios**:

1. **Given** a new `main` head, **when** manual dispatch runs with `force=true`,
   **then** path eligibility may be bypassed but exact-SHA idempotency, ancestry,
   secret, signing, and upload safety checks remain mandatory.
2. **Given** the marker already resolves to the selected head, **when** any
   manual or automatic run evaluates it, **then** it skips before upload; the
   same SHA is never uploaded twice.
3. **Given** an attempted-only SHA and exact operator-supplied build evidence,
   **when** explicit reconciliation independently proves the ASC version/build
   and all intended group memberships, **then** it writes confirmation and
   repairs the public marker without candidate checkout, Fastlane, signing,
   distribution, or upload; absent proof leaves the quarantine unchanged.

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

- **FR-001 — Trusted automatic trigger**: The workflow MUST register
  `workflow_run` for the repository workflow named `build`, type `completed`,
  branch `main`, and MUST admit an automatic candidate only when the source run
  is the repository's `.github/workflows/build.yml`, its event is `push`, its
  conclusion is `success`, its head branch is `main`, and
  `head_repository.full_name == github.repository`.
- **FR-002 — Exact verified head**: Automatic execution MUST select and check
  out `github.event.workflow_run.head_sha`. Before candidate checkout, use of
  the self-hosted runner, release secrets, signing, or upload, a read-only
  provenance stage MUST fetch protected `main` from the official repository,
  prove that SHA resolves to a commit reachable from it, and pin it. It MUST NOT
  replace that immutable SHA with the current `main` tip. Manual execution MUST
  resolve protected `main` once in the same read-only manner and pin the result.
- **FR-003 — Durable serialized admission**: Every trusted candidate MUST be
  persisted in a strictly validated workflow-owned queue ref before entering
  the shared release-worker concurrency group. Only the drain/release job uses
  group `testflight` with `cancel-in-progress: false`; an ungrouped admission
  job cannot execute candidate content or receive release secrets. With no
  public marker, the workflow MUST locate exactly one commit on freshly fetched
  protected `main`'s first-parent history that introduces the unique
  `.github/workflows/testflight.yml` sentinel `release-contract-schema: 1`;
  `testflight/queue-start` MUST target that deterministic activation commit and
  MUST contain no admitting-run metadata. Missing or multiple introducing
  commits, an activation commit later than the candidate, or target/metadata-
  mismatched activation evidence fails closed. Concurrent creators
  MAY produce different annotated tag object IDs, but the losing creator MUST
  refetch and accept the existing boundary only when its target and strict
  semantic metadata match that same activation commit. Before draining, the
  worker MUST exhaustively reconcile successful protected-`main`
  `build.yml` push runs across the bounded release/activation range, materialize
  any missing queue entries, de-duplicate by SHA, and process them in
  first-parent order. Incomplete API pagination, provenance, or range evidence
  fails closed. Replacement of a pending worker MUST NOT lose a candidate.
- **FR-004 — Journaled idempotency and recovery**: Before any upload, the
  workflow MUST dereference `testflight/last-released` to a commit, reject an
  identical candidate, and require an existing marker to be an ancestor of the
  candidate. After deterministic preflight it MUST create a remote,
  create-only attempt record immediately before the one permitted Fastlane
  invocation. After upload and distribution are independently confirmed it
  MUST persist a create-only confirmation record before moving the public
  marker by compare-and-swap. A confirmation with a lagging marker is repaired
  by marker-only reconciliation with no build, signing, or Fastlane invocation.
  An attempt without confirmation is quarantined, blocks later candidates, and
  can never be retried by `force`. Explicit recovery MUST validate the exact
  attempted SHA, strict refs/metadata, marker ancestry, operator-supplied build,
  and exact ASC version/build/all-group membership, using only the existing ASC
  readback credentials it needs. It MUST NOT require the normal release path's
  five-secret/signing preflight, create a new attempt, checkout candidate code,
  or invoke build, signing, Fastlane, distribution, or upload. The marker MUST
  never move backwards.
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
  distribution all succeed and a confirmation record is durable, the workflow
  MUST compare-and-swap `testflight/last-released` to an annotated tag pointing
  at the uploaded commit and containing the effective marketing version and
  confirmed build metadata. A genuine legacy lightweight public marker remains
  readable and falls back to the project version. An annotated public marker,
  queue entry, attempt, or confirmation with missing, empty, malformed,
  duplicate, unknown, or target-mismatched metadata MUST fail preflight.
- **FR-011 — Fail-closed upload**: The workflow MUST set
  `TESTFLIGHT_STRICT_UPLOAD=1`, normalize one non-empty set of intended internal
  groups, and use the existing ASC credentials to prove before the attempt that
  every exact group exists. After the lane succeeds it MUST parse exactly one
  selected build number and independently prove that exact build belongs to
  every intended group before confirmation. Missing or duplicate groups,
  absent or ambiguous build metadata, absent membership, missing secrets,
  Xcode/tooling failure, signing failure, upload failure, invalid metadata,
  label lookup failure, or state-ref push failure MUST fail closed. There is no
  automatic retry, rollback, alternate build runner, or credential path.
- **FR-012 — Existing infrastructure**: The job MUST run on
  `[self-hosted, aidash-mac]`, reuse the existing ASC API key and keychain
  secrets, runtime-fetched provisioning profile, and existing Fastlane lane.
  It MUST introduce no new secret or tracked identity.
- **FR-013 — Observable outcome**: Every skip or failure MUST record a concise
  per-candidate reason in the eventual drain worker's `$GITHUB_STEP_SUMMARY`.
  A success MUST record candidate SHA, effective marketing version, build
  number, and the GitHub run URL. A platform-cancelled pending worker is not a
  terminal candidate outcome; the durable queue entry remains for a survivor.
- **FR-014 — Post-merge evidence**: After the implementation merges, the next
  eligible app-relevant `main` merge MUST produce exactly one successful
  TestFlight upload. Its run URL and build number are recorded on the delivery
  issue; no separate manual smoke-test issue is created.
- **FR-015 — Gate interpreter compatibility**: Replacement workflow contract
  tests MUST run under the RepoInfra local gate's `/usr/bin/python3`, currently
  Python 3.9 on the approved planning base. They MUST NOT use Python 3.10+
  syntax or Python 3.11-only standard-library modules unless an explicitly
  approved refreshed base first changes the repository gate contract.

## Compatibility

- The manual entry point and `force` input remain compatible; optional exact
  marker-only recovery inputs are additive and never upload. Self-hosted
  build/upload runner labels, five existing secrets, runtime signing/profile
  fetch, Fastlane upload lane, internal group, and public moving marker name
  remain compatible. Read-only hosted provenance and write-only admission jobs
  add no alternate build or upload runner.
- Workflow-owned queue, attempt, and confirmation refs are additive operational
  state. They never replace `testflight/last-released` as the public release
  marker and never authorize a second upload.
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
- reliance on one shared concurrency group's pending slot as a durable queue;
- blind force-replacement of release state after an ambiguous upload.

No test is deleted or weakened without replacement. The manual-only regression
is replaced by automatic-trigger, immutable-head, idempotency, path-gate,
version, strict-failure, and manual-compatibility coverage.

## Explicit non-goals and prohibitions

- No scheduled/cron release is restored.
- No change to `.github/workflows/build.yml`, review workflows, rulesets,
  branch protection, required checks, runner/host configuration, credentials,
  or secret inventory. Only build, signing, and upload run on the existing
  self-hosted Mac; control-plane provenance/admission cannot execute candidate
  code or receive release secrets.
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

- Multiple successful events first create durable queue entries. GitHub may
  replace a pending drain worker, but the surviving worker reconciles the
  authoritative successful-run range and drains every proven head in
  first-parent order.
- A marker that resolves to a tag object is dereferenced to its commit before
  equality or ancestry checks.
- A genuine lightweight public marker has no version metadata. An annotated
  marker with absent, malformed, duplicate, or unknown metadata fails rather
  than falling back.
- A candidate missing locally after checkout/fetch, an invalid SHA, a deleted
  marker target, or a non-ancestor marker fails before secrets are used.
- A durable confirmation with a failed public-marker update is reconciled by a
  later worker without invoking Fastlane. An attempt without confirmation has
  unknown external state and remains quarantined; explicit recovery may only
  create confirmation and reconcile the marker after exact ASC/build/group and
  run-log proof. Clearing the attempt or uploading again requires a new Owner
  decision.
- A missing intended group fails before the attempt; a group deleted after
  preflight or a selected build missing any intended membership fails after the
  attempt and remains quarantined without confirmation.
- A label added or removed after the merged PR's exact head is selected is read
  once during the serialized run and recorded in the summary.

## Stable acceptance criteria

- **AC-01**: FR-001–FR-003 are proven by workflow contract tests for trusted
  same-repository push provenance; PR/fork/unreachable rejection before
  checkout/secrets; deterministic sentinel-derived activation; simultaneous
  first admissions and newer-before-older intake with no public marker;
  exhaustive API reconciliation; and A/B/C pending-worker replacement with
  every proven head drained in first-parent order.
- **AC-02**: FR-004–FR-005 are proven for marker missing, same SHA, ancestor,
  non-ancestor, root commit, queue collision/deduplication, create-only attempt,
  attempted-only quarantine, confirmed marker-only recovery, unresolved older
  attempt blocking newer work, and out-of-order histories.
- **AC-03**: FR-006 is proven with every included path family and representative
  docs/specs/CI/review/CLI/aidata-only exclusions; every skip records a reason.
- **AC-04**: FR-007 is proven for manual force false/true, including proof that
  force cannot bypass same-SHA, ancestry, or exact-head safety.
- **AC-05**: FR-008 preserves the existing global ASC counter and exposes the
  selected build number without introducing a second allocator.
- **AC-06**: FR-009–FR-010 are proven for configured version, genuine
  lightweight marker, valid annotated marker, every invalid annotated-metadata
  class, labelled and unlabelled exact merged PRs, direct pushes, label API
  failure, persistent non-regression, create-only confirmation, and public-tag
  compare-and-swap reconciliation.
- **AC-07**: FR-011–FR-012 are proven for normalized group validation, missing
  group before attempt, exact selected-build membership after upload, missing
  membership quarantine, existing secrets, runtime signing, exact self-hosted
  build runner labels, and no fallback/retry/rollback path.
- **AC-08**: FR-013 success/skip/failure summaries include the required fields
  without secrets or tracked identity values.
- **AC-09**: The manual-only test is replaced, not merely removed; the new tests
  cover AC-01–AC-08, remain Python 3.9-compatible under `/usr/bin/python3`, and
  the RepoInfra resolver-selected local gate passes on the approved refreshed
  delivery base.
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

- **SC-001**: Every trusted eligible successful `main` CI head is durably
  admitted and, on a failure-free path, produces one TestFlight upload of that
  exact commit. Once an attempt record exists, automatic processing invokes the
  upload lane at most once; ambiguous external outcomes quarantine for explicit
  marker-only recovery and never trigger an automatic re-upload.
- **SC-002**: Ineligible, stale, duplicate, unsafe, or non-app-relevant events
  perform zero signing and zero upload operations and expose a reason.
- **SC-003**: Build numbers remain globally increasing, and a label-driven minor
  version never regresses on later releases.
- **SC-004**: The existing manual release entry point and signing setup continue
  to work without any new secret or identity in version control.
