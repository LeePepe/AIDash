# Feature Specification: Complete-Predicate Evidence for Required Review

**Feature ID**: `006-codex-gate-false-positive`

**Created**: 2026-08-31

**Status**: Planning candidate

**Input**: Keep the required `codex-review-target` gate fail-closed while
repairing the repeatable false blocker on PR #199. Land the RepoInfra repair
before refreshing PR #199; do not bypass the gate or mutate PR #198 or PR #199
during planning.

## User Scenarios & Testing

### User Story 1 - Classify validation predicates from complete evidence (Priority: P1)

As a repository maintainer, I need the required automated reviewer to evaluate
the complete deciding predicate before claiming that a value is rejected, so
a partial diff hunk cannot turn an accepted value into a repeatable false
blocker.

**Why this priority**: A false blocker in a required check stops every valid
change behind it. The gate must remain fail-closed for real defects and tool
failures, so the repair has to improve evidence discipline without weakening
the merge policy.

**Independent Test**: A hermetic RepoInfra regression renders the exact shared
trusted prompt clause used by the live gate and pins its abstention contract:
an isolated allowlist from a partial hunk cannot support a value-rejection
blocker. The PR #199 shape—`VALID_TIERS = {"explore"}` in the hunk while the
unchanged predicate is `tier not in VALID_TIERS | {"production"}`—is the
regression example. The deterministic test verifies prompt policy and shared
helper consumption; it does not assert a nondeterministic model verdict.

**Acceptance Scenarios**:

1. **Given** a diff hunk shows `VALID_TIERS = {"explore"}` but not the complete
   membership predicate, **when** the reviewer evaluates whether `production`
   is invalid, **then** that partial constant alone is insufficient evidence
   for a blocker.
2. **Given** the complete predicate is
   `tier not in VALID_TIERS | {"production"}`, **when** the reviewer evaluates
   `production`, **then** it recognizes that the value is accepted and does
   not issue the contradicted invalid-tier blocker.
3. **Given** a complete predicate actually rejects an invalid value, **when**
   the reviewer has direct diff or supplied evidence for that predicate,
   **then** the existing critical/high blocker behavior remains available.
4. **Given** the review tool, evidence builder, parser, schema validation, or
   timeout path fails, **when** the gate completes, **then** it still exits
   non-zero and does not permit merge.
5. **Given** T001 is ready to dispatch, **when** Team Lead pins its exact
   implementation base, **then** that same commit has a successful
   `review-gate (pytest)` check before Fullstack starts; a missing or failing
   baseline keeps T001 blocked.

### Edge Cases

- A constant is shown in a hunk while a union, fallback, normalization step, or
  negated comparison that determines acceptance is outside the hunk.
- A predicate spans multiple lines or helper names; absence of the complete
  deciding expression is treated as missing evidence, not proof of rejection.
- A value is genuinely rejected by a complete predicate; the new discipline
  must not downgrade a directly proven functional defect.
- The prompt contract is edited while one live gate stops consuming the shared
  helper; regression coverage must catch that drift.
- An analyzer or review CLI fails; fail-closed tool-error behavior is unchanged.

## Requirements

### Functional Requirements

- **FR-001**: The shared trusted evidence discipline MUST require a blocker
  alleging that a value is invalid or rejected to cite and evaluate the
  complete deciding predicate.
- **FR-002**: Complete-predicate evaluation MUST account for unions, defaults,
  normalization, negation, and other same-expression qualifiers that can alter
  whether the value is accepted.
- **FR-003**: An isolated constant, partial hunk, or unshown helper MUST NOT be
  treated as sufficient proof that a value is rejected.
- **FR-004**: Missing complete-predicate evidence MUST prevent this class of
  blocker; it MAY be reported as a non-blocking note when uncertainty remains.
- **FR-005**: Directly proven critical/high defects—including failures shown by
  direct test or CI output—and all tool/schema/timeout failures MUST continue
  to fail closed.
- **FR-006**: The live Codex required gate MUST consume the shared evidence
  discipline; the repair MUST NOT add a gate-specific copy that can drift.
