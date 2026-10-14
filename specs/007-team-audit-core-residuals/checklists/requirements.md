# Specification Quality Checklist: Hidden Team Audit Core Residuals

**Purpose**: Verify the Decision B successor before the single final plan gate.

**Created**: 2026-10-14

**Feature**: `specs/007-team-audit-core-residuals/spec.md`

## Authority and scope

- [x] Accepted version is issue revision 5 plus Decision B comment revision 1.
- [x] Current-main baseline and repository identity are immutable and explicit.
- [x] Predecessor artifacts/candidate/review are evidence only and remain untouched.
- [x] The named review-machinery item is only a later merge dependency.
- [x] Registration, enumeration, discovery, public API, UI, App, CLI, aidata, and unrelated behavior are excluded.

## Behavior contract

- [x] Existing behavior, compatibility, and removed/superseded behavior are explicit.
- [x] No accepted current-main behavior or test is removed.
- [x] Stable US1/AC1–US1/AC7 and FR-001–FR-009 IDs exist.
- [x] Nil and present artifact `caseID` semantics are deterministic.
- [x] Full-report resolution names kind, ID, hash, raw URL, sidecar ID, and sidecar hash.
- [x] Externalized-versus-resolved equality and positive byte counts are explicit.
- [x] The eight optional-only externalizable kinds and unknown-value behavior are locked.
- [x] AIDashCore URL-policy ownership is preserved without duplicating policy in Types.

## Plan and tasks

- [x] The implementation allowlist is exactly two AIDashCore paths.
- [x] Forbidden sibling, generic-test, public API, and consumer paths are explicit.
- [x] Recursive context ownership and one-layer dependency direction are recorded.
- [x] One vertical slice maps every AC to one schedulable layer task.
- [x] The task graph is acyclic and the merge dependency does not create scope.
- [x] Verification is hook-driven, Packages-only, and forbids local `xcodebuild`.
- [x] Completion conditions include exact diff surface, unchanged card count, neutral fixtures, and no weakened tests.

## Review readiness

- [x] No unresolved clarification marker remains.
- [x] Constitution 1.13.0 passes pre- and post-design checks.
- [x] The residual contract matrix covers a positive and each independent negative.
- [x] Historical findings already closed by Reviewer round 2 are excluded.
- [x] Exact planning commit and artifact blobs will be pinned in the review request.
- [x] A `NEEDS_WORK` verdict ends the authorized review cycle and returns to Team Lead.
