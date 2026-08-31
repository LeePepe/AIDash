---
description: "Layer-scoped implementation tasks for complete-predicate review evidence"
---

# Tasks: Complete-Predicate Evidence for Required Review

**Input**: Design documents from
`specs/006-codex-gate-false-positive/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`,
`contracts/review-evidence-discipline.md`, `quickstart.md`

**Organization**: One vertical outcome, realized by one RepoInfra
implementation task after the Team Lead-owned B000 exact-base readiness gate.
PR #199 refresh remains a downstream delivery dependency, not a hidden
cross-layer Fullstack task.

## Pre-Dispatch Gate B000 - Exact-Base RepoInfra Baseline

B000 is a scheduling prerequisite, not an implementation checkbox. Team Lead
pins T001's proposed `delivery_base_sha` and verifies a successful GitHub
`review-gate (pytest)` check on that exact commit before dispatch.

- Current evidence applies only to
  `40a920526ebf69c07dfa85a109ad2c585c5cb70a`: Actions run `33342454411`, job
  `99340425368` completed `scripts/context/run RepoInfra --mode ci` successfully.
- If `main` advances, Team Lead must re-establish B000 on the replacement exact
  SHA.
- Missing/failing evidence keeps T001 blocked and requires a separately planned
  RepoInfra prerequisite; it does not expand T001.

## Phase 1: User Story 1 - Complete-Predicate Evidence (Priority: P1)

**Goal**: The required automated reviewer does not claim that an accepted value
is invalid from a partial hunk, while direct defects and tool failures remain
fail closed.

**Independent Test**: The real shared trusted prompt helper renders an
abstention rule for a hunk that shows only `VALID_TIERS = {"explore"}` without
the complete `VALID_TIERS | {"production"}` predicate, and the live Codex gate
continues to consume that helper. This pins deterministic prompt policy, not a
model verdict.

- [ ] **T001 [US1]** Extend the complete-predicate evidence contract in `scripts/ci/review-common.sh`, add the PR-shaped regression to `scripts/ci/tests/test_review_shell.py`, and document the invariant in `docs/ci-gates.md`.

### T001 Metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra`; context chain `CONTEXT.md` → `scripts/CONTEXT.md` |
| Files in scope | `scripts/ci/review-common.sh` only within `review_evidence_rules()` and its adjacent explanation; `scripts/ci/tests/test_review_shell.py` only for the new prompt-contract regression; `docs/ci-gates.md` only for the complete-predicate incident/invariant |
| Files/layers out of scope | `.github/workflows/**`; `scripts/ci/codex-review.sh`; `scripts/rulesets/**`; `scripts/hooks/check-tasks-fresh`; all `aidata/**`; PR #198; PR #199; every Swift/App/CLI package; `run_with_timeout` and every existing timeout/process-group test even though they share two in-scope files |
| Interface impact | Extends the existing internal trusted prompt interface `review_evidence_rules()`; no public product or data contract change |
| Task-local acceptance | A blocker claiming a value is invalid/rejected requires the complete deciding predicate; unions/defaults/normalization/negation are evaluated; a partial constant cannot prove rejection; the regression pins abstention for the incomplete PR #199 hunk and shared-helper consumption, not a model verdict; directly proven critical/high defects, direct test/CI failure output, and all fail-closed tool paths remain intact |
| Exact verification | After B000, normal hooks invoke `scripts/context/run RepoInfra --mode local`; implementation handoff records its exit 0. CI later invokes the RepoInfra CI gate and ruff. Do not manually add App, Swift, or Aidata suites. If a named baseline failure recurs, this acceptance is not met and T001 returns blocked. |
| Blocking edges | Reviewed exact planning revision; B000 exact-base green baseline |
| Vertical slice | US1 |

**T001 red line**: If
`test_run_with_timeout_kills_nested_wrapper_descendants`,
`test_run_with_timeout_kills_the_whole_process_group`, or the Homebrew-Bash
`check-tasks-fresh` hang occurs, Fullstack MUST stop, make no timeout or
task-freshness repair, and return the evidence to Team Lead for a separately
planned RepoInfra prerequisite. Re-running until green or editing those paths
inside T001 is prohibited.

**Quality bars**: Constitution §Cross-Cutting Quality Bars and §Development
Workflow apply automatically.

## Acceptance Traceability

| Requirement / scenario | Slice | Task | Verification surface |
|---|---|---|---|
| FR-001–FR-004; scenarios 1–2 | US1 | T001 | Shared-helper text and PR-shaped regression |
| FR-005; scenarios 3–4 | US1 | T001 | Existing direct-blocker and fail-closed regression suite remains green |
| FR-006–FR-007 | US1 | T001 | Shared-helper consumption and no-inline-copy assertions |
| FR-008–FR-009 | US1 | T001 | Three-file diff allowlist plus exact-SHA review |
| FR-010–FR-011 | Downstream delivery dependency | T001 blocks refresh | Quickstart sequence and Team Lead scheduling gate |
| FR-012 | Pre-dispatch readiness | B000 | Same-SHA `review-gate (pytest)` success |
| FR-013 | Scope containment | T001 red line | Immediate blocked return on named recurrence; no out-of-scope edit |
| SC-001 | US1 | T001 | Shared-helper prompt regression |
| SC-002 | Pre-dispatch readiness | B000 | Exact-base GitHub check evidence |
| SC-003–SC-005 | US1 | T001 | RepoInfra local/CI gates, named-failure red line, and diff inspection |
| SC-006 | Downstream MY-1495 shipping | T001 must reach main first | Refreshed PR #199 all checks green and fresh same-HEAD AI Reviewer PASS |

## Dependency Graph

```text
reviewed planning revision
  -> B000 exact-base review-gate green
  -> T001 RepoInfra repair
       -> named baseline failure recurs: STOP -> Team Lead -> separate prerequisite
  -> repair PR exact-SHA PASS + all checks green
  -> repair merged to main
  -> Team Lead refreshes PR #199 from repaired main
  -> PR #199 all checks green + fresh same-HEAD AI Reviewer PASS
  -> PR Manager merges PR #199 / MY-1495 reaches main
  -> Team Lead may promote MY-1496
```

There are no parallel implementation opportunities inside this feature: the
three files form one prompt-contract change and must land atomically.