- **FR-007**: Hermetic RepoInfra regression coverage MUST pin abstention for the
  incomplete PR #199 hunk, record the complete predicate that accepts
  `production`, and verify shared-helper consumption.
- **FR-008**: The repair MUST preserve the trusted-base checkout, the untrusted
  PR-data fence, the required ruleset entry, and the existing severity
  threshold.
- **FR-009**: The repair implementation MUST remain in the RepoInfra layer and
  MUST NOT modify Aidata product/data files, PR #198, or PR #199.
- **FR-010**: PR #199 MUST be refreshed only after the reviewed RepoInfra repair
  reaches `main`; the refreshed L4 candidate MUST retain its existing allowlist
  and obtain all-green checks plus a fresh Multica AI Reviewer PASS on the same
  resulting HEAD before shipping.
- **FR-011**: MY-1496 MUST remain blocked until MY-1495 is delivered to `main`.
- **FR-012**: Before T001 dispatch, Team Lead MUST pin the exact implementation
  base and verify a successful `review-gate (pytest)` check for that same
  commit. If `main` advances, the evidence MUST be refreshed for the new base.
- **FR-013**: The existing timeout/process-group behavior and the Homebrew-Bash
  `check-tasks-fresh` hang are outside T001. If
  `test_run_with_timeout_kills_nested_wrapper_descendants`,
  `test_run_with_timeout_kills_the_whole_process_group`, or that hang recurs,
  Fullstack MUST stop without repairing or retrying around it and return the
  blocker to Team Lead for a separately planned RepoInfra prerequisite.

### Key Entities

- **Evidence discipline**: Trusted instructions that constrain which facts may
  justify a blocking verdict.
- **Complete predicate**: The full decision expression and its material
  qualifiers that determine whether a value is accepted or rejected.
- **Required review result**: The fail-closed `codex-review-target` status for
  one exact PR HEAD.
- **Dependent L4 candidate**: PR #199 after it is refreshed from a `main` that
  already contains the gate repair.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Removing or weakening the incomplete-evidence abstention
  instruction causes the new RepoInfra regression to fail.
- **SC-002**: Before dispatch, the exact T001 implementation base has a
  successful `review-gate (pytest)` check. At planning time,
  `40a920526ebf69c07dfa85a109ad2c585c5cb70a` satisfies this through Actions run
  `33342454411`, job `99340425368`.
- **SC-003**: The complete RepoInfra local gate exits 0 for the T001 repair
  revision without changing timeout/process-group behavior; recurrence of a
  named baseline failure blocks T001 and returns it to Team Lead.
- **SC-004**: Existing regressions for direct blockers and fail-closed tool,
  timeout, parse, and schema failures remain green.
- **SC-005**: No workflow, ruleset, Aidata, PR #198, or PR #199 file is present
  in the gate-repair implementation diff.
- **SC-006**: After the repair reaches `main`, PR #199 is refreshed and its new
  exact HEAD has all checks green and a fresh Multica AI Reviewer PASS before
  PR Manager merge.

## Constraints and Non-Goals

- The owner selected fail-closed repair; no admin bypass is authorized.
- This feature does not widen MY-1495's AidataL4 file allowlist or change the
  L4 attribution contract already accepted at `6cefdd4ac8b00dc8b896014cca3ba38ec6dcff17`.
- It does not redesign automated review, add a model call, add a new analyzer,
  change severity thresholds, or alter ruleset membership.
- It does not refresh, rebase, amend, or otherwise mutate PR #199 as part of
  planning or of the RepoInfra repair task.
- It does not repair existing timeout/process-group tests or the
  `check-tasks-fresh` Bash transport. Those require a separate RepoInfra plan if
  the exact-base readiness gate or T001 hook exposes them again.

## Assumptions

- `review_evidence_rules()` remains the single shared trusted prompt seam used
  by the live Codex gate.
- The existing RepoInfra test harness is the correct deterministic surface for
  prompt-contract regressions.
- The current `main` planning base is
  `40a920526ebf69c07dfa85a109ad2c585c5cb70a`.
