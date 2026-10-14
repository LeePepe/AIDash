# Feature Specification: CI-Gated TestFlight Release

**Feature Branch**: `007-release-workflow`

**Created**: 2026-10-15

**Status**: Ready for final planning review

**Input**: Owner decision dated 2026-10-14, refined by the delegated Owner
decision dated 2026-10-15: automatically release the latest trusted
CI-verified protected-`main` head when the accumulated change since the last
successful release is app-relevant, while preserving safe manual dispatch and
the existing signing infrastructure.

## Authority and supersession

This feature replaces only the TestFlight trigger policy in Spec 004 section C
and task T205, plus the later manual-only policy introduced by commit
`a542b31256a49168e380dd7c28f26c07e52ed9d6`. It does not reopen completed iOS
application work from Spec 004 and does not restore Spec 004's obsolete
scheduled release.

The 2026-10-15 refinement supersedes the queue-start, queue/cursor/skip,
attempt/confirmation journal, quarantine, and marker-only recovery model from
the earlier MY-1767 planning revision. The sole durable release-progress state
is `testflight/last-released`. The repository has no tracked `CODEOWNERS` file;
the Owner decision classifies `.github/**` as protected and requires Owner
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
  `cancel-in-progress: false` and runner labels `[self-hosted, aidash-mac]`.
  GitHub may replace an older pending member of a concurrency group; the group
  serializes actual release work but is not a durable per-head queue.
- Fastlane already queries App Store Connect for the maximum build number
  across all marketing versions and uses the next integer. Signing profiles
  are fetched at runtime and the existing ASC/keychain secrets are reused.
- Internal-group distribution is best-effort unless the workflow sets
  `TESTFLIGHT_STRICT_UPLOAD=1`; the existing lane also logs and skips an absent
  requested group, so workflow-owned group validation is required.
- `scripts/ci/tests/test_testflight_manual_only.py` intentionally rejects any
  automatic trigger, and `docs/testflight-handoff.md` documents manual-only
  operation.

## User scenarios and testing

### User Story 1 - Release an eligible verified head automatically (Priority: P1)

As the Owner, I receive a TestFlight build for the latest exact CI-verified
`main` head when the accumulated range since the last successful release
contains an app-relevant change.

**Independent Test**: Feed representative `workflow_run` payloads and Git
histories to the workflow contract tests. Only a completed successful
same-repository `build.yml` push on protected `main`, for an exact reachable
candidate with a safe marker relationship and an app-relevant accumulated
range, reaches the release steps.

**Acceptance Scenarios**:

1. **Given** the required `build` workflow completed successfully from a
   same-repository `push` to protected `main`, **when** `marker..candidate`
   contains an app-relevant change, **then** that exact candidate may build and
   upload inside the serialized per-app release worker.
2. **Given** an existing ancestor marker and one or more successive trusted
   candidates whose accumulated range remains docs-, spec-, CI-, CLI-, review-,
   or aidata-only, **when** each is evaluated, **then** each executed run skips,
   the marker remains unchanged, and the next descendant evaluates the still-
   accumulated range.
3. **Given** a pull-request-origin, fork-origin, failed, cancelled, non-`main`,
   wrong-workflow, invalid-SHA, or unreachable event, **when** the release
   workflow evaluates it, **then** it fails closed before candidate checkout,
   a self-hosted runner, signing, or upload and records the reason.

---

### User Story 2 - Preserve safe manual control (Priority: P1)

As the Owner, I can still dispatch the release workflow manually and use
`force=true` to release the current protected-`main` head even when its
accumulated diff is not app-relevant.

**Independent Test**: Exercise manual payloads with and without `force`, mixed
automatic/manual ordering, missing/prior/equal/descendant/unrelated marker
states, and release failures.

**Acceptance Scenarios**:

1. **Given** current protected `main`, **when** manual dispatch runs with
   `force=true`, **then** path relevance may be bypassed but candidate pinning,
   released-SHA protection, ancestry, secret, signing, group, version, and
   upload safety checks remain mandatory.
