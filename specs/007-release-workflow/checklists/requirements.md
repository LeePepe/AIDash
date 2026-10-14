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
- [x] FR-001–FR-015 use mandatory, testable language.
- [x] AC-01–AC-12 provide stable review identifiers.
- [x] Automatic and manual entrypoints select immutable candidates.
- [x] Automatic admission requires push provenance, same repository, exact workflow path, and protected-main reachability before privileges.
- [x] Durable pre-concurrency queueing plus exhaustive successful-run reconciliation survives pending-worker replacement and out-of-order intake.
- [x] A unique workflow sentinel derives a deterministic activation boundary; simultaneous first admissions and newer-before-older intake cannot lose a head.
- [x] Missing, duplicate, stale, non-ancestor, and out-of-order marker states are defined.
- [x] Attempt, confirmation, quarantine, compare-and-swap, and marker-only recovery states prevent automatic same-SHA re-upload.
- [x] Common, normal-release-only, and marker-recovery-only invariants are distinct and fail closed without granting recovery upload authority.
- [x] App-relevant and non-relevant path families are exact.
- [x] Manual force bypasses only path relevance, never safety or idempotency.
- [x] Build-number allocation preserves the existing single global counter.
- [x] Marketing-version bump and persistence prevent later regression.
- [x] Direct-push, missing-PR, ambiguous-PR, and label-API outcomes are defined.
- [x] Group existence and exact selected-build membership are independently proven; strict-mode configuration alone is not treated as evidence.
- [x] Failure, per-candidate summary, no-retry, no-rollback, and strict distribution behavior are explicit.
- [x] Protected-path approval and post-merge evidence are explicit.

## Scope and authority

- [x] Spec 004 history and the later manual-only policy are superseded narrowly.
- [x] Scheduled release is explicitly not restored.
- [x] Product, Fastlane, project configuration, review machinery, rulesets, and runner/secret changes are prohibited.
- [x] No tracked personal, account, team, workspace, or credential value is introduced.
- [x] The separate review-machinery sequencing dependency is stated without becoming source scope.
- [x] `.specify/feature.json` and the `AGENTS.md` Spec Kit marker both select Spec 007 and are frozen with the reviewed package.

## Readiness

- [x] Constitution and RepoInfra ownership checks have no unresolved conflict.
- [x] AC-01–AC-10 map to the sole implementation task T001; AC-11–AC-12 map to explicit external delivery gates.
- [x] US1–US3 are ordered internal phases, not extra tasks/issues/PRs; the implementation graph is single-layer, acyclic, and schedulable.
- [x] Verification uses repository hooks/resolver gates and forbids host-based app tests.
- [x] Replacement tests are required to remain compatible with the gate's `/usr/bin/python3` (currently Python 3.9).
- [x] The specification is ready for exact-revision AI Reviewer spec gate.
