# Implementation Plan: CI-Gated TestFlight Release

**Branch**: `007-release-workflow` | **Date**: 2026-10-15 | **Spec**: `spec.md`

**Input**: Feature specification from `specs/007-release-workflow/spec.md`

## Summary

Replace AIDash's manual-only TestFlight trigger with a trusted
`workflow_run`-driven release. Validate same-repository protected-`main` push
provenance before candidate checkout or privileges, durably enqueue every
proven head before the replaceable GitHub concurrency slot, and drain the queue
in first-parent order on the existing self-hosted Mac. Journal the irreversible
upload with create-only attempt and confirmation refs, verify exact TestFlight
group membership, and move the public release marker by compare-and-swap. Keep
the existing Fastlane lane, ASC build-number counter, secrets, signing, and
build runner unchanged. Implement the behavior in one RepoInfra issue/PR: the
workflow, its replacement contract tests, and its operating guide.

## Technical context

**Language/Version**: GitHub Actions YAML; POSIX/Bash on hosted Linux and
macOS; replacement `unittest`/`pytest` contract tests compatible with the
RepoInfra gate's `/usr/bin/python3` (Python 3.9 on the planning base; no
3.10/3.11-only syntax or standard-library dependency)

**Primary Dependencies**: GitHub Actions `workflow_run` and `workflow_dispatch`
payloads; `actions/checkout@v4`; repository Git history/tags; GitHub REST API via
the existing `GITHUB_TOKEN`; existing Fastlane `ios beta` lane

**Storage**: Strict workflow-owned Git refs for queue boundary/entries,
create-only upload attempts and confirmations, plus the existing
`testflight/last-released` public moving marker; App Store Connect remains the
global build-number allocator and external distribution authority

**Testing**: Resolver-selected RepoInfra pytest gate and repository hooks; no
app tests, host-based tests, manual upload, or `xcodebuild` during implementation

**Target Platform**: GitHub Actions control plane plus the existing
`[self-hosted, aidash-mac]` runner

**Project Type**: Repository release automation

**Performance Goals**: Untrusted events stop before candidate checkout,
self-hosted capacity, secret access, signing, archive, or upload; trusted
candidates survive pending-worker replacement and release work remains
serialized

**Constraints**: Exact CI head; fail closed; no new secret; no tracked identity;
no automatic retry/rollback; no branch/ruleset/review-gate change; Owner approval
required for `.github/**`

**Scale/Scope**: One workflow, one renamed/replacement contract test, one
operating guide; one implementation task/issue/PR serving one goal

## Repository authority and base

- Repository: `https://github.com/LeePepe/AIDash`
- Planning base: `bdf1435fe7d3d9c4da43ed4297cbc24482447b46`, equal to
  `origin/main` at planning start.
- Authority chain: `AGENTS.md` → `.specify/memory/constitution.md` →
  `CONTEXT.md` → `scripts/CONTEXT.md`. No `shared-ci@<SHA>` pin exists.
- `scripts/context/resolve` maps all implementation paths to `RepoInfra`, whose
  dependencies are empty.
- No tracked `CODEOWNERS` exists. The Owner decision for this work is the direct
  authority requiring Owner approval of the protected-path PR.

## Constitution check

### Before design

- **Scope discipline**: PASS. The slice declares exact paths and prohibitions.
- **Dependency direction**: PASS. All implementation paths resolve to one
  dependency-free RepoInfra layer.
- **Testing**: PASS. Existing manual-only assertions are replaced by deeper
  contract coverage; no test is silently deleted or weakened.
- **Identity hygiene**: PASS. No account, team, workspace, or credential value is
  added to tracked files.
- **Local safety**: PASS. Verification is hook/resolver-driven; no host-based app
  test or proactive Xcode suite is planned.
- **User-feedback policy**: PASS. Post-merge evidence is recorded on the delivery
  issue, not delegated to a manual smoke-test issue.

### After design

- The marker/version model and workflow contract introduce no app schema,
  storage, package, or dependency change.
- The exact-path plan remains a single RepoInfra layer.
- The design preserves required CI/review gates and adds no bypass.
- No constitutional exception or complexity waiver is required.

## Project structure

### Documentation for this feature

```text
specs/007-release-workflow/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── release-workflow.md
└── tasks.md
```

The reviewed planning package also includes `.specify/feature.json` and only
the `<!-- SPECKIT START/END -->` marker block in `AGENTS.md`. Those two routing
authorities select this feature together and remain frozen with the feature
artifacts during implementation.

