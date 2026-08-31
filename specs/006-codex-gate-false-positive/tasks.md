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

B000 proves baseline health only. Existing green tests and an empty prepared
branch do not satisfy T001.

## Exact-Base Status - Expected Red Starting Point

Read-only reconciliation against `8716846` proves the implementation delta
is missing:

- `build_scope_evidence()` forwards only `*.swift` and returns early for
  Python/protected-file-only diffs;
- `review_context.py` skips non-Swift files and emits only text Swift receiver
  evidence;
- no claim-completion/bundle or protected-file enforcement symbols/tests
  exist; and
- the typed whole-record cap contract is absent.

The actual analyzer returns exit 0 with zero stdout for both the PR #199
Python input and PR #205 protected-file input. That is the red acceptance
signal. A clean `HEAD == base` delivery workspace is correct preparation, not
completion and not a reason to fabricate a no-op commit.

## Phase 1: User Story 1 - Trusted Structural Review Evidence (Priority: P1)

**Goal**: The required reviewer receives claim-scoped exact-HEAD Python
predicate evidence from base-owned code, while the landed preflight protects
its complete enforcement chain before model invocation and existing
Swift/fail-closed behavior remains intact.

**Independent Test**: Add the named regressions first and observe them fail
against the pinned base. After implementation, the same selectors prove the
PR #199 predicate/RHS claims, unresolved regex/group helper semantics,
rejecting mutation, canonical whole-fact bundle, all-path forwarding, and
five-file protected-enforcement/no-model behavior.

- [ ] **T001 [US1]** Implement the missing claim-scoped Python evidence bundle and five-file protected-enforcement bootstrap in `scripts/ci/review_context.py`, wire all-path invocation in `scripts/ci/review-common.sh`, add the mandatory red→green regressions in `scripts/ci/tests/test_review_context.py` and `scripts/ci/tests/test_review_shell.py`, and document the delta in `docs/ci-gates.md`.

### T001 Metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra`; context chain `CONTEXT.md` → `scripts/CONTEXT.md` |
| Files in scope | `scripts/ci/review_context.py`: add `PROTECTED_ENFORCEMENT_PATHS`, claim/evidence/bundle types, HEAD hunk-context mapping, private Python adapter, base/head blob check, canonical whole-record cap renderer, and preflight-first CLI dispatch; `scripts/ci/review-common.sh`: only `build_scope_evidence()` and adjacent explanation, removing Swift-only filtering/early return and forwarding every path; `scripts/ci/tests/test_review_context.py`: named claim/bundle/protected-file regressions; `scripts/ci/tests/test_review_shell.py`: named all-path and no-model propagation regressions only; `docs/ci-gates.md`: exact-base gap, red→green bootstrap, claim semantics, and protected-file invariant |
| Files/regions out of scope | `review_evidence_rules()`, `review_security_notice()`, `run_with_timeout`, and existing timeout/process-group tests even though they share in-scope files; `scripts/ci/codex-review.sh`, `claude-review.sh`, `kimi-review.sh`, `swift_scope.py`; `.github/workflows/**`; `scripts/rulesets/**`; hooks and `scripts/hooks/check-tasks-fresh`; all `aidata/**` and Swift/App/CLI packages; PR #198, PR #199, and PR #205 branch/candidate |
| Interface impact | Deepens the existing internal shell/CLI evidence interface; callers keep one entry point. Adds versioned claim-scoped predicate facts and a pre-model `protected_enforcement_change` failure. T001 is the one bootstrap publication; later protected changes require a new owner-reviewed contract. No public product/data interface changes. |
| Task-local acceptance | The exact new selectors first fail against pinned-base behavior and later pass unchanged; all paths reach the base-owned module; exact-HEAD blobs are read but never checked out/imported/evaluated/executed; PR #199 reports complete predicate-structure and RHS allowed-domain claims, unresolved dynamic subject/helper semantics, and observation-only literal fallback; rejecting mutation changes the allowed domain; after bootstrap, any blob change to `review_context.py`, `review-common.sh`, `codex-review.sh`, `codex-review-target.yml`, or `main-protection.json` fails before model invocation; PR source stays below the fence; the three unchanged protected files remain byte-identical during bootstrap; Swift PR #171 and existing fail-closed behavior remain covered. |
| Exact layer verification | Record the named selectors red before source implementation and green afterward; let normal hooks invoke `scripts/context/run RepoInfra --mode local` and record exit 0. CI invokes RepoInfra in CI mode and ruff. Inspect a non-empty exact diff against this allowlist/region exclusions and prove protected target identity. Do not manually add App, Swift-package, or Aidata suites. |
| Blocking edges | Exact-revision planning PASS; B000 same-SHA green baseline; new clean delivery branch distinct from PR #205 |
| Vertical slice | US1 |

### T001 Interface verification cases

1. **Accepting predicate claims**: PR #199 hunk-context binding yields complete
   `predicate_structure` and `allowed_domain` claims for the exact
   out-of-hunk `not in VALID_TIERS | {"production"}` expression.
2. **Dynamic helper isolation**: `subject_helper_semantics` remains
   `unresolved` for `TIER_DIRECTIVE.search` / `match.group`; the literal
   fallback is an observation with unresolved runtime selection.
3. **Rejecting mutation**: removing the production union changes the typed
   result; the test does not pass through vocabulary alone.
4. **Safe static subset**: literal collections, local bindings, union,
   supported comparisons, negation, normalization/default/fallback evidence,
   and per-claim bounded closure behave deterministically.
5. **Unsupported semantics**: dynamic/cross-file/cyclic forms make only the
   affected claim `unresolved` without fabricated conclusions.
