# Implementation Plan: CI-Gated TestFlight Release

**Branch**: `007-release-workflow` | **Date**: 2026-10-15 | **Spec**: `spec.md`

**Input**: Feature specification from `specs/007-release-workflow/spec.md`

## Summary

Replace AIDash's manual-only TestFlight trigger with a trusted
`workflow_run`-driven release. Prove same-repository protected-`main` push
provenance on a hosted read-only worker before candidate checkout, self-hosted
capacity, or release secrets. Serialize automatic and manual release work in
one AIDash concurrency group and use only the existing
`testflight/last-released` marker: an existing marker compares
`marker..candidate`, so irrelevant skips and failures accumulate naturally
until a later candidate is eligible. Preserve missing-marker first-parent
bootstrap, exact-head safety, the existing Fastlane lane, ASC build-number
counter, signing, secrets, and runner. Add workflow-owned group-existence and
selected-build membership proof before advancing the marker. Implement the
behavior in one RepoInfra issue/PR covering the workflow, replacement contract
tests, and operating guide.

## Technical context

**Language/Version**: GitHub Actions YAML; POSIX/Bash on hosted Linux and macOS;
replacement `unittest`/`pytest` contract tests compatible with the RepoInfra
gate's `/usr/bin/python3` (Python 3.9 on the planning base; no Python 3.10+
syntax or Python 3.11-only standard-library dependency)

**Primary Dependencies**: GitHub Actions `workflow_run` and
`workflow_dispatch`; `actions/checkout@v4`; Git history/tags; GitHub REST API
via the existing `GITHUB_TOKEN`; existing Fastlane `ios beta` lane

**Storage**: Only the existing annotated or legacy-lightweight
`testflight/last-released` marker; App Store Connect remains the global
build-number allocator and external distribution authority

**Testing**: Resolver-selected RepoInfra pytest gate and repository hooks; no
app tests, host-based tests, manual upload, or `xcodebuild` during implementation

**Target Platform**: GitHub Actions control plane plus the existing
`[self-hosted, aidash-mac]` runner

**Project Type**: Repository release automation

**Performance Goals**: Untrusted events stop before candidate checkout,
self-hosted capacity, secret access, signing, archive, or upload; trusted
release work remains serialized

**Constraints**: Exact CI head; fail closed; no new durable state, secret, or
tracked identity; no automatic retry/rollback; no branch/ruleset/review-gate
change; Owner approval required for `.github/**`

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
- No tracked `CODEOWNERS` exists. The Owner decision directly requires Owner
  approval of the protected-path PR.

## Constitution check

### Before design

- **Scope discipline**: PASS. The slice declares exact paths and prohibitions.
- **Dependency direction**: PASS. All implementation paths resolve to one
  dependency-free RepoInfra layer.
- **Testing**: PASS. Obsolete manual-only assertions are replaced by deeper
  contract coverage; no test is silently deleted or weakened.
- **Identity hygiene**: PASS. No account, team, workspace, or credential value
  is added to tracked files.
- **Local safety**: PASS. Verification is hook/resolver-driven; no host-based
  app test or proactive Xcode suite is planned.
- **User-feedback policy**: PASS. Post-merge evidence is recorded on the
  delivery issue, not delegated to a manual smoke-test issue.

### After design

- The marker/version model adds no product schema, dependency, or durable state.
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
├── checklists/
│   └── requirements.md
└── tasks.md
```

The reviewed planning package also includes `.specify/feature.json` and only
the `<!-- SPECKIT START/END -->` marker block in `AGENTS.md`. Those routing
authorities select this feature together and remain frozen with the feature
artifacts during implementation.

### Owned implementation paths

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py   # removed/renamed
scripts/ci/tests/test_testflight_release.py       # replacement
docs/testflight-handoff.md
```

**Structure decision**: Keep provenance, release selection, version derivation,
ephemeral marketing-version injection, Fastlane invocation, summaries, group
proof, and marker update inside the existing workflow. Replace the obsolete
manual-only test with a release-policy contract test and update the existing
operating guide. The existing Fastlane lane remains unchanged.

