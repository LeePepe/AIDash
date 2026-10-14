# Implementation Plan: Minimal CI-Gated TestFlight Release

**Branch**: `007-release-workflow` | **Date**: 2026-10-15 | **Spec**: `spec.md`

## Summary

Replace the manual-only trigger with a single serialized self-hosted release
job. A successful same-repository `build` push on `main` checks out exactly the
source `head_sha` with full history. The job compares the public release marker
to that head, runs a small production relevance classifier, skips irrelevant
ranges with one summary line, otherwise invokes the existing Fastlane lane,
then moves the marker. Manual dispatch and its existing `force` escape remain.
Signing secrets exist only on the build/upload step. A final `always()` step
restores keychain state and removes run-scoped temporary keychain/local-tag
artifacts. No separate provenance/CAS job, release journal, recovery model, or
workflow-policy shadow suite remains.

## Technical context

**Language/Version**: GitHub Actions YAML; Bash on macOS; Python 3.9-compatible
classifier/tests

**Dependencies**: `actions/checkout@v4`, Git, repository Python, existing
`fastlane ios beta`; actionlint is a verification tool only

**Storage**: Existing moving tag `testflight/last-released` only

**Testing**: Focused classifier unit tests; actionlint workflow lint; normal
hook-selected RepoInfra gate; no Xcode tests or real upload

**Target**: Existing `[self-hosted, aidash-mac]` runner

**Constraints**: Exact automatic head; one job/group; plain job-level
`contents: write`; fail closed; no retry; secrets only on build/upload; cleanup
always; four final diff paths or fewer; Owner approval for `.github/**`

## Repository authority and base

- Repository: `https://github.com/LeePepe/AIDash`
- Planning base: `efc5760d496a92934fba096ef54e48fb4d1fe86e`
- Authority: `AGENTS.md` → constitution → `CONTEXT.md` →
  `scripts/CONTEXT.md`; no shared-ci pin exists.
- All planning and implementation paths resolve to dependency-free
  `RepoInfra`.
- `OD-2026-10-15-B` is the removal authority for the superseded planning and
  unpublished shadow-policy candidate.

## Constitution check

### Before design

- **Scope**: PASS. One RepoInfra task declares four final diff paths.
- **Testing**: PASS. The obsolete manual-only test is replaced by unit tests for
  the production classifier; the unaccepted shadow suite is explicitly removed.
- **Identity**: PASS. No tracked identity, credential, or secret is added.
- **Local safety**: PASS. Verification uses hooks, Python, and workflow lint;
  no host-based app test or upload is planned.
- **Delivery**: PASS. Protected-path approval and MY-1692 remain external gates.

### After design

- The design has one job, one layer, one marker, and no added dependency or
  durable state.
- The accepted simplification removes rather than relocates the prior policy
  machinery.
- No constitutional exception is required.

## Project structure

### Planning artifacts

```text
specs/007-release-workflow/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/release-workflow.md
├── checklists/requirements.md
└── tasks.md
```

`.specify/feature.json` and the Spec Kit marker block in `AGENTS.md` already
select this feature and remain unchanged.

### Final implementation paths

```text
.github/workflows/testflight.yml
scripts/ci/tests/test_testflight_manual_only.py     # delete
scripts/ci/tests/test_testflight_relevance.py       # add classifier + units
docs/testflight-handoff.md
```

The unpublished `scripts/ci/tests/test_testflight_release.py` shadow suite must
not exist in the final tree or PR diff; the Owner identifies it as the 542-line
shadow-policy suite. If recovery begins from its preserved
local branch, Team Lead must first establish a non-descendant publication line;
Planner and Fullstack must not publish `e8c353ce` in history.

## Architecture and data flow

```text
successful same-repo build push on main ─┐
                                         ├─> one serialized self-hosted job
workflow_dispatch on current main ───────┘        │
                                                   ├─ exact/full-history checkout
                                                   ├─ fetch marker
                                                   ├─ diff marker..head
                                                   ├─ production classifier
                       irrelevant/no force ───────> summary + stop
                                                   ├─ build/upload step (all secrets)
                                                   ├─ move marker after lane success
                                                   └─ always cleanup temp keychain/tags
```

## Trigger, checkout, and serialization

- Register `workflow_run` for `build`, `completed`, `main`, plus
  `workflow_dispatch(force=false)`.
- The single release job accepts the automatic path only for conclusion
  `success`, event `push`, head branch `main`, and same head repository.
- Automatic checkout ref is exactly `workflow_run.head_sha`; manual checkout
  ref is `main`. Both use `fetch-depth: 0` and tag fetch.
- One job-level concurrency group `testflight` uses
  `cancel-in-progress: false`. It is serialization, not a durable queue.
- The job declares only ordinary `contents: write` permission. There is no
  hosted pre-job or token/CAS boundary.

## Marker and relevance

- Fetch/dereference `testflight/last-released` and compute exactly
  `git diff --name-only <marker>..<checked-out-head>`.
- Missing/invalid marker or diff failure fails closed on automatic and
  non-forced manual execution. Existing manual `force=true` may bootstrap or
  bypass an irrelevant/equal range; it creates no second state.
