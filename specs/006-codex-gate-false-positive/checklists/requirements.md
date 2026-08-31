# Requirements Checklist: Complete-Predicate Evidence for Required Review

**Purpose**: Validate specification and planning readiness before independent
review.

**Created**: 2026-08-31

**Feature**: `specs/006-codex-gate-false-positive/spec.md`

## Outcome and authority

- [x] CHK001 Owner decision B is explicit: fail closed and no admin bypass.
- [x] CHK002 The repeated PR #199 false blocker and contradicting full predicate
  are recorded.
- [x] CHK003 PR #198 preservation, MY-1495 allowlist, and MY-1496 dependency are
  explicit.

## Scope and architecture

- [x] CHK004 The implementation is one RepoInfra layer task.
- [x] CHK005 Every implementation file and high-risk exclusion is named.
- [x] CHK006 Trusted-base, untrusted-data fence, severity threshold, required
  status, and tool-error behavior are preserved.
- [x] CHK007 No new analyzer, workflow, ruleset, dependency, schema, or product
  behavior is introduced.

## Acceptance and traceability

- [x] CHK008 Every functional requirement maps to US1/T001 or an explicit
  downstream delivery dependency.
- [x] CHK009 The PR-shaped incomplete-hunk abstention regression is
  deterministic and tied to the real shared prompt helper without claiming a
  deterministic model verdict.
- [x] CHK010 Direct blockers and fail-closed failures remain covered.
- [x] CHK011 The exact RepoInfra local verification command is declared through
  the repository hook contract.
- [x] CHK012 PR #199 refresh, same-HEAD checks/review, and MY-1496 promotion order
  are acyclic and explicit.
- [x] CHK013 B000 requires a successful `review-gate (pytest)` check on T001's
  exact base before dispatch and refreshes evidence if `main` advances.
- [x] CHK014 T001 names the two observed timeout failures and the Homebrew-Bash
  task-freshness hang as stop-and-return red lines outside its scope.

## Readiness

- [x] CHK015 No unresolved clarification marker remains.
- [x] CHK016 No product, content, or authority decision remains open.
- [x] CHK017 Spec, plan, research, contract, quickstart, tasks, and data-model
  statement agree on scope and terminology.
