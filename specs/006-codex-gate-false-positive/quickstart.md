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
- Confirm `HEAD == delivery_base_sha` and the initial base-to-HEAD diff is
  empty. This is expected preparation, not task completion.

## 4. Prove the base gap before implementation

Exact base `8716846` forwards only Swift paths, skips non-Swift files in the
analyzer, emits zero bytes for the PR #199 Python fixture, returns zero for the
PR #205 protected-file fixture, and contains no claim bundle/Python
adapter/protected-file regressions.

Add the seven named tests from `tasks.md` first and run their exact selectors.
The PR #199 and protected-file selectors must fail against base behavior.
The failure must be a return-code/output assertion through the existing
CLI/shell seam, not test collection, ImportError, or missing-symbol failure.
Existing green tests prove B000 health only. A green new selector before
production edits is not red-capable and must be corrected.

## 5. Implement only the reviewed structural contract

Allowed paths:

- `scripts/ci/review_context.py`;
- `scripts/ci/review-common.sh`, only `build_scope_evidence()` and its
  adjacent evidence-caller explanation;
- `scripts/ci/tests/test_review_context.py`;
- `scripts/ci/tests/test_review_shell.py`, only structural evidence/preflight
  integration; and
- `docs/ci-gates.md`, only the structural evidence/preflight invariant.

Required behavior:

- add the normative production symbols/transformations listed in `plan.md`,
  producing a non-empty implementation diff;
- forward every changed path to the deep evidence module instead of retaining
  the base's Swift-only filter and early return;
- keep Swift receiver behavior;
- generate claim-scoped Python evidence from exact-HEAD blobs: complete
  predicate structure and safe RHS domain, unresolved dynamic subject/helper
  semantics, and observation-only literal fallback;
- keep all PR-authored bytes below the untrusted-data fence;
- after bootstrap, reject any blob change to `review_context.py`,
  `review-common.sh`, `codex-review.sh`,
  `codex-review-target.yml`, or `main-protection.json` before the model;
  and
- preserve all existing fail-closed paths.

## 6. Respect the red lines

Do not edit:

- `review_evidence_rules()` or `review_security_notice()`;
- the Codex prompt, caller, invocation flags, verdict schema/parser, severity,
  timeout/process-group behavior, workflow, or ruleset;
- `scripts/ci/swift_scope.py`;
- hooks or `scripts/hooks/check-tasks-fresh`;
- any Aidata, Swift/App/CLI, PR #199, or PR #205 path/branch.

The unchanged Codex consumer, workflow, and ruleset are protected verification
targets even though they are not implementation files.

If either named `test_run_with_timeout_*` failure or the Homebrew-Bash
`check-tasks-fresh` hang recurs, stop and return the evidence to Team Lead.
Do not retry around or repair it inside T001.

An empty clean branch is not a hard red line. Do not stop merely because the
planned files exist or the existing suite passes; those are baseline facts
already accounted for by the reviewed delta.

## 7. Verify through repository-owned gates

Interface regressions must cover:

- PR #199 complete predicate/RHS-domain claims and the genuinely rejecting
  mutation;
- dynamic regex/group helper semantics remaining unresolved while the literal
  fallback remains observation-only;
- an independent mutation fixture for each of the five protected files
  returning `protected_enforcement_change` before a model stub runs;
- canonical fact/claim ordering, whole-fact caps, and explicit omissions;
- untrusted evidence placement;
- unchanged PR #171 Swift behavior; and
- live shell forwarding plus fail-closed analyzer status.

First record the named selectors red against base behavior, then run the
identical command green after implementation. The final exact base-to-HEAD diff
must be non-empty and remain inside the five-file/region allowlist.

Let normal pre-commit/pre-push hooks invoke:

`scripts/context/run RepoInfra --mode local`

Do not add App, Swift-package, or Aidata suites manually.

## 8. Review and land the one-time bootstrap

- Prove clean local HEAD = pushed branch OID = new PR `headRefOid`.
- Obtain all required checks green.
- Obtain a fresh exact-SHA Multica AI Reviewer PASS.
- PR Manager merges only that exact reviewed structural bootstrap to `main`
  without bypass.
- Once merged, T001's bootstrap authority is consumed. Any later change to a
  protected enforcement link requires a new owner decision and separately
  reviewed trusted-base publication contract.

## 9. Refresh PR #199 only after repaired main

- Team Lead refreshes the existing AidataL4 candidate from the new `main`.
- Preserve its two-file AidataL4 allowlist.
- Do not reuse or modify PR #198.
- Require every check, including `codex-review-target`, to be green on the
  refreshed exact HEAD.
- Obtain a fresh Multica AI Reviewer PASS for that same HEAD before merge.

## 10. Release the downstream dependency

MY-1496 remains blocked until PR #199 / MY-1495 is proven merged to `main`.