2. **Given** the marker already resolves to the selected candidate, **when** any
   manual or automatic run evaluates it, **then** it skips before upload and
   never re-releases that recorded SHA.
3. **Given** automatic and manual runs select the same candidate, **when** they
   serialize, **then** an automatic irrelevant skip leaves manual force able to
   release it; if either run succeeds and advances the marker, the other skips.

---

### User Story 3 - Carry release version intent without drift (Priority: P2)

As the Owner, releases keep the current effective marketing version, while a
candidate associated with a merged PR labelled `release:minor` advances the
minor version once and later successful releases continue on that version.

**Independent Test**: Validate version selection for no marker, legacy
lightweight marker, annotated marker, labelled merged PR, unlabelled PR, direct
push, ambiguous PR association, and API failure.

**Acceptance Scenarios**:

1. **Given** an exact merged PR associated with the candidate and carrying
   `release:minor`, **when** release metadata is selected, **then** the current
   effective `major.minor` version advances by one minor step for that upload
   and is persisted in the successful release marker metadata.
2. **Given** no `release:minor` label, **when** a later eligible release runs,
   **then** it uses the greater of the project-configured version and the last
   successfully released effective version; it never regresses after a prior
   label-driven bump.
3. **Given** the PR/label API is unavailable or returns contradictory exact-head
   associations, **when** version intent cannot be proven, **then** the run
   fails closed before upload. A direct push or proven no-associated-PR
   candidate means no label and does not bump the minor version.

## Requirements

### Functional requirements

- **FR-001 — Trusted automatic trigger**: The workflow MUST register
  `workflow_run` for the repository workflow named `build`, type `completed`,
  branch `main`, and MUST accept an automatic candidate only when the source
  run is the repository's `.github/workflows/build.yml`, its event is `push`,
  its conclusion is `success`, its head branch is `main`, and
  `head_repository.full_name == github.repository`.
- **FR-002 — Exact verified candidate**: Automatic execution MUST select
  `github.event.workflow_run.head_sha`. Before candidate checkout, self-hosted
  execution, release-secret reference, signing, or upload, a hosted read-only
  provenance stage MUST fetch protected `main` from the official repository,
  prove that the SHA is a commit reachable from it, and pin it. It MUST NOT
  replace that SHA with a newer tip. Manual execution MUST resolve current
  protected `main` once in the same read-only manner and pin that result.
- **FR-003 — Marker-only serialization and accumulation**: Automatic and manual
  release workers MUST share one per-app concurrency group with
  `cancel-in-progress: false`. No queue, cursor, skip, attempt, confirmation,
  quarantine, or recovery ref MAY be introduced. With an existing marker, path
  relevance MUST use `marker..candidate`; a skip or failure MUST leave the
  marker unchanged so later candidates naturally re-evaluate the accumulated
  range. GitHub may replace pending runs, so the contract MUST NOT promise one
  upload or one terminal summary for every intermediate head.
- **FR-004 — Released-SHA and ancestry safety**: Before any release side effect,
  the workflow MUST strictly parse and dereference `testflight/last-released`.
  Marker equality is an absolute no-upload skip. An ancestor marker permits the
  normal accumulated range. If the marker is a descendant of a stale
  candidate, the run MUST skip without rewinding. An unrelated marker and
  candidate MUST fail closed. The marker MUST never move backwards.
- **FR-005 — Missing-marker bootstrap**: If the marker is absent, an automatic
  run MUST compare the candidate with its first parent, or the empty tree for a
  root commit, and release only when that delta is app-relevant. A manual
  `force=true` run MAY bootstrap a marker. A workflow-only enabling merge MUST
  skip; the first later app-relevant candidate can bootstrap without another
  durable state.