- The production classifier is
  `scripts/ci/tests/test_testflight_relevance.py`. It accepts newline-delimited
  paths and returns relevant/non-relevant. The workflow calls that exact code;
  pytest imports the same function. No YAML-policy mirror is permitted.
- Relevant roots are the seven families in FR-006. Matching is root-anchored;
  near misses such as `docs/Apps/AIDashApp/...` remain irrelevant.
- A non-forced irrelevant result appends one concise summary line and exits
  before any secret-bearing step.

## Build, permissions, marker, and cleanup

- Reuse the existing Xcode/tool checks and `fastlane ios beta` lane without
  changing Fastlane, build-number allocation, signing, groups, or project files.
- Put secret presence validation, run-scoped keychain preparation, login
  keychain unlock as needed, and the lane invocation in one build/upload step.
  Its environment is the only place containing the five secrets.
- After that step succeeds, move the plain remote marker to the checked-out
  commit using the checkout-provided job token. No annotated schema, lease, or
  separate permission job is added.
- A final `if: always()` step restores the prior user keychain search list and
  removes only the per-run temporary keychain and local temporary marker tag.
  It never removes or rewrites the remote marker. Cleanup requires no signing
  secret.
- Any command error fails the run. There is no automatic retry, rollback,
  alternate runner, or fallback credential path.

## Focused validation scenarios

- Each allowed path family is relevant; representative `.github`, docs, specs,
  scripts, CLI, and aidata paths are not.
- Mixed inputs are relevant, empty inputs are not, and root-prefix near misses
  do not match.
- Actionlint accepts trigger syntax, expressions, checkout inputs, job-level
  permissions, concurrency, step conditions, and `always()` cleanup.
- Reviewer inspection confirms exact automatic SHA checkout, summary-before-
  secrets ordering, all five secrets on one step only, upload-before-marker,
  marker unchanged on failure, and cleanup on skip/failure/success.

## Delivery sequencing

1. Publish this planning package and obtain exact-revision AI Reviewer PASS.
2. Team Lead resolves the preserved local-only `e8c353ce` lineage without
   deleting or publishing it, then dispatches one Fullstack Engineer with the
   reviewed planning revision and the approved implementation base.
3. Fullstack produces one local candidate in no more than the four declared
   final diff paths and explicitly records the discarded shadow suite in the PR
   body's Removed/weakened-tests section.
4. AI Reviewer performs the normal prepublication review. The normal two-round
   budget starts fresh for this re-scoped implementation; if round 2 still
   returns `NEEDS_WORK`, Team Lead parks it and reports to the Owner delegate,
   with no Owner escalation and no third round.
5. Publication requires protected-path Owner approval. Merge/ship remains
   blocked by the unchanged MY-1692 gate.

## Acceptance traceability

| Acceptance | Requirements | Task |
|---|---|---|
| AC-01 | FR-001–FR-002 | T001 |
| AC-02 | FR-003–FR-004 | T001 |
| AC-03 | FR-005–FR-007 | T001 |
| AC-04 | FR-008–FR-009 | T001 |
| AC-05 | FR-010–FR-011 | T001 |
| AC-06 | FR-011 | T001 |
| AC-07 | FR-012 | T001 |
| AC-08 | FR-012 + external gates | T001 / Team Lead / PR Manager |

## Verification strategy

- Activate `scripts/hooks` and let commit/push run the resolver-selected gates.
- Focused evidence before commit:
  `/usr/bin/python3 -m pytest scripts/ci/tests/test_testflight_relevance.py -q`.
- Workflow lint: install Homebrew `actionlint` if absent, record
  `actionlint -version`, then run
  `actionlint .github/workflows/testflight.yml`. Planning-time Homebrew reports
  stable `1.7.12`; any unavailable/failed lint is a blocker, not a waiver.
- Normal hook-selected RepoInfra evidence remains
  `/usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q`.
- Confirm resolver ownership, `scripts/context/audit`, task freshness,
  `git diff --check`, and exact final paths.
- Do not run Xcode tests, host-based tests, or a real upload.

## Planning validation

Run Spec Kit prerequisites with tasks, context audit, task freshness,
placeholder scan, pointer synchronization, read-only Analyze, and
`git diff --check`. Pin the exact revision, changed-path manifest, and blobs.

The planning base's unrelated Python 3.9/`tomllib` RepoInfra failure remains an
MY-1692 delivery dependency, not a waiver. The implementation candidate must
obtain a fresh green complete gate on the Team Lead-approved refreshed base.

## Risks and routing

- A missing marker blocks automatic release; manual force is the retained
  bootstrap escape. Do not add bootstrap state.
- Plain marker movement is deliberately not CAS. One concurrency group is the
  accepted boundary; do not reintroduce a permission/state machine.
- Actionlint is not currently installed. Fullstack installs the verification
  tool locally and records its version; failure to provision it blocks delivery.
- The preserved unpublished candidate requires Team Lead recovery before a new
  publication line. Planner does not mutate that checkout.
- MY-1692 and protected-path approval remain unchanged external gates.

## Complexity tracking

No constitutional violation or exception.
