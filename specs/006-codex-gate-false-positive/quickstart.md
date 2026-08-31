# Quickstart: Gate Repair and PR #199 Recovery

## 1. Establish B000 before dispatch

- Pin T001's proposed `delivery_base_sha` to current `main`.
- Require a successful `review-gate (pytest)` check for that exact SHA.
- Current evidence is valid only for
  `40a920526ebf69c07dfa85a109ad2c585c5cb70a`: Actions run `33342454411`, job
  `99340425368`.
- If `main` advances, re-check the replacement exact SHA. Missing or failing
  evidence keeps T001 blocked and requires a separate RepoInfra prerequisite.

## 2. Implement the reviewed RepoInfra task

- Start from current `main` in a dedicated RepoInfra worktree/branch.
- Read the root constitution and the `RepoInfra` context chain.
- Modify only:
  - `scripts/ci/review-common.sh`
  - `scripts/ci/tests/test_review_shell.py`
  - `docs/ci-gates.md`
- Keep all workflows, rulesets, Aidata files, PR #198, and PR #199 untouched.
- In `review-common.sh`, change only `review_evidence_rules()` and its adjacent
  explanation; do not change `run_with_timeout` or process-group behavior.
- In `test_review_shell.py`, add only the prompt-contract regression; do not
  change existing timeout/process-group tests.
- If either named `test_run_with_timeout_*` failure or the Homebrew-Bash
  `check-tasks-fresh` hang recurs, stop and return to Team Lead. Do not absorb,
  retry around, or repair it within T001.
- Let normal pre-commit/pre-push hooks execute the local RepoInfra gate.

## 3. Review and land the repair

- Pin local HEAD, pushed branch OID, and repair-PR `headRefOid` to one SHA.
- Obtain all checks green and an exact-SHA Multica AI Reviewer PASS.
- PR Manager merges the repair to `main`; no bypass is permitted.

## 4. Refresh PR #199 only after the repair is on main

- Team Lead schedules the refresh of the existing AidataL4 branch from the new
  current `main`.
- Preserve the existing MY-1495 allowlist:
  - `aidata/L4_serve/queries/attribution/cost-by-project.sql`
  - `aidata/tests/test_query_tiers.py`
- Do not reuse or modify PR #198.

## 5. Re-establish exact-HEAD evidence

- Confirm local HEAD, remote branch OID, and PR #199 `headRefOid` match.
- Require every check, including `codex-review-target`, to be green.
- Obtain a fresh Multica AI Reviewer PASS for that same refreshed HEAD.
- Hand the exact evidence to PR Manager for merge.

## 6. Release the downstream dependency

MY-1496 remains blocked until PR #199/MY-1495 is proven merged to `main`.
