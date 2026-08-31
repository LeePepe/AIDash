# Implementation Plan: Complete-Predicate Evidence for Required Review

**Feature**: `006-codex-gate-false-positive` | **Date**: 2026-08-31 |
**Spec**: `specs/006-codex-gate-false-positive/spec.md`

**Input**: Owner decision B: preserve the required fail-closed Codex gate,
repair the repeatable invalid-tier false inference with regression coverage,
land the repair, then refresh PR #199 and obtain same-HEAD green checks plus a
fresh Multica AI Reviewer PASS.

## Summary

Extend the existing shared trusted prompt interface in
`scripts/ci/review-common.sh` so value-rejection blockers require the complete
deciding predicate, not an isolated declaration from a partial hunk.
Pin the PR #199 `VALID_TIERS | {"production"}` shape in the existing hermetic
shell regression suite and document the invariant. The implementation is one
RepoInfra task and does not change workflows, rulesets, Aidata, or either
preserved PR branch.

## Technical Context

**Language/Version**: Bash 3.2-compatible shell for prompt helpers; Python 3
with pytest for regression coverage

**Primary Dependencies**: Repository-owned shell helpers, Python standard
library, pytest; no new dependency

**Storage**: N/A

**Testing**: Resolver-declared RepoInfra pytest and hook-syntax gates, invoked
through normal repository hooks; CI additionally runs ruff

**Target Platform**: GitHub Actions `pull_request_target` on the trusted base,
with the `aidash-mac` self-hosted runner for the Codex CLI

**Project Type**: Repository automation / merge gate

**Performance Goals**: No additional model call or analyzer pass; only a small
bounded trusted prompt-text increase

**Constraints**: Fail closed; preserve trusted-base checkout and untrusted-data
fence; no admin bypass; no workflow/ruleset change; no PR #198/#199 mutation;
T001 dispatch requires an exact-base green `review-gate (pytest)` baseline;
known timeout/process-group failures and the `check-tasks-fresh` Bash hang are
out of scope and stop the task if they recur

**Scale/Scope**: One shared prompt helper, one existing regression module, one
operator document; one RepoInfra implementation task

## Constitution Check

### Before Phase 0 research

- **Scope Discipline**: PASS. The repair is uniquely owned by RepoInfra and has
  an explicit three-file allowlist plus explicit exclusions.
- **Testing / hook ownership**: PASS with an explicit entry gate. Exact current
  `main` `40a920526ebf69c07dfa85a109ad2c585c5cb70a` passed the full RepoInfra CI
  gate in Actions run `33342454411`, job `99340425368`. Team Lead must refresh
  that same-SHA evidence if the implementation base changes. Local recurrence
  of the named baseline failures stops T001 instead of expanding its scope.
- **Identity hygiene**: PASS. The regression uses language tokens and neutral
  values only; it introduces no account, employer, or machine identifier.
- **Dependency direction**: PASS. RepoInfra has no declared dependencies and
  the repair introduces none.
- **Security / fail-closed posture**: PASS. Trusted-base execution,
  untrusted-data fencing, tool-error failure, required ruleset membership, and
  blocker thresholds remain unchanged.

### After Phase 1 design

- **Interface depth**: PASS. The change extends the existing shared
  `review_evidence_rules()` seam consumed by the live gate rather than adding a
  second prompt copy or a new analyzer.
- **Regression coverage**: PASS. The contract test pins the incomplete-hunk
  abstention policy, records the complete predicate as the contradicted
  evidence, and verifies consumption of the shared helper without claiming a
  deterministic model verdict.
- **Cross-layer behavior**: PASS. The only downstream relationship is a
  delivery dependency: the independent AidataL4 candidate is refreshed after
  the RepoInfra repair lands; no cross-layer implementation task is created.
- **No constitutional exception**: PASS. Complexity Tracking is not required.

## Design

### Existing control path

```text
.github/workflows/codex-review-target.yml (trusted base)
  -> scripts/ci/codex-review.sh
       -> review_evidence_rules() in scripts/ci/review-common.sh
       -> PR diff + optional scope evidence inside untrusted-data fence
       -> fail-closed structured verdict
```

The current evidence rule handles Swift modifier receiver ambiguity and
injection-token intent, but it does not explicitly forbid validation claims
made from an incomplete predicate. Python diffs receive no Swift scope
evidence, so the PR #199 hunk exposed `VALID_TIERS = {"explore"}` without the
unchanged union that admits `production`.

### Pre-dispatch readiness gate B000

B000 is a Team Lead-owned scheduling gate, not a Fullstack implementation task:

1. Pin the proposed T001 `delivery_base_sha` to the then-current `main`.
2. Verify that exact commit has a successful GitHub
   `review-gate (pytest)` check. A green check on another SHA is not evidence.
3. Only then prepare T001's delivery workspace and dispatch Fullstack.
4. If the check is missing or failing, keep T001 blocked and obtain a separate
   RepoInfra prerequisite plan; do not fold baseline repair into T001.

Current evidence satisfies B000 only while the implementation base remains
`40a920526ebf69c07dfa85a109ad2c585c5cb70a`: Actions run `33342454411`, job
`99340425368` ran `scripts/context/run RepoInfra --mode ci` and completed all
pytest, hook-syntax, and ruff gates successfully. If `main` advances before
dispatch, Team Lead must re-establish B000 for the replacement exact SHA.

