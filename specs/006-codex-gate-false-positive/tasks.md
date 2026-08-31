---
description: "Layer-scoped task for trusted exact-HEAD decision evidence"
---

# Tasks: Trusted Exact-HEAD Decision Evidence

**Input**: Design documents from
`specs/006-codex-gate-false-positive/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`,
`contracts/review-evidence-discipline.md`, `quickstart.md`

**Organization**: One vertical outcome realized by one atomic RepoInfra task
after the Team Lead-owned B000 exact-base readiness gate. The stopped PR #205
and downstream PR #199 are delivery state, not hidden implementation tasks.

## Pre-Dispatch Gate B000 - Exact-Base RepoInfra Baseline

B000 is a scheduling prerequisite, not an implementation checkbox:

1. Team Lead pins T001's proposed `delivery_base_sha` to then-current `main`.
2. That exact commit must have a successful GitHub
   `review-gate (pytest)` check.
3. Team Lead prepares a new clean delivery branch/worktree; PR #205's branch is
   not reused.
4. Missing/failing same-SHA evidence keeps T001 blocked and requires a
   separately planned RepoInfra prerequisite.

Planning-start evidence applies only to
`8716846ac42b48bfd89b9a09d5dd05fc4819025d`: Actions run `33350742892`,
job `99363478423`. A newer base requires fresh evidence.

## Phase 1: User Story 1 - Trusted Structural Review Evidence (Priority: P1)

**Goal**: The required reviewer receives complete exact-HEAD Python predicate
evidence from base-owned code, while PR changes to instruction-producing
regions fail before model invocation and existing Swift/fail-closed behavior
remains intact.

**Independent Test**: Invoke the module interface with the PR #199 hunk and
exact-HEAD fixture. The bundle includes the out-of-hunk predicate, local
dependencies, and allowed `production` value. Remove `| {"production"}` and
the structural result changes. Invoke it with the PR #205 instruction-surface
diff and a model stub; preflight returns non-zero and the stub is not called.

- [ ] **T001 [US1]** Deepen the trusted evidence module and integrate its protected-surface preflight in `scripts/ci/review_context.py`, `scripts/ci/review-common.sh`, `scripts/ci/tests/test_review_context.py`, `scripts/ci/tests/test_review_shell.py`, and `docs/ci-gates.md`.

### T001 Metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra`; context chain `CONTEXT.md` → `scripts/CONTEXT.md` |
| Files in scope | `scripts/ci/review_context.py` for the deep evidence module, private Python adapter, typed bundle, caps, and protected-region preflight; `scripts/ci/review-common.sh` only inside `build_scope_evidence()` and its adjacent evidence-caller explanation; `scripts/ci/tests/test_review_context.py` for module-interface behavior; `scripts/ci/tests/test_review_shell.py` only for all-path forwarding, protected-surface/no-model, fence placement, and analyzer fail-closed integration; `docs/ci-gates.md` only for the structural evidence/preflight incident and invariant |
| Files/regions out of scope | `review_evidence_rules()`, `review_security_notice()`, `run_with_timeout`, and existing timeout/process-group tests even though they share in-scope files; `scripts/ci/codex-review.sh`, `claude-review.sh`, `kimi-review.sh`, `swift_scope.py`; `.github/workflows/**`; `scripts/rulesets/**`; hooks and `scripts/hooks/check-tasks-fresh`; all `aidata/**` and Swift/App/CLI packages; PR #198, PR #199, and PR #205 branch/candidate |
| Interface impact | Deepens the existing internal shell/CLI evidence interface; callers keep one entry point. Adds versioned typed predicate facts and a pre-model `protected_instruction_change` failure. No public product/data interface changes. |
| Task-local acceptance | All changed paths reach the base-owned module; exact-HEAD blobs are read but never checked out/imported/evaluated/executed; PR #199 fixture resolves the full predicate, local helper/fallback, and allowed `production`; rejecting mutation produces the opposite structural domain; unsupported semantics are explicit, never guessed; PR #205 fixture fails before model invocation; PR source stays below the fence; prompt helpers/caller/workflow/ruleset/severity/schema/timeouts stay unchanged; Swift PR #171 and existing fail-closed behavior remain covered. |
| Exact layer verification | Let normal hooks invoke `scripts/context/run RepoInfra --mode local` and record exit 0. CI invokes RepoInfra in CI mode and ruff. Inspect the exact diff against this allowlist and region exclusions. Do not manually add App, Swift-package, or Aidata suites. |
| Blocking edges | Exact-revision planning PASS; B000 same-SHA green baseline; new clean delivery branch distinct from PR #205 |
| Vertical slice | US1 |