## Architecture and data flow

```text
build workflow completed ─┐
                          ├─> hosted read-only provenance + official main fetch
manual workflow_dispatch ─┘        (no candidate execution or release secrets)
                                      │ exact pinned candidate
                                      v
                 serialized self-hosted worker (`testflight`, no cancellation)
                                      │
                     refetch marker + revalidate candidate
                                      │
          equal ─> skip | descendant marker ─> stale skip | unrelated ─> fail
                                      │
             marker..candidate (or missing-marker first-parent delta)
                                      │
                    irrelevant and no force ─> skip, marker unchanged
                                      │
               version, ASC group, and signing-secret preflight
                                      │
               existing Fastlane lane + global ASC build counter
                                      │
                    exact-build/all-group membership proof
                                      │
                  compare-and-swap last-released marker
```

Automatic and manual events share the same serialized release state machine.
Only event-to-candidate proof and the manual `force` relevance override differ.
The hosted provenance job never executes candidate content or receives release
secrets. The self-hosted worker performs metadata-only fetches and all
eligibility checks before candidate checkout or step-level secret exposure.

## Trusted provenance and serialization design

- Automatic provenance requires workflow path `.github/workflows/build.yml`,
  name `build`, source event `push`, completed/success, head branch `main`, same
  head repository as `github.repository`, and a 40-hex head SHA.
- A hosted read-only job initializes a metadata-only Git repository, fetches
  official protected `main`, and proves the candidate is reachable. It does not
  use `actions/checkout`, execute repository code, request contents write, enter
  the self-hosted runner, or reference ASC/keychain secrets.
- Manual provenance resolves official protected `main` once in the same hosted
  stage and passes that immutable SHA to the release worker. `force` changes
  only path relevance.
- All trusted automatic and manual release workers use the single AIDash group
  `testflight` with `cancel-in-progress: false`. Under the lock, the worker
  refetches protected `main` and the public marker, revalidates candidate
  reachability and marker relationship, then computes eligibility.
- GitHub can retain only one pending group member and may replace an older
  pending run. This design intentionally does not preserve every intermediate
  head. With an existing ancestor marker, a later descendant evaluates the
  full `marker..candidate` range, so skipped/replaced relevant changes are
  carried into the later candidate. With no marker, the later candidate uses
  only its own first-parent/root delta, so a replaced relevant head is not
  implicitly carried forward. The workflow makes no per-head exactly-once or
  survivor-summary promise.
- The workflow creates no queue-start, queue/cursor/skip, attempt, confirmation,
  quarantine, or recovery ref. `testflight/last-released` is the only durable
  release-progress record.

## Marker, version, and failure design

- Existing marker: strictly parse and dereference `testflight/last-released`.
  Equality is an absolute skip. Ancestor permits `marker..candidate`.
  Descendant means stale candidate and skips without rewind. Unrelated history
  fails closed.
- Missing marker: compare the candidate's first-parent delta, or the empty tree
  to a root candidate. A workflow-only enabling merge skips; the first later
  app-relevant candidate can bootstrap. Manual `force=true` may bootstrap.
- Project version: parse tracked `MARKETING_VERSION` from `project.yml`.
- Marker version: parse exactly one valid `marketing-version=<semver>` field
  from an annotated marker. Only a genuine lightweight marker has no version
  metadata and falls back to the project version. Invalid annotated metadata
  fails preflight.
- Effective baseline: the semantically greater project/marker version.
  `release:minor` applies only for a proven exact merged PR associated with the
  candidate; direct push/proven no-PR means no bump, while API ambiguity fails.
- Build input: modify only the isolated release checkout so XcodeGen sees the
  effective version. Never commit or push that transformation.
- Success: after the lane succeeds, exactly one selected build number is
  parsed, and ASC independently proves membership in every intended group.
  Then replace the annotated marker only with compare-and-swap against the
  fetched prior tag-object ID. Its metadata contains exactly schema, effective
  marketing version, and build number.
