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
- [x] The 2026-10-15 delegated Owner refinement supersedes the earlier
  queue/journal/recovery planning model without changing repository authority.
- [x] FR-001–FR-015 use mandatory, testable language.
- [x] AC-01–AC-12 provide stable review identifiers.
- [x] Automatic and manual entrypoints select immutable candidates.
- [x] Automatic provenance requires push, same repository, exact workflow path,
  success, main, and protected-main reachability before privileges.
- [x] One per-app group serializes release work without claiming durable
  per-head queue behavior or survival of every pending head.
- [x] `testflight/last-released` is the sole durable release-progress state;
  queue/cursor/skip/journal/quarantine/recovery state is prohibited.
- [x] Existing-marker relevance accumulates over `marker..candidate`; skipped
  and failed runs leave the marker unchanged.
- [x] Missing-marker first-parent/root bootstrap is explicit and introduces no
  second durable state.
- [x] Equal, ancestor, descendant/stale, unrelated, missing, and invalid marker
  states are defined with no-rewind behavior.
- [x] Mixed automatic/manual force ordering and same-recorded-SHA protection are
  explicit; force bypasses only path relevance.
- [x] Failure pickup distinguishes existing-marker accumulation from absent-
  marker first-parent bootstrap; no automatic retry, rollback, exactly-once
  claim, or marker-only recovery remains.
- [x] App-relevant and non-relevant path families are exact.
- [x] Build-number allocation preserves the existing single global counter.
- [x] Marketing-version bump and marker persistence prevent later regression.
- [x] Direct-push, missing-PR, ambiguous-PR, and label-API outcomes are defined.
- [x] Group existence and exact selected-build membership are independently
  proven; strict-mode configuration alone is not treated as evidence.
- [x] Every executed run's failure/skip/success summary is explicit; no survivor
  synthesizes per-candidate evidence for a replaced pending run.
- [x] Protected-path approval and post-merge evidence are explicit.

## Scope and authority

- [x] Spec 004 history and the later manual-only policy are superseded narrowly.
- [x] Scheduled release is explicitly not restored.
- [x] Product, Fastlane, project configuration, review machinery, rulesets, and
  runner/secret changes are prohibited.
- [x] No tracked personal, account, team, workspace, or credential value is
  introduced.
- [x] The MY-1692 sequencing dependency is stated without becoming source scope.
- [x] `.specify/feature.json` and the `AGENTS.md` Spec Kit marker both select
  Spec 007 and are frozen with the reviewed package.

## Readiness

- [x] Constitution and RepoInfra ownership checks have no unresolved conflict.
- [x] AC-01–AC-10 map to sole implementation task T001; AC-11–AC-12 map to
  explicit external delivery gates.
- [x] US1–US3 are ordered internal phases, not extra tasks/issues/PRs; the
  implementation graph is single-layer, acyclic, and schedulable.
- [x] Verification uses repository hooks/resolver gates and forbids host-based
  app tests.
- [x] Replacement tests remain compatible with the gate's `/usr/bin/python3`
  (currently Python 3.9).
- [x] Focused cases cover irrelevant accumulation, mixed auto/manual force,
  failed-release pickup, absent-marker bootstrap, and same-recorded-SHA safety.
- [x] The specification is ready for the authorized final exact-revision AI
  Reviewer spec gate.