### Selected repair

Add a complete-predicate clause to `review_evidence_rules()`:

1. A blocker claiming that a value is invalid or rejected must cite the entire
   deciding expression available in diff/evidence.
2. Unions, defaults, normalization, negation, and helper qualifiers must be
   evaluated before classifying the value.
3. A partial constant or omitted predicate is missing evidence; it cannot
   support a blocker in this class.
4. A complete predicate that directly proves rejection remains eligible for a
   critical/high blocker. Direct test/CI failure output also remains independent
   blocking evidence and is not subject to this partial-predicate abstention.

The rule remains in the trusted pre-fence prompt. The PR-shaped regression
renders the real helper and pins abstention when the hunk shows only the
isolated set while the complete union is outside the hunk. It also asserts that
the live gate continues to call the shared helper instead of an inline copy.
It deliberately tests the deterministic prompt contract, not a model verdict.

### Alternatives rejected

- **Admin bypass**: rejected by the owner; it leaves the recurring defect and
  violates the selected fail-closed delivery posture.
- **Change the Aidata allowlist or tier marker**: rejected because the exact
  predicate already accepts `production`; changing L4 would hide the reviewer
  defect and expand MY-1495 scope.
- **New Python semantic analyzer/full-file evidence generator**: rejected for
  this repair because the prompt already has enough information to require
  evidence before blocking. A new analyzer broadens scope, attack surface,
  prompt size, and failure modes without being necessary.
- **Edit `codex-review.sh` directly**: rejected because it already consumes the
  shared helper. A second copy would create drift.
- **Change workflow or ruleset**: rejected; required status and trusted-base
  execution are correct and must remain intact.

## Project Structure

### Documentation (this feature)

```text
specs/006-codex-gate-false-positive/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── review-evidence-discipline.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source code (implementation revision)

```text
scripts/ci/review-common.sh
scripts/ci/tests/test_review_shell.py
docs/ci-gates.md
```

**Structure Decision**: Extend the existing RepoInfra prompt-contract seam and
its colocated regression suite. No new module or directory is introduced.

## Vertical Slice and Layer Graph

| Slice | Outcome | Layer task | Upstream dependency |
|---|---|---|---|
| US1 | Required reviewer evaluates validation claims from complete predicates while preserving fail-closed behavior | T001 · RepoInfra | Reviewed planning revision + B000 exact-base green baseline |

T001 is the only implementation task. The PR #199 refresh is not hidden inside
it; it is a downstream Team Lead/PR Manager delivery dependency on T001 being
reviewed, merged, and visible in `main`.

## Delivery Dependency Sequence

1. AI Reviewer passes this exact planning revision.
2. Team Lead establishes B000: pin T001's exact current-`main` base and verify
   that same SHA has a successful `review-gate (pytest)` check. A newer base
   requires new evidence; missing/failing evidence keeps T001 blocked.
3. Only after B000, Team Lead schedules T001 on a fresh RepoInfra
   branch/worktree; PR #198 and PR #199 remain untouched.
4. Fullstack implements only the complete-predicate prompt contract. If either
   named `run_with_timeout` failure or the Homebrew-Bash `check-tasks-fresh`
   hang recurs, Fullstack stops without changing that behavior and returns the
   blocker to Team Lead for a separate RepoInfra prerequisite.
5. Normal hooks run the RepoInfra local gate; the implementation then receives
   exact-SHA AI Reviewer PASS plus all checks green.
6. PR Manager merges the RepoInfra repair to `main` without bypass.
7. Team Lead refreshes PR #199 from the resulting current `main`. The new HEAD
   may contain only the existing two-file AidataL4 candidate plus the merged
   base history; MY-1495's allowlist is not expanded.
8. The refreshed PR #199 exact HEAD must have every check green and a fresh
   Multica AI Reviewer PASS on that same HEAD before PR Manager merge.
9. Only after MY-1495 is proven on `main` may Team Lead promote MY-1496.

## Risks and Controls

| Risk | Control |
|---|---|
| Prompt wording becomes a broad “never block” exception | Contract limits the downgrade to missing complete-predicate evidence and explicitly preserves direct blockers |
| Codex and another gate drift | Existing shared helper remains the single source; regression asserts live consumption |
| Repair accidentally changes product/data behavior | Three-file RepoInfra allowlist and explicit Aidata/workflow/ruleset exclusions |
| Gate fails open on tool error | Existing non-zero timeout, evidence, parse, schema, and tool paths remain covered and unchanged |
| Known baseline flake is accidentally absorbed into T001 | B000 requires same-SHA green CI before dispatch; T001 red lines forbid timeout/process-group and task-freshness transport repair and require immediate return to Team Lead on recurrence |
| Old base keeps using old prompt | Repair must reach `main` before PR #199 refresh because `pull_request_target` reads the trusted base |
| Review evidence becomes stale after refresh | Exact local/remote/PR HEAD pin and fresh same-HEAD AI Reviewer PASS are required |

## Complexity Tracking

No constitution violation or complexity exception is required.
