# Specification Quality Checklist: CI-Gated TestFlight Release

**Purpose**: Verify Specify-stage completeness before independent planning review.
**Created**: 2026-10-15
**Feature**: `specs/007-release-workflow/spec.md`

## Content quality

- [x] Owner outcome, actors, and operational value precede implementation detail.
- [x] All user stories are prioritized and independently testable with fixtures.
- [x] Success criteria describe observable release outcomes.
- [x] No unresolved clarification marker or placeholder remains.

## Requirement completeness

- [x] Existing behavior, compatibility, and removed behavior are explicit.
- [x] Every removal is bound to the dated Owner decision.
- [x] FR-001–FR-014 use mandatory, testable language.
- [x] AC-01–AC-12 provide stable review identifiers.
- [x] Automatic and manual entrypoints select immutable candidates.
- [x] Missing, duplicate, stale, non-ancestor, and out-of-order marker states are defined.
- [x] App-relevant and non-relevant path families are exact.
- [x] Manual force bypasses only path relevance, never safety or idempotency.
- [x] Build-number allocation preserves the existing single global counter.
- [x] Marketing-version bump and persistence prevent later regression.
- [x] Direct-push, missing-PR, ambiguous-PR, and label-API outcomes are defined.
- [x] Failure, summary, no-retry, no-rollback, and strict distribution behavior are explicit.
- [x] Protected-path approval and post-merge evidence are explicit.

## Scope and authority

- [x] Spec 004 history and the later manual-only policy are superseded narrowly.
- [x] Scheduled release is explicitly not restored.
- [x] Product, Fastlane, project configuration, review machinery, rulesets, and runner/secret changes are prohibited.
- [x] No tracked personal, account, team, workspace, or credential value is introduced.
- [x] The separate review-machinery sequencing dependency is stated without becoming source scope.

## Readiness

- [x] Constitution and RepoInfra ownership checks have no unresolved conflict.
- [x] Every AC maps to a task or explicit external delivery gate.
- [x] The implementation graph is single-layer, acyclic, and schedulable.
- [x] Verification uses repository hooks/resolver gates and forbids host-based app tests.
- [x] The specification is ready for exact-revision AI Reviewer spec gate.