- Failure: preflight, lane, proof, or marker compare-and-swap failure leaves the
  marker unchanged. There is no automatic retry, rollback, journal,
  reconciliation, or quarantine. A later eligible merge or manual run starts a
  new evaluation. If an external upload succeeded before marker failure, a
  later run may upload again because the authorized model records no attempt;
  the plan claims only same-recorded-SHA protection, not exactly-once upload.

## Path eligibility contract

The allowlist is exactly:

```text
Apps/AIDashApp/**
Packages/AIDashCore/**
Packages/AIDashUI/**
Packages/DesignKit/**
Configs/**
project.yml
fastlane/**
```

With an existing marker, compare `marker..candidate`. Several irrelevant merges
therefore keep accumulating while the marker stays fixed. With no marker,
compare only candidate first-parent delta, or empty-tree delta for a root.
Manual `force=true` bypasses only the allowlist result.

## Permissions, distribution, and summaries

- Hosted provenance has read-only contents/actions permission and runs before
  any write token, self-hosted capacity, candidate checkout, or secret reference.
- The serialized release worker has read-only actions/PR metadata and
  `contents: write` only for the public-marker compare-and-swap. Existing ASC
  readback credentials are first referenced, step-scoped, for group existence
  only after candidate/marker/path/version preflight; signing/keychain material
  remains step-scoped to the subsequent release path.
- Normalize the lane's existing `TESTFLIGHT_GROUPS` contract (default
  `Internal`; comma split/trim; reject empty or duplicate names). Prove each
  group exists before Fastlane. Set `TESTFLIGHT_STRICT_UPLOAD=1`, invoke the
  lane once in that run, parse exactly one selected build number, then prove
  that exact build belongs to every intended group before marker movement.
- Every run reaching eligibility evaluation summarizes its own candidate,
  marker state, outcome, and reason. Success also includes effective version,
  build number, and run URL. No run fabricates a result for a replaced pending
  run or exposes secrets/identity values.

## Focused contract scenarios

- Existing marker plus several irrelevant automatic merges: every executed run
  skips; marker stays fixed; the accumulated range remains available to a later
  descendant.
- Irrelevant automatic run then manual `force=true`: manual pins current main
  and may release despite relevance.
- Same-candidate automatic/manual: serialized; an automatic skip permits later
  force, while the first successful marker advance makes the other skip.
- Failed eligible release with an existing ancestor marker: marker remains
  fixed; a later descendant includes the failed relevant change and may release
  its newer exact head.
- Failed/replaced eligible candidate with no marker: a later docs-only candidate
  still skips because it evaluates only its own first-parent delta; pickup
  requires an independently app-relevant bootstrap candidate or manual force.
- Missing-marker workflow-only enabling merge: skip; the first later
  app-relevant candidate bootstraps from its first-parent delta.
- Marker equality, ancestor, descendant/stale, and unrelated-history behavior.
- Group absence before lane, selected-build membership absence after lane, and
  marker compare-and-swap failure all fail without marker movement.
- No queue/journal/recovery inputs or refs and no exactly-once claim after an
  upload/marker split failure.

## Delivery sequencing

1. This planning package may be reviewed at the pinned planning base.
2. After exact-revision spec-gate PASS, Team Lead may dispatch one Fullstack
   Engineer. Under the scoped workspace protocol, Fullstack owns the first new
   issue-scoped delivery checkout and metadata registration.
3. Fullstack creates one implementation PR and may prepare it before the
   separate review-machinery dependency completes.
4. Merge/ship is blocked until Team Lead records the MY-1692 repair landing and
   a fresh eligible parked-PR proof on the repaired base with a real terminal
   `pass` or `changes` verdict. Pre-landing reruns, setup failures, and invalid
   verdicts do not satisfy the dependency.
5. Any base refresh creates a new exact head and requires renewed implementation
   review, checks, and Owner approval before shipping.
6. After merge, record the next eligible release run URL and build number on the
   delivery issue. Do not create a manual smoke-test issue.