- **FR-006 — App relevance**: Without manual force, at least one changed path in
  the applicable comparison range MUST match this exact allowlist:
  `Apps/AIDashApp/**`, `Packages/AIDashCore/**`, `Packages/AIDashUI/**`,
  `Packages/DesignKit/**`, `Configs/**`, `project.yml`, or `fastlane/**`.
  Docs, specs, `.github/**`, `scripts/**`, `CLI/**`, and `aidata/**` alone MUST
  not trigger an upload.
- **FR-007 — Manual compatibility**: `workflow_dispatch` and its boolean
  `force` input MUST remain. Without force it follows the same relevance gate;
  with force it bypasses only FR-006, never FR-002–FR-005 or any signing,
  secret, version, distribution, and upload validation.
- **FR-008 — Build number**: The existing App Store Connect global counter
  (`maximum build across all marketing versions + 1`) MUST remain the sole
  build-number allocator. Serialized release work MUST prevent two runs from
  reserving the same number. The selected build number MUST be visible in the
  run log and successful summary.
- **FR-009 — Marketing version**: The workflow MUST derive an effective version
  from `project.yml` plus the last successful marker metadata. A proven exact
  merged PR labelled `release:minor` increments the minor component once and
  resets any patch component to zero. Other releases retain the effective
  version. The override MAY exist only in the isolated release checkout; the
  workflow MUST NOT push a version commit to `main`.
- **FR-010 — Sole durable release marker**: Only after build, upload, and
  internal distribution are independently proven successful, the workflow
  MUST compare-and-swap `testflight/last-released` to an annotated tag pointing
  at the uploaded candidate and containing the effective marketing version and
  selected build number. A genuine legacy lightweight marker remains readable
  and falls back to the project version. An annotated marker with missing,
  empty, malformed, duplicate, or unknown metadata, or a marker that does not
  dereference to a commit, MUST fail preflight; only a genuine lightweight tag
  receives legacy fallback.
- **FR-011 — Fail-closed upload**: The workflow MUST set
  `TESTFLIGHT_STRICT_UPLOAD=1`, normalize one non-empty set of intended internal
  groups, and use the existing ASC credentials to prove before Fastlane that
  every exact group exists. After the lane succeeds it MUST parse exactly one
  selected build number and independently prove that exact build belongs to
  every intended group before marker movement. Missing/duplicate groups,
  absent/ambiguous build metadata, absent membership, missing secrets,
  Xcode/tooling failure, signing failure, upload failure, invalid metadata,
  label lookup failure, or marker compare-and-swap failure MUST fail closed.
  There is no automatic retry, rollback, alternate runner, or credential path.
- **FR-012 — Existing infrastructure**: The release job MUST run on
  `[self-hosted, aidash-mac]`, reuse the existing ASC API key and keychain
  secrets, runtime-fetched provisioning profile, and existing Fastlane lane.
  It MUST introduce no new secret or tracked identity.
- **FR-013 — Observable run outcome**: Every run that reaches eligibility
  evaluation MUST record its own concise, secret-free outcome and reason in
  `$GITHUB_STEP_SUMMARY`. A success MUST record candidate SHA, effective
  marketing version, build number, and run URL. No run is responsible for an
  eventual summary for a different or platform-replaced pending candidate.
- **FR-014 — Failure pickup**: A preflight, build, upload, distribution-proof,
  or marker-update failure MUST leave `testflight/last-released` unchanged and
  MUST NOT automatically retry or roll back. With an existing ancestor marker,
  a later trusted descendant re-evaluates `marker..candidate` and includes the
  failed relevant change. With no marker, a later automatic run still uses only
  its own first-parent/root delta, so pickup requires a later independently
  app-relevant candidate or manual `force=true`. A later manual run always pins
  current `main`. Because no attempt journal exists, the contract guarantees
  only that a SHA recorded by the marker is not released again; it does not
  claim exactly-once behavior after an external upload succeeds but marker
  movement fails.
- **FR-015 — Gate interpreter compatibility**: Replacement workflow contract
  tests MUST run under the RepoInfra local gate's `/usr/bin/python3`, currently
  Python 3.9 on the approved planning base. They MUST NOT use Python 3.10+
  syntax or Python 3.11-only standard-library modules unless an explicitly
  approved refreshed base first changes the repository gate contract.

