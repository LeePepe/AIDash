# Specification Quality Checklist: Minimal CI-Gated TestFlight Release

**Purpose**: Verify the `OD-2026-10-15-B` re-scope before independent review.

## Content quality

- [x] Owner outcome, actors, existing behavior, compatibility, and removals are explicit.
- [x] User stories are prioritized and independently testable.
- [x] Stable FR/AC identifiers cover the complete minimal design.
- [x] No placeholder or unresolved product choice remains.

## Minimal-v1 contract

- [x] Trigger is successful same-repository `build` push on `main`; manual dispatch remains.
- [x] Automatic checkout is exact `head_sha` with `fetch-depth: 0` and tags.
- [x] One self-hosted job has ordinary job-level `contents: write`.
- [x] One concurrency group uses `cancel-in-progress: false`.
- [x] Relevance is exactly `git diff --name-only marker..head` against the app roots.
- [x] Irrelevant non-forced execution skips with one summary line before secrets.
- [x] Missing/invalid marker fails closed; retained manual force may bootstrap.
- [x] Existing lane, build-number behavior, runner, signing, and five secrets are preserved.
- [x] All five secrets are scoped only to the build/upload step.
- [x] Marker movement occurs only after successful upload.
- [x] `always()` cleanup restores keychain state and removes run-scoped local artifacts.
- [x] No retry, rollback, alternate runner, cursor, journal, recovery ref, or CAS-only boundary remains.

## Testing and removal

- [x] The workflow invokes the same focused classifier exercised by Python 3.9 unit tests.
- [x] Tests cover included roots, exclusions, mixed/empty inputs, and near misses.
- [x] Actionlint is the explicit workflow-lint gate; its absence/failure blocks delivery.
- [x] The obsolete manual-only test is replaced.
- [x] The unpublished 542-line shadow-policy suite is discarded, not ported, and must be listed in the PR body.

## Scope and delivery

- [x] T001 is one RepoInfra task/issue/PR with four final paths or fewer.
- [x] Product, Fastlane, project, CI-build, review, ruleset, and planning paths are excluded.
- [x] `e8c353ce` preservation/non-publication is a Team Lead recovery precondition.
- [x] Protected-path approval and the MY-1692 merge gate are unchanged.
- [x] Round-2 implementation review failure parks and reports without another round or Owner escalation.
- [x] The package is ready for exact-revision AI Reviewer spec gate.
