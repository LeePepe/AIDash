---
description: "Layer-scoped implementation tasks for complete-predicate review evidence"
---

# Tasks: Complete-Predicate Evidence for Required Review

**Input**: Design documents from
`specs/006-codex-gate-false-positive/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`,
`contracts/review-evidence-discipline.md`, `quickstart.md`

**Organization**: One vertical outcome, realized by one independently
schedulable RepoInfra implementation task. PR #199 refresh remains a downstream
delivery dependency, not a hidden cross-layer Fullstack task.

## Phase 1: User Story 1 - Complete-Predicate Evidence (Priority: P1)

**Goal**: The required automated reviewer does not claim that an accepted value
is invalid from a partial hunk, while direct defects and tool failures remain
fail closed.

**Independent Test**: The real shared trusted prompt helper renders a
complete-predicate rule that correctly interprets the pinned
`VALID_TIERS | {"production"}` shape, and the live Codex gate continues to
consume that helper.

- [ ] T001 [US1] Extend the complete-predicate evidence contract in `scripts/ci/review-common.sh`, add the PR-shaped regression to `scripts/ci/tests/test_review_shell.py`, and document the invariant in `docs/ci-gates.md`.

### T001 Metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra`; context chain `CONTEXT.md` → `scripts/CONTEXT.md` |
| Files in scope | `scripts/ci/review-common.sh`; `scripts/ci/tests/test_review_shell.py`; `docs/ci-gates.md` |
| Files/layers out of scope | `.github/workflows/**`; `scripts/ci/codex-review.sh`; `scripts/rulesets/**`; all `aidata/**`; PR #198; PR #199; every Swift/App/CLI package |
| Interface impact | Extends the existing internal trusted prompt interface `review_evidence_rules()`; no public product or data contract change |
| Task-local acceptance | Invalid-value/test/CI-failure blockers require the complete deciding predicate; unions/defaults/normalization/negation are evaluated; a partial constant cannot prove rejection; the pinned `production` value is recognized as accepted by the full union; directly proven critical/high defects and all fail-closed tool paths remain intact; both live gate consumption and single-source wording are regression-pinned |
| Exact verification | Normal hooks invoke `scripts/context/run RepoInfra --mode local`; implementation handoff records its exit 0. CI later invokes the RepoInfra CI gate and ruff. Do not manually add App, Swift, or Aidata suites. |
| Blocking edges | Reviewed exact planning revision; no implementation task dependency |
| Vertical slice | US1 |

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
| SC-001–SC-004 | US1 | T001 | RepoInfra local/CI gates and diff inspection |
| SC-005 | Downstream MY-1495 shipping | T001 must reach main first | Refreshed PR #199 required checks and fresh same-HEAD AI Reviewer PASS |

## Dependency Graph

```text
reviewed planning revision
  -> T001 RepoInfra repair
  -> repair PR exact-SHA PASS + required checks green
  -> repair merged to main
  -> Team Lead refreshes PR #199 from repaired main
  -> PR #199 required checks green + fresh same-HEAD AI Reviewer PASS
  -> PR Manager merges PR #199 / MY-1495 reaches main
  -> Team Lead may promote MY-1496
```

There are no parallel implementation opportunities inside this feature: the
three files form one prompt-contract change and must land atomically.
