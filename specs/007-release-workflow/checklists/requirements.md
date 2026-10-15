# Specification Quality Checklist: Minimal CI-Gated TestFlight Release

## Content quality

- [x] Focused on user outcomes and repository release contracts
- [x] Existing behavior, compatibility, removed behavior, and non-goals are explicit
- [x] Owner decision B, final Lead decision `01a13ce1-ee23-711b-a336-f64c1e1637f0`, and superseded revision-3 behavior are traceable

## Requirement completeness

- [x] Stable FR and AC identifiers remain traceable across revisions
- [x] Automatic and manual candidate selection is explicit
- [x] Missing/equal/ancestor/non-ancestor marker states are defined
- [x] Manual force and automatic entry share one explicit boundary
- [x] Repository-specific runner/signing/build-number behavior is preserved
- [x] Upload/tag non-atomicity, marker compare-and-swap success boundary, warning-only later cleanup, and lack of retry/recovery are disclosed
- [x] Login-keychain use is unlock-only with unconditional re-lock and no settings/search-list/partition mutation

## Scope and authority

- [x] One `RepoInfra` task owns four implementation paths or fewer
- [x] T001 cites Testing / Who runs tests, Scope Discipline, and Quality Gates instead of replacing hook/CI ownership
- [x] Planning artifacts and prohibited paths are frozen after PASS
- [x] Ordinary job-level contents write is tied to the exact Owner decision
- [x] Removed test/planning behavior is explicitly authorized
- [x] MY-1692 and protected-path merge dependencies remain Team Lead-owned
- [x] Missing-marker behavior is force-only bootstrap, not an implicit cursor
- [x] Full-workflow `actionlint` stays inside the four-path scope without a tracked dependency and mandatory repository gates remain
- [x] Classifier cases extract and execute the exact production block
- [x] Terminal-outcome taxonomy is absent; only minimal secret-free summary facts remain

## Readiness

- [x] No unresolved product or authority decision remains
- [x] The preserved revision-3 candidate is explicitly parked and unpublished
- [x] The normal two-round implementation review budget is explicit
- [x] A blocking round-2 result parks delivery without another round
- [x] Exact-revision AI Reviewer spec-gate PASS is required before resumption