6. **Trust placement**: malicious imperative source is escaped/tagged as
   `untrusted_pr` and appears only below the existing fence.
7. **Self-protecting enforcement**: independent blob mutations to each of
   `review_context.py`, `review-common.sh`, `codex-review.sh`,
   `codex-review-target.yml`, and `main-protection.json` yield
   `protected_enforcement_change`; a model stub never runs. PR #205 is the
   `review-common.sh` fixture.
8. **Stability/caps**: same request produces byte-identical fact/claim
   ordering/digests;
   caps omit whole facts and append explicit omissions.
9. **Compatibility**: existing PR #171 Swift receiver behavior remains
   behavior-compatible.
10. **Live integration**: the shell forwards Swift and Python paths to the
   single module; analyzer/preflight non-zero remains fail closed.

### T001 mandatory red→green selectors

Fullstack first adds these exact test functions without production changes:

- `test_pr199_claim_scoped_predicate_evidence`
- `test_pr199_dynamic_helper_is_unresolved`
- `test_pr199_rejecting_mutation_changes_allowed_domain`
- `test_typed_bundle_is_canonical_and_omits_whole_facts`
- `test_protected_enforcement_file_changes_fail_closed` (parameterized over
  all five protected paths)
- `test_scope_evidence_forwards_all_changed_paths`
- `test_protected_enforcement_failure_stops_before_model`

Run:

```bash
/usr/bin/python3 -m pytest scripts/ci/tests/test_review_context.py::test_pr199_claim_scoped_predicate_evidence scripts/ci/tests/test_review_context.py::test_pr199_dynamic_helper_is_unresolved scripts/ci/tests/test_review_context.py::test_pr199_rejecting_mutation_changes_allowed_domain scripts/ci/tests/test_review_context.py::test_typed_bundle_is_canonical_and_omits_whole_facts scripts/ci/tests/test_review_context.py::test_protected_enforcement_file_changes_fail_closed scripts/ci/tests/test_review_shell.py::test_scope_evidence_forwards_all_changed_paths scripts/ci/tests/test_review_shell.py::test_protected_enforcement_failure_stops_before_model -q
```

Before production edits, at least the PR #199 evidence and protected-file
selectors must fail on behavioral assertions against the existing public
CLI/shell seam (base return code/output). Collection errors, ImportError, or a
missing-new-symbol error do not count as red evidence. After implementation,
the identical command must pass. If it is green before implementation, the
tests are not red-capable and Fullstack stops for planning review.

### T001 hard red lines

- Do not copy, cherry-pick, amend, or continue the PR #205 wording candidate.
- Do not treat an empty freshly prepared branch or the existing green suite as
  delivered behavior; implement the normative non-empty delta above.
- Do not add a PR-controlled exemption/allowlist/attestation for protected
  instruction changes.
- Treat T001 as consumed once its exact reviewed bootstrap reaches `main`;
  no later protected-chain change inherits this authority.
- Do not move exact-HEAD source or evidence above the untrusted-data fence.
- Do not edit prompt functions, the live Codex prompt/caller, model flags,
  schema/parser, severity, workflow, ruleset, hooks, or product/data layers.
- If `test_run_with_timeout_kills_nested_wrapper_descendants`,
  `test_run_with_timeout_kills_the_whole_process_group`, or the Homebrew-Bash
  `check-tasks-fresh` hang occurs, stop without retrying around or repairing
  it; return the evidence to Team Lead for a separately planned prerequisite.

**Quality bars**: Constitution Cross-Cutting Quality Bars and Development
Workflow apply automatically.

## Acceptance Traceability

| Requirement / scenario | Slice | Task/gate | Verification surface |
|---|---|---|---|
| FR-001–FR-004; scenarios 3 and 6 | US1 | T001 | Base-owned module interface, all-path shell forwarding, existing fence |
| FR-005–FR-008; scenarios 1–2 | US1 | T001 | PR #199 per-claim accepting fixture, dynamic-helper unresolved assertion, rejecting mutation |
| FR-009–FR-010 | US1 | T001 | Typed bundle, stable digest/order, trust tag, whole-fact caps |
| FR-011–FR-012; scenario 4 | US1 | T001 | One mutation fixture per protected enforcement file, no-model assertion, one-time bootstrap evidence |
| FR-013–FR-015; scenario 5 | US1 | T001 | Exact diff inspection, Swift compatibility, shell/failure regressions |
| FR-016–FR-017 | US1 | T001 | Layer/file/region allowlist; PR #205 hold/non-reuse evidence |
| FR-018 | Downstream delivery | T001 blocks refresh | Quickstart and Team Lead/PR Manager sequence |
| FR-019; scenario 7 | Pre-dispatch | B000 | Same-SHA `review-gate (pytest)` success |
| FR-020 | Scope containment | T001 red line | Immediate stop-and-return on named recurrence |
| SC-001–SC-005 | US1 | T001 | Module and shell interface regression set |
| SC-006 | Pre-dispatch | B000 | Exact-base GitHub check evidence |
| SC-007 | US1 | T001 | Hook-driven RepoInfra gate, CI/ruff, exact diff inspection |
| SC-008 | Downstream MY-1495 | T001 must reach `main` first | Refreshed PR #199 all checks green + fresh same-HEAD AI Reviewer PASS |
| SC-009; scenario 8 | US1 baseline/delta | T001 | Exact-base probe red, named selectors red→green, non-empty implementation diff |

## Dependency Graph

```text
exact-revision structural planning PASS
  -> B000 exact-base review-gate green + new clean delivery branch
  -> exact base-gap probe red (empty branch is expected starting state)
  -> T001 RepoInfra one-time bootstrap: deep evidence module +
     self-protecting enforcement preflight
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