### Owned implementation paths

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py   # removed/renamed
scripts/ci/tests/test_testflight_release.py       # replacement
docs/testflight-handoff.md
```

**Structure decision**: Keep release selection, version derivation, ephemeral
marketing-version injection, Fastlane invocation, summaries, and marker update
inside the existing workflow. Replace the obsolete manual-only contract test
with a release-policy contract test and update the existing operating guide.
The existing Fastlane lane remains unchanged and continues to allocate the build
number and perform signing/upload/distribution.

## Architecture and data flow

```text
build workflow completed ─┐
                          ├─> hosted read-only provenance + protected-main fetch
manual workflow_dispatch ─┘        (no checkout, candidate execution, or secrets)
                                      │
                                      v
                         ungrouped durable queue admission
                                      │
                                      v
                 serialized self-hosted drain worker (`testflight`)
                                      │
                 reconcile successful build runs + queue refs
                 revalidate provenance + first-parent order
                                      │
                 duplicate / stale / invalid ─> terminal candidate summary
                                      │
                           path/version/group preflight
                                      │
                     create-only attempted/<sha> ref
                                      │
             existing Fastlane lane + global ASC build counter
                                      │
                  exact-build/all-group membership proof
                                      │
                    create-only confirmed/<sha> ref
                                      │
                compare-and-swap last-released marker
