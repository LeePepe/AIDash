# Implementation Plan: CI-Gated TestFlight Release

**Branch**: `007-release-workflow` | **Date**: 2026-10-15 | **Spec**: `spec.md`

**Input**: Feature specification from `specs/007-release-workflow/spec.md`

## Summary

Replace AIDash's manual-only TestFlight trigger with a serialized,
`workflow_run`-driven release that checks out the exact successful `build`
workflow head, filters app-relevant changes, preserves a safe manual dispatch,
and fails closed on duplicate, stale, ambiguous, signing, upload, distribution,
or marker failures. Keep the existing Fastlane lane, ASC build-number counter,
secrets, and runner unchanged. Implement the behavior in one RepoInfra slice:
the workflow, its contract tests, and its operating guide.

## Technical context

**Language/Version**: GitHub Actions YAML; POSIX/Bash on macOS; Python 3.11+
`unittest`/`pytest` contract tests

**Primary Dependencies**: GitHub Actions `workflow_run` and `workflow_dispatch`
payloads; `actions/checkout@v4`; repository Git history/tags; GitHub REST API via
the existing `GITHUB_TOKEN`; existing Fastlane `ios beta` lane

**Storage**: Git tag `testflight/last-released` as the durable commit and
effective-marketing-version marker; App Store Connect as the existing global
build-number counter

**Testing**: Resolver-selected RepoInfra pytest gate and repository hooks; no
app tests, host-based tests, manual upload, or `xcodebuild` during implementation

**Target Platform**: GitHub Actions control plane plus the existing
`[self-hosted, aidash-mac]` runner

**Project Type**: Repository release automation

**Performance Goals**: Ineligible events stop before tooling installation,
secret access, signing, archive, or upload; eligible events remain serialized

**Constraints**: Exact CI head; fail closed; no new secret; no tracked identity;
no automatic retry/rollback; no branch/ruleset/review-gate change; Owner approval
required for `.github/**`

**Scale/Scope**: One workflow, one renamed/replacement contract test, one
operating guide; one implementation PR serving one goal

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
build workflow completed on main ─┐
                                  ├─> select immutable candidate SHA
manual workflow_dispatch ─────────┘
        │
        v
fetch candidate + release marker
        │
        ├─ duplicate / non-ancestor / invalid ─> fail or skip + summary
        └─ safe range
             │
             ├─ no app path and not manual force ─> skip + summary
             └─ eligible
                  │
                  ├─ resolve exact merged-PR label and effective version
                  ├─ ephemeral version override in isolated checkout
                  ├─ existing strict Fastlane lane + global ASC build counter
                  └─ success: annotated marker + success summary
```

Automatic and manual events share the same eligibility function and concurrency
group. Only event-to-candidate selection differs. Marker equality is an absolute
no-upload rule. Ancestry prevents delayed events from moving the marker backward.

## Version and marker design

- Project version: parse the tracked `MARKETING_VERSION` from `project.yml`.
- Marker version: parse a single validated `marketing-version=<semver>` field
  from the annotated `testflight/last-released` tag. A lightweight or malformed
  legacy marker contributes no version and falls back to the project version.
- Effective baseline: the semantically greater of project and marker versions.
- `release:minor`: only a proven exact merged PR for the candidate can set it;
  increment `major.minor`, resetting patch to zero. No PR/direct push means no
  bump. API or contradictory-association failure stops before upload.
- Build input: modify only the isolated checkout used by the runner so XcodeGen
  sees the effective version. Never commit or push this transformation.
- Success marker: force-replace the existing tag ref only after strict Fastlane
  success, pointing to the candidate and carrying the effective version.

The workflow captures Fastlane's existing selected-build message for the final
summary. Absence or ambiguity of that value after a nominally successful lane is
an invalid success and prevents marker movement.

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

- Retain `contents: write` for the moving tag.
- Add only the least permission needed to resolve an exact commit's associated
  merged PR and labels. Repository contents and PR metadata are read-only.
- Set `TESTFLIGHT_STRICT_UPLOAD=1` so internal distribution failure is fatal.
- Emit an outcome summary on `always()` without exposing secret or identity
  values. No failure starts an automatic rerun or rollback.

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
| AC-09 | Replacement tests + RepoInfra gate | T001 |
| AC-10 | Exact diff scope | T001 |
| AC-11 | Owner approval + delivery dependency | Team Lead / PR Manager gate |
| AC-12 | Post-merge run URL + build number | Team Lead / PR Manager evidence |

## Verification strategy

- Activate repository hooks in the delivery workspace.
- Let the staged commit/push flow run the resolver-selected RepoInfra gates.
- Required focused command if invoked through the resolver/hook:
  `/usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q`.
- Confirm `scripts/context/resolve` maps each changed path to `RepoInfra` and
  `scripts/context/audit` remains clean through repository gates.
- Run `git diff --check` and validate the exact four-path add/delete/modify set.
- Do not run `xcodebuild`, app tests, a real upload, or duplicate test suites
  manually during implementation.
- Before publication, freeze the local candidate and obtain AI Reviewer PASS on
  that exact content. Any content change invalidates review.

## Planning validation evidence

Fresh validation on the pinned planning base produced:

- Spec Kit prerequisites with required Tasks: PASS; all required Plan artifacts
  were discovered.
- `scripts/context/audit`: PASS with zero findings.
- `scripts/hooks/check-tasks-fresh`: PASS after the task metadata was adjusted
  to the repository parser's native format.
- Placeholder scan and `git diff --check`: PASS.
- Resolver-selected RepoInfra local gate: FAIL on pre-existing review-machinery
  runtime compatibility. The workspace `/usr/bin/python3` is Python 3.9, while
  `scripts/ci/review-raven.py` imports Python 3.11's `tomllib`. This causes two
  direct failures (`test_review_raven` contract and Codex timeout fixture) plus
  one cascading wrapper failure in the hook regression. No failure cites a new
  planning artifact or this feature's implementation scope.

The failing source/tests are explicitly prohibited review-machinery paths owned
by the separate repair sequence. This plan does not waive, suppress, or repair
the gate. Fullstack must rerun the complete RepoInfra gate on the refreshed
delivery base and obtain green evidence before publication; if the dependency
does not make that possible, return the exact failure to Team Lead.

## Open risks and routing

- GitHub payload/API shape drift or ambiguous exact-commit PR association:
  fail closed and return to Fullstack; do not infer label state.
- Missing/invalid marker metadata: fall back only as explicitly defined; unsafe
  commit ancestry blocks.
- Upload succeeds but marker push fails: run is failed and requires diagnosis;
  no automatic retry. Same-SHA re-upload remains prohibited, so repair may need
  an Owner decision if remote systems disagree with the marker.
- Separate review-machinery sequencing remains external to this source slice and
  is owned by Team Lead.
- The current planning-base RepoInfra failure is a concrete dependency, not an
  allowed baseline exception. It blocks publication until a refreshed base
  supplies a passing resolver-selected gate.

## Complexity tracking

No constitutional violation or justified exception.