## Compatibility

- The manual entry point and `force` input remain compatible. Self-hosted
  build/upload runner labels, five existing secrets, runtime signing/profile
  fetch, Fastlane upload lane, intended internal group contract, and public
  moving marker name remain compatible.
- `testflight/last-released` remains the only durable release-progress state;
  no new ref namespace, database, artifact, secret, or recovery input is added.
- Existing lightweight `testflight/last-released` tags, if later restored, are
  accepted. Their missing version metadata falls back safely to `project.yml`.
- Current app binaries, schemas, product behavior, CLI behavior, aidata, CI
  build/review policy, rulesets, and required-check names are unchanged.
- The reviewed planning artifacts remain byte-identical during implementation;
  implementation changes are limited to the owned paths declared in the plan.

## Removed behavior

The Owner decisions authorize removal of:

- manual-only triggering and regression assertions that reject automatic
  `workflow_run` events;
- checkout of a moving `main` tip for an automatic release;
- `force=true` re-upload of a SHA already recorded by the public marker;
- treating every new commit as release-worthy without app-path filtering;
- best-effort success when internal TestFlight group distribution failed;
- all superseded planning for queue-start/queue/cursor/skip refs, Actions API
  run materialization, attempt/confirmation refs, quarantine, marker-only
  recovery, and operator recovery inputs;
- claims that every eligible intermediate head survives pending replacement,
  uploads exactly once, or receives an eventual survivor-produced summary.

No test is deleted or weakened without replacement. The manual-only regression
is replaced by automatic-trigger, immutable-head, accumulated-range,
released-SHA, path-gate, version, strict-failure, and manual-compatibility
coverage.

## Explicit non-goals and prohibitions

- No scheduled/cron release is restored.
- No change to `.github/workflows/build.yml`, review workflows, rulesets,
  branch protection, required checks, runner/host configuration, credentials,
  or secret inventory. Only build, signing, and upload run on the existing
  self-hosted Mac; hosted provenance cannot execute candidate code or receive
  release secrets.
- No change to tracked `project.yml`, `fastlane/**`, `Configs/**`, application,
  package, CLI, or aidata sources. A marketing-version override is an ephemeral
  release-checkout transformation owned by the workflow.
- No edit to review-machinery repair paths: `scripts/ci/review-raven.py`,
  `scripts/ci/codex-review.sh`, `scripts/ci/tests/review_raven_contract.py`,
  `scripts/ci/tests/test_review_shell.py`, or
  `scripts/ci/raven-review-operations.md`.
- No queue/journal/recovery ref, new durable state, release bypass, branch
  force-push, manual required-check bypass, automatic rollback, or automatic
  retry.

## Edge cases

- Several irrelevant automatic merges leave the marker unchanged. Each
  existing-marker comparison is `marker..candidate`, so the range accumulates
  until a later candidate contains an app-relevant change.
- An irrelevant automatic run followed by manual `force=true` may release
  pinned current `main`. Same-candidate automatic and manual runs serialize;
  an automatic skip does not block force, while any successful marker advance
  makes the other run an equality skip.
- A failed eligible release leaves the marker unchanged. With an existing
  ancestor marker, a later descendant's range includes the failed relevant
  change and may release the newer exact head. With no marker, a later
  automatic candidate uses only its own first-parent/root delta, so it must be
  independently app-relevant; manual `force=true` may instead bootstrap pinned
  current `main`. None of these paths is an automatic retry.
- With no marker, a workflow-only enabling merge skips; the first later
  app-relevant merge evaluates only its first-parent delta and bootstraps.
- With no marker, if a relevant pending head is replaced by a later docs-only
  head, the later head also skips because it evaluates only its own delta;
  bootstrap waits for an independently relevant head or manual force.