```

Automatic and manual events share the same eligibility state machine. Only the
event-to-candidate proof and manual `force` relevance override differ. Hosted
provenance/admission jobs never build or upload; the existing
`[self-hosted, aidash-mac]` runner remains the only release worker. Marker
equality is an absolute no-upload rule. Ancestry and first-parent queue ordering
prevent delayed events from moving release state backward.

## Trusted provenance and durable queue design

- Automatic admission requires workflow path `.github/workflows/build.yml`,
  name `build`, source event `push`, completed/success, head branch `main`, the
  same head repository as `github.repository`, and a 40-hex head SHA.
- A read-only hosted job initializes a metadata-only Git repository, fetches
  official protected `main`, and proves the candidate commit is reachable. It
  does not use `actions/checkout`, execute repository code, request contents
  write, enter the self-hosted runner, or receive ASC/keychain secrets.
- The following ungrouped admission job is the first write-capable job. It
  creates an immutable, annotated `testflight/queue/<run-id>-<attempt>-<sha>`
  ref targeting the candidate. Exact retry is idempotent; a collision,
  mismatched target, or invalid/unknown metadata fails closed.
- The workflow carries one unique literal sentinel
  `release-contract-schema: 1`. With no public marker, scan freshly fetched
  protected `main` first-parent history and require exactly one commit that
  introduces that sentinel in `.github/workflows/testflight.yml`.
  `testflight/queue-start` targets that deterministic activation commit and its
  strict semantic metadata contains no admitting-run identity. Concurrent
  creators may produce different annotated tag object IDs; after a create race,
  the loser refetches and accepts the winner only when target and metadata match
  the derived activation commit. Missing/multiple introducing commits, an
  activation commit later than the candidate, or mismatched activation evidence
  fails closed. Before each drain, the worker uses
  `actions: read` to exhaustively reconcile successful same-repository
  `build.yml` push runs between the current public marker (or queue-start) and
  the newest queued head. Missing queue entries are materialized before any
  candidate checkout. Incomplete pagination or a history/API disagreement
  fails closed.
- Only the drain job uses job-level group `testflight` with
  `cancel-in-progress: false`. GitHub may replace a pending worker, but every
  candidate already has durable intent. The survivor rescans, revalidates
  source run IDs/attempts and protected-main reachability, de-duplicates SHA
  entries, and drains them oldest-first along protected `main`'s first-parent
  chain.
- Queue takeover before an attempt is continuation, not an upload retry. Queue
  entries are compare-and-swap deleted only after a terminal skip, successful
  release/reconciliation, or safe supersession. Attempted-only entries remain.

## Version and release-state design

- Project version: parse the tracked `MARKETING_VERSION` from `project.yml`.
- Marker version: parse a single validated `marketing-version=<semver>` field
  from the annotated `testflight/last-released` tag. Only a genuine lightweight
  legacy marker contributes no version and falls back to the project version.
  An annotated marker with missing/empty, malformed, duplicate, or unknown
  metadata fails preflight.
- Effective baseline: the semantically greater of project and marker versions.
- `release:minor`: only a proven exact merged PR for the candidate can set it;
  increment `major.minor`, resetting patch to zero. No PR/direct push means no
  bump. API or contradictory-association failure stops before upload.
- Build input: modify only the isolated checkout used by the runner so XcodeGen
  sees the effective version. Never commit or push this transformation.
- Attempt journal: after every deterministic preflight (including group
  existence) and immediately before Fastlane, create
  `testflight/attempted/<sha>` remotely with strict schema, candidate, effective
  version, intended groups, and source-run metadata. It is create-only. If the
  create cannot be positively confirmed, no lane runs.
- Confirmation journal: only after the lane succeeds, exactly one build number
  is parsed, and ASC independently proves that exact build belongs to every
  intended group, create `testflight/confirmed/<sha>` with strict version,
  build, group, candidate, and run metadata. It is also create-only.
- Public marker: after confirmation is durable, replace the annotated
  `testflight/last-released` ref only with `--force-with-lease` against the
  fetched prior tag-object ID. Its strict metadata carries the confirmed
  marketing version and build number. It is never a blind force-push.
- Recovery: a confirmation with a lagging ancestor marker takes a marker-only
  compare-and-swap path that invokes no checkout, Xcode, signing, or Fastlane.
  An attempt without confirmation is unknown external state: automatic and
  manual-force runs quarantine it and block later descendants. An explicit
  `workflow_dispatch` reconciliation mode accepts the exact SHA and build
  number, verifies the attempt plus exact ASC version/build/group membership
  with only the existing ASC readback credentials it needs, then creates
  confirmation and repairs the marker. Common state/ref, exact-SHA, marker
  ancestry/no-rewind, strict-metadata, and applicable ASC-evidence invariants
  remain mandatory. Recovery does not run the normal five-secret/signing/group-
  existence/new-attempt preflight and cannot create a new attempt, checkout
  candidate code, invoke the upload lane, build, sign, distribute, or upload.
  If proof is absent, quarantine remains; deleting the attempt or uploading
  again requires a new Owner decision.

The workflow captures Fastlane's existing selected-build message for the final
summary. Absence or duplication of that value after a nominally successful lane
is an invalid success, leaves the attempt quarantined, and prevents confirmation
or marker movement.

## Path eligibility contract

The workflow uses Git pathspecs, not a GitHub native path filter (which is not
available for `workflow_run`). The allowlist is exactly:

```text
Apps/AIDashApp/**
Packages/AIDashCore/**
Packages/AIDashUI/**
Packages/DesignKit/**
Configs/**
project.yml
fastlane/**
```

For an existing marker, compare `marker..candidate`. For a missing marker,
compare the candidate's first-parent delta, or empty-tree delta for a root
commit. This prevents the workflow-only enabling merge from releasing while
allowing the first subsequent app-relevant merge to bootstrap automatically.

## Permissions and failure policy

- The hosted provenance job has read-only contents/actions permission. It runs
  before any write token or release-secret reference.
- The ungrouped admission job adds only `contents: write` for strict queue refs
  and still has no candidate checkout, candidate execution, or release secrets.
- The serialized drain job has `actions: read`, read-only PR metadata, and
  `contents: write` for queue/journal/public-marker compare-and-swap updates.
  ASC/keychain secrets are referenced only after queued provenance is
  revalidated on the locked worker.
- Normalize the same `TESTFLIGHT_GROUPS` contract used by the existing lane
  (default `Internal`; comma-split/trim; reject empty or duplicate names).
  Before the attempt, query ASC and require every group to exist. Set
  `TESTFLIGHT_STRICT_UPLOAD=1`, run the lane once, parse exactly one selected
  build number, then query ASC again and require that exact build to belong to
  every intended group. This closes the current Fastfile branch that logs and
  skips a missing group without raising.
- Emit per-candidate outcomes on `always()` without exposing secrets or
  identity values. A replaced pending worker has no terminal candidate outcome;
  its durable entries remain. No failure starts an automatic upload retry or
  rollback.

## Delivery sequencing

1. This planning package may be reviewed now at the pinned planning base.
2. After exact-revision spec-gate PASS, Team Lead may dispatch one Fullstack
   Engineer. Under the scoped workspace protocol, Fullstack owns the first new
   issue-scoped delivery checkout and metadata registration.
3. Fullstack creates one implementation PR and may prepare it before the
   separate review-machinery dependency completes.
4. Merge/ship is blocked until Team Lead records the external repair landing and
   a fresh eligible parked-PR proof on the repaired base with a real terminal
   `pass` or `changes` verdict. Pre-landing reruns, setup failures, and invalid
   verdicts do not satisfy the dependency.
5. Because strict main synchronization may change the base, any refresh creates
   a new exact head and requires renewed implementation review, checks, and
   Owner approval before shipping.
6. After merge, record the next eligible release run URL and build number on the
   delivery issue. Do not create a manual smoke-test issue.

This dependency is a delivery-order constraint, not a source-code dependency;
the review-machinery repair paths are explicitly prohibited from this diff.

## Acceptance traceability

| Acceptance | Requirement coverage | Task |
|---|---|---|
| AC-01 | FR-001–FR-003 | T001 |
| AC-02 | FR-004–FR-005 | T001 |
| AC-03 | FR-006 | T001 |
| AC-04 | FR-007 | T001 |
| AC-05 | FR-008 | T001 |
| AC-06 | FR-009–FR-010 | T001 |
| AC-07 | FR-011–FR-012 | T001 |
| AC-08 | FR-013 | T001 |
| AC-09 | FR-015 + replacement tests + RepoInfra gate | T001 |
| AC-10 | Exact diff scope | T001 |
| AC-11 | Owner approval + delivery dependency | Team Lead / PR Manager gate |
| AC-12 | Post-merge run URL + build number | Team Lead / PR Manager evidence |

## Verification strategy

- Activate repository hooks in the delivery workspace.
- Let the staged commit/push flow run the resolver-selected RepoInfra gates.
- Required focused command if invoked through the resolver/hook:
  `/usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q`.
- The replacement test must remain Python 3.9-compatible under that exact
  interpreter unless an approved refreshed base first changes the gate.
- Confirm `scripts/context/resolve` maps each changed path to `RepoInfra` and
  `scripts/context/audit` remains clean through repository gates.
- Contract fixtures cover untrusted PR/fork events, protected-main reachability,
  sentinel-derived activation, simultaneous first admissions, newer-before-
  older intake, queue collision/deduplication, pending-worker replacement,
  out-of-order ingestion/API reconciliation, strict journal metadata,
  quarantine and mode-specific marker-only recovery, group existence and exact-
  build membership, and prove checkout/secrets/Fastlane cannot precede
  provenance.
- Run `git diff --check` and validate the exact four-path implementation
  add/delete/modify set.
- Do not run `xcodebuild`, app tests, a real upload, or duplicate test suites
  manually during implementation.
- Before publication, freeze the local candidate and obtain AI Reviewer PASS on
  that exact content. Any content change invalidates review.

## Planning validation evidence

Fresh round-2 planning validation on the pinned planning base produced:

- Spec Kit prerequisites with required Tasks: PASS; all required Plan artifacts
  were discovered.
- `scripts/context/audit`: PASS with zero findings.
- `scripts/hooks/check-tasks-fresh`: PASS; T001 is the sole native task row and
  remains single-layer.
- Placeholder scan and `git diff --check`: PASS.
- `.specify/feature.json` and the `AGENTS.md` managed marker both select Spec
  007. The repository agent-context extension was invoked with this plan but
  skipped because no installed Python exposes PyYAML; the managed marker was
  byte-checked directly and no dependency was installed.
- The complete RepoInfra suite was not duplicated in round 2 because repository
  policy leaves test execution to hooks. Its most recent exact-base evidence
  remains FAIL on pre-existing review-machinery runtime compatibility: the
  workspace `/usr/bin/python3` is Python 3.9, while
  `scripts/ci/review-raven.py` imports Python 3.11's `tomllib`. That evidence
  contains two direct review-machinery failures plus one cascading hook-wrapper
  failure; none cites a planning artifact or this feature's implementation
  scope.

The failing source/tests are explicitly prohibited review-machinery paths owned
by the separate repair sequence. This plan does not waive, suppress, or repair
the gate. Fullstack must rerun the complete RepoInfra gate on the refreshed
delivery base and obtain green evidence before publication; if the dependency
does not make that possible, return the exact failure to Team Lead.

## Open risks and routing

- GitHub payload/API shape drift or ambiguous exact-commit PR association:
  fail closed and return to Fullstack; do not infer label state.
- Missing/invalid marker metadata: fallback applies only to a genuine
  lightweight public marker; every invalid annotated marker or journal state
  fails preflight and unsafe commit ancestry blocks.
- A durable confirmation plus failed public-marker update is resolved by the
  specified marker-only reconciliation path. An attempted-only record is
  quarantined and never invokes Fastlane again; explicit ASC-backed
  reconciliation may confirm it, while clearing/retrying requires Owner
  authority.
- GitHub may replace pending concurrency members or deliver follower events out
  of order. Durable pre-concurrency admission plus exhaustive successful-run
  reconciliation preserves candidate intent; incomplete API pagination or
  activation-boundary proof fails closed.
- The existing Fastfile does not throw when a requested group is absent. The
  workflow-owned preflight existence and postflight exact-build membership
  checks are therefore mandatory; strict mode alone is insufficient.
- Separate review-machinery sequencing remains external to this source slice and
  is owned by Team Lead.
- The current planning-base RepoInfra failure is a concrete dependency, not an
  allowed baseline exception. It blocks publication until a refreshed base
  supplies a passing resolver-selected gate.

## Complexity tracking

No constitutional violation or justified exception.