### T001 Interface verification cases

1. **Accepting predicate**: PR #199 hunk-context binding resolves the exact
   out-of-hunk `not in VALID_TIERS | {"production"}` predicate, sorted allowed
   literals, and material local helper/fallback.
2. **Rejecting mutation**: removing the production union changes the typed
   result; the test does not pass through vocabulary alone.
3. **Safe static subset**: literal collections, local bindings, union,
   supported comparisons, negation, normalization/default/fallback evidence,
   and bounded helper closure behave deterministically.
4. **Unsupported semantics**: dynamic/cross-file/cyclic forms are explicit
   `unresolved` facts without fabricated conclusions.
5. **Trust placement**: malicious imperative source is escaped/tagged as
   `untrusted_pr` and appears only below the existing fence.
6. **Protected policy**: the exact PR #205 shape yields
   `protected_instruction_change` non-zero and a model stub is never invoked.
7. **Stability/caps**: same request produces byte-identical ordering/digests;
   caps omit whole facts and append explicit omissions.
8. **Compatibility**: existing PR #171 Swift receiver behavior remains
   behavior-compatible.
9. **Live integration**: the shell forwards Swift and Python paths to the
   single module; analyzer/preflight non-zero remains fail closed.

### T001 hard red lines

- Do not copy, cherry-pick, amend, or continue the PR #205 wording candidate.
- Do not add a PR-controlled exemption/allowlist/attestation for protected
  instruction changes.
- Do not move exact-HEAD source or evidence above the untrusted-data fence.
- Do not edit prompt functions, the live Codex prompt/caller, model flags,
  schema/parser, severity, workflow, ruleset, hooks, or product/data layers.
- If `test_run_with_timeout_kills_nested_wrapper_descendants`,
  `test_run_with_timeout_kills_the_whole_process_group`, or the Homebrew-Bash
  `check-tasks-fresh` hang occurs, stop without retrying around or repairing
  it; return the evidence to Team Lead for a separately planned prerequisite.

**Quality bars**: Constitution `Cross-Cutting Quality Bars and `Development
Workflow apply automatically.

## Acceptance Traceability

| Requirement / scenario | Slice | Task/gate | Verification surface |
|---|---|---|---|
| FR-001–FR-004; scenarios 3 and 6 | US1 | T001 | Base-owned module interface, all-path shell forwarding, existing fence |
| FR-005–FR-008; scenarios 1–2 | US1 | T001 | PR #199 accepting fixture, rejecting mutation, safe-subset/unresolved cases |
| FR-009–FR-010 | US1 | T001 | Typed bundle, stable digest/order, trust tag, whole-fact caps |
| FR-011–FR-012; scenario 4 | US1 | T001 | Exact PR #205 protected-surface fixture and no-model assertion |
| FR-013–FR-015; scenario 5 | US1 | T001 | Exact diff inspection, Swift compatibility, shell/failure regressions |
| FR-016–FR-017 | US1 | T001 | Layer/file/region allowlist; PR #205 hold/non-reuse evidence |
| FR-018 | Downstream delivery | T001 blocks refresh | Quickstart and Team Lead/PR Manager sequence |
| FR-019; scenario 7 | Pre-dispatch | B000 | Same-SHA `review-gate (pytest)` success |
| FR-020 | Scope containment | T001 red line | Immediate stop-and-return on named recurrence |
| SC-001–SC-005 | US1 | T001 | Module and shell interface regression set |
| SC-006 | Pre-dispatch | B000 | Exact-base GitHub check evidence |
| SC-007 | US1 | T001 | Hook-driven RepoInfra gate, CI/ruff, exact diff inspection |
| SC-008 | Downstream MY-1495 | T001 must reach `main` first | Refreshed PR #199 all checks green + fresh same-HEAD AI Reviewer PASS |

## Dependency Graph

```text
exact-revision structural planning PASS
  -> B000 exact-base review-gate green + new clean delivery branch
  -> T001 RepoInfra deep evidence module + protected-surface preflight
       -> named baseline failure: STOP -> Team Lead -> separate prerequisite
  -> new repair PR exact-SHA PASS + all required checks green
  -> structural repair merged to main
  -> Team Lead refreshes PR #199 from repaired main
  -> PR #199 all checks green + fresh same-HEAD AI Reviewer PASS
  -> PR Manager merges PR #199 / MY-1495 reaches main
  -> Team Lead may promote MY-1496

PR #205 f16e5d5... remains Draft/no-auto-merge evidence on a separate branch
and has no edge into the implementation chain.
```

There are no parallel implementation rows: the module, shell forwarding,
preflight, regressions, and operator contract must land atomically in the one
RepoInfra layer.