- A marker is dereferenced before equality or ancestry checks. Equality skips;
  ancestor proceeds; descendant/stale candidate skips without rewind;
  unrelated histories fail closed.
- A genuine lightweight marker has no version metadata. An annotated marker
  with absent, malformed, duplicate, or unknown metadata, or a marker that does
  not dereference to a commit, fails rather than falling back.
- If upload or postflight proof succeeds but marker movement fails, no durable
  record distinguishes that external result. The marker stays unchanged and a
  later eligible run may upload again; the workflow MUST NOT claim stronger
  exactly-once recovery.
- A missing intended group fails before Fastlane; a group deleted after
  preflight or selected build missing any intended membership fails postflight
  and prevents marker movement.

## Stable acceptance criteria

- **AC-01**: FR-001–FR-002 are proven for trusted same-repository push
  provenance and rejection of PR/fork/wrong-workflow/non-main/non-success/
  invalid/unreachable events before checkout, self-hosted execution, or secrets.
- **AC-02**: FR-003–FR-005 are proven for marker missing/root/non-root,
  equal/ancestor/descendant/unrelated histories, accumulated irrelevant merges,
  pending replacement without per-head guarantees, and no-rewind behavior.
- **AC-03**: FR-006 is proven with every included path family and representative
  docs/specs/CI/review/CLI/aidata-only exclusions; every executed skip records a
  reason.
- **AC-04**: FR-007 is proven for force false/true and mixed automatic/manual
  same-candidate ordering, including proof that force cannot bypass marker
  equality, ancestry, provenance, or exact-head safety.
- **AC-05**: FR-008 preserves the existing global ASC counter and exposes the
  selected build number without introducing a second allocator.
- **AC-06**: FR-009–FR-010 are proven for configured version, genuine
  lightweight marker, every valid/invalid annotated-marker class, labelled and
  unlabelled exact merged PRs, direct pushes, API failure, persistent
  non-regression, and public-marker compare-and-swap.
- **AC-07**: FR-011–FR-012 are proven for normalized group validation, missing
  group before Fastlane, exact selected-build membership after upload, missing
  membership failure, existing secrets/signing, exact runner labels, and no
  fallback/retry/rollback path.
- **AC-08**: FR-013–FR-014 are proven for per-run success/skip/failure summaries,
  existing-marker failure pickup by a later descendant, absent-marker pickup
  only through an independently relevant candidate or manual force, unchanged
  marker on every failure, and no queue/journal/recovery behavior or
  exactly-once claim.
- **AC-09**: The manual-only test is replaced, not merely removed; the new tests
  cover AC-01–AC-08, remain Python 3.9-compatible under `/usr/bin/python3`, and
  the RepoInfra resolver-selected local gate passes on the approved refreshed
  delivery base.
- **AC-10**: The final implementation diff contains only
  `.github/workflows/testflight.yml`, the renamed/replacement TestFlight
  workflow contract test under `scripts/ci/tests/`, and
  `docs/testflight-handoff.md`; reviewed planning artifacts are unchanged.
- **AC-11**: Owner approval is recorded for the protected-path PR. No merge or
  ship occurs until the separately governed MY-1692 review-machinery bootstrap
  has landed and its fresh parked-PR proof has produced a real terminal verdict.
- **AC-12**: After merge, the next eligible app-relevant accumulated range
  produces a successful upload and the delivery issue records its run URL and
  build number.

## Success criteria

- **SC-001**: A trusted executed run with a safe candidate and app-relevant
  accumulated range uploads that exact candidate on a failure-free path and
  advances the sole public marker; a candidate already recorded by the marker
  performs zero upload operations.
- **SC-002**: Untrusted, duplicate, stale, unsafe, or non-app-relevant executed
  runs perform zero signing and zero upload operations and expose a reason.
- **SC-003**: Build numbers remain globally increasing, and a label-driven minor
  version never regresses on later successful releases.
- **SC-004**: The existing manual release entry point and signing setup continue
  to work without any new secret, identity, or durable state.