This dependency is a delivery-order constraint, not a source-code dependency;
MY-1692's review-machinery paths remain prohibited from this diff.

## Acceptance traceability

| Acceptance | Requirement coverage | Task |
|---|---|---|
| AC-01 | FR-001–FR-002 | T001 |
| AC-02 | FR-003–FR-005 | T001 |
| AC-03 | FR-006 | T001 |
| AC-04 | FR-007 | T001 |
| AC-05 | FR-008 | T001 |
| AC-06 | FR-009–FR-010 | T001 |
| AC-07 | FR-011–FR-012 | T001 |
| AC-08 | FR-013–FR-014 | T001 |
| AC-09 | FR-015 + replacement tests + RepoInfra gate | T001 |
| AC-10 | Exact diff scope | T001 |
| AC-11 | Owner approval + MY-1692 delivery dependency | Team Lead / PR Manager gate |
| AC-12 | Post-merge run URL + build number | Team Lead / PR Manager evidence |

## Verification strategy

- Activate repository hooks in the delivery workspace and let staged
  commit/push flow run resolver-selected RepoInfra gates.
- Required resolver/hook gate:
  `/usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q`.
- Keep the replacement test Python 3.9-compatible under that interpreter unless
  an approved refreshed base first changes the gate.
- Confirm context resolution maps each implementation path to `RepoInfra` and
  `scripts/context/audit` is clean.
- Contract fixtures cover provenance rejection before privileges; exact
  candidates; missing/equal/ancestor/descendant/unrelated markers; existing-
  marker accumulated irrelevant ranges; mixed automatic/manual force; pending
  replacement without per-head guarantees; existing-marker failure/replacement
  pickup; absent-marker first-parent non-carry-forward and bootstrap; strict
  metadata; version behavior; group existence; exact-build membership;
  unchanged marker on failure; and absence of queue/journal/recovery state.
- Run `git diff --check` and validate the exact four-path implementation
  add/delete/modify set.
- Do not run `xcodebuild`, app tests, a real upload, or duplicate hook-owned test
  suites manually during implementation.
- Before publication, freeze the local candidate and obtain AI Reviewer PASS on
  that exact content. Any content change invalidates review.

## Planning validation requirements

Before publishing this exact planning revision, run Spec Kit prerequisites with
required tasks, `scripts/context/audit`, `scripts/hooks/check-tasks-fresh`, a
placeholder scan, pointer synchronization checks, and `git diff --check`.
Capture the exact local/remote planning SHA, clean tree, changed-path manifest,
and blob IDs for the final AI Reviewer gate.

The planning-base RepoInfra implementation gate remains known-failing because
`/usr/bin/python3` is 3.9 while the separately owned review launcher imports
Python 3.11's `tomllib`. This feature neither waives nor repairs that failure.
Fullstack must obtain a fresh green complete RepoInfra gate on the Team
Lead-approved refreshed delivery base; otherwise return the exact blocker.

## Open risks and routing

- GitHub payload/API drift or ambiguous exact-candidate PR association fails
  closed; do not infer provenance or label state.
- Missing/invalid marker metadata falls back only for a genuine lightweight
  public marker; invalid annotated state or unsafe ancestry fails closed.
- GitHub may replace a pending group member. The accepted model accumulates
  relevance in the unchanged marker range and deliberately does not promise
  release of every intermediate head.
- Upload success and marker movement are not atomic. Without an attempt journal,
  a later run may repeat an externally successful but unrecorded upload. This is
  the explicit Owner-authorized tradeoff; do not invent recovery state.
- The existing Fastfile does not throw when a requested group is absent.
  Workflow-owned preflight existence and postflight exact-build membership are
  mandatory; strict mode alone is insufficient.
- MY-1692 sequencing remains external to this source slice and Team Lead-owned.
- The planning-base RepoInfra failure is a dependency, not an allowed baseline
  exception; publication requires a passing refreshed-base gate.

## Complexity tracking

No constitutional violation or justified exception.
