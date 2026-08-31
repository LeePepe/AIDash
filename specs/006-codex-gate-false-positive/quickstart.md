# Quickstart: Structural Gate Repair and PR #199 Recovery

## 1. Preserve the stopped candidate

- Keep PR #205 at `f16e5d503304b7951f995286cdbb0727b6d2472e` Draft.
- Keep auto-merge disabled.
- Do not merge, bypass, rebase, amend, refresh, or reuse its branch.
- Retain its three-file diff and same-SHA gate failure as regression evidence.

## 2. Establish B000 before dispatch

- Pin T001's proposed `delivery_base_sha` to current `main`.
- Require a successful `review-gate (pytest)` check for that exact SHA.
- Evidence at planning start applies only to
  `8716846ac42b48bfd89b9a09d5dd05fc4819025d`: Actions run
  `33350742892`, job `99363478423`.
- If `main` advances, refresh the proof. Missing/failing evidence keeps T001
  blocked and requires a separate RepoInfra prerequisite.

## 3. Prepare a new delivery branch

- Use a new clean RepoInfra worktree/branch from the B000 base.
- Do not use the PR #205 delivery directory or branch as the new repair.
- Read the constitution and `CONTEXT.md` → `scripts/CONTEXT.md` chain.

## 4. Implement only the reviewed structural contract

Allowed paths:

- `scripts/ci/review_context.py`;
- `scripts/ci/review-common.sh`, only `build_scope_evidence()` and its
  adjacent evidence-caller explanation;
- `scripts/ci/tests/test_review_context.py`;
- `scripts/ci/tests/test_review_shell.py`, only structural evidence/preflight
  integration; and
- `docs/ci-gates.md`, only the structural evidence/preflight invariant.

Required behavior:

- forward every changed path to the deep evidence module;
- keep Swift receiver behavior;
- generate typed Python predicate closure from exact-HEAD blobs;
- keep all PR-authored bytes below the untrusted-data fence;
- reject protected instruction changes before the model; and
- preserve all existing fail-closed paths.

## 5. Respect the red lines

Do not edit:

- `review_evidence_rules()` or `review_security_notice()`;
- the Codex prompt, caller, invocation flags, verdict schema/parser, severity,
  timeout/process-group behavior, workflow, or ruleset;
- `scripts/ci/swift_scope.py`;
- hooks or `scripts/hooks/check-tasks-fresh`;
- any Aidata, Swift/App/CLI, PR #199, or PR #205 path/branch.

If either named `test_run_with_timeout_*` failure or the Homebrew-Bash
`check-tasks-fresh` hang recurs, stop and return the evidence to Team Lead.
Do not retry around or repair it inside T001.

## 6. Verify through repository-owned gates

Interface regressions must cover:

- PR #199 accepted-domain evidence and the genuinely rejecting mutation;
- local helpers/defaults, normalization, negation, unresolved/cycle behavior;
- PR #205 `protected_instruction_change` before a model stub runs;
- canonical ordering, whole-fact caps, and explicit omissions;
- untrusted evidence placement;
- unchanged PR #171 Swift behavior; and
- live shell forwarding plus fail-closed analyzer status.

Let normal pre-commit/pre-push hooks invoke:

`scripts/context/run RepoInfra --mode local`

Do not add App, Swift-package, or Aidata suites manually.

## 7. Review and land the new repair

- Prove clean local HEAD = pushed branch OID = new PR `headRefOid`.
- Obtain all required checks green.
- Obtain a fresh exact-SHA Multica AI Reviewer PASS.
- PR Manager merges the new structural repair to `main` without bypass.

## 8. Refresh PR #199 only after repaired main

- Team Lead refreshes the existing AidataL4 candidate from the new `main`.
- Preserve its two-file AidataL4 allowlist.
- Do not reuse or modify PR #198.
- Require every check, including `codex-review-target`, to be green on the
  refreshed exact HEAD.
- Obtain a fresh Multica AI Reviewer PASS for that same HEAD before merge.

## 9. Release the downstream dependency

MY-1496 remains blocked until PR #199 / MY-1495 is proven merged to `main`.
