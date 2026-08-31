# Quickstart: Gate Repair and PR #199 Recovery

## 1. Implement the reviewed RepoInfra task

- Start from current `main` in a dedicated RepoInfra worktree/branch.
- Read the root constitution and the `RepoInfra` context chain.
- Modify only:
  - `scripts/ci/review-common.sh`
  - `scripts/ci/tests/test_review_shell.py`
  - `docs/ci-gates.md`
- Keep all workflows, rulesets, Aidata files, PR #198, and PR #199 untouched.
- Let normal pre-commit/pre-push hooks execute the local RepoInfra gate.

## 2. Review and land the repair

- Pin local HEAD, pushed branch OID, and repair-PR `headRefOid` to one SHA.
- Obtain all checks green and an exact-SHA Multica AI Reviewer PASS.
- PR Manager merges the repair to `main`; no bypass is permitted.

## 3. Refresh PR #199 only after the repair is on main

- Team Lead schedules the refresh of the existing AidataL4 branch from the new
  current `main`.
- Preserve the existing MY-1495 allowlist:
  - `aidata/L4_serve/queries/attribution/cost-by-project.sql`
  - `aidata/tests/test_query_tiers.py`
- Do not reuse or modify PR #198.

## 4. Re-establish exact-HEAD evidence

- Confirm local HEAD, remote branch OID, and PR #199 `headRefOid` match.
- Require every check, including `codex-review-target`, to be green.
- Obtain a fresh Multica AI Reviewer PASS for that same refreshed HEAD.
- Hand the exact evidence to PR Manager for merge.

## 5. Release the downstream dependency

MY-1496 remains blocked until PR #199/MY-1495 is proven merged to `main`.
