# Quickstart: RepoInfra Raven Interpreter Delegation

## Preconditions

1. Use the MY-1746 delivery workspace prepared from exact base
   `c1f6ea8ec4a41a1993591fd454aafdae08194358`.
2. Read `AGENTS.md`, `.specify/memory/constitution.md`, `CONTEXT.md`, and
   `scripts/CONTEXT.md`.
3. Confirm the resolver maps `scripts/ci/review-python311`,
   `scripts/ci/codex-review.sh`, `scripts/ci/tests/test_review_raven.py`, and
   `scripts/ci/tests/review_raven_contract.py` to RepoInfra.
4. Confirm no prior candidate or competing implementation workspace exists.

## Implement

1. Modify only `scripts/ci/review-python311` (new),
   `scripts/ci/codex-review.sh`, `scripts/ci/tests/test_review_raven.py`, and
   `scripts/ci/tests/review_raven_contract.py`.
2. Implement the shared adapter from `contracts/delegation-contract.md`.
3. Keep the wrapper importable under Python 3.9 and route its existing offline
   contract invocation through the adapter.
4. Change only the production caller's interpreter prefix; keep its helper,
   argv, redirections, and watchdog intact.
5. Update only the caller contract's literal launcher-prefix source assertion
   to require the adapter; leave every other existing assertion unchanged.
6. Add deterministic focused cases for both adapter branches, exact argv
   forwarding, and every missing/incompatible delegation failure.

## Verify and publish

1. Review `git diff --name-only` and reject any path outside the allowlist.
2. Stage the four allowed files and commit normally. Do not use `--no-verify`;
   the resolver-selected pre-commit hook is the authoritative local test.
3. If a hook fails, repair only the emitted RepoInfra cause and commit again.
   Do not proactively repeat pytest.
4. Freeze the local candidate, obtain exact-SHA AI Reviewer implementation
   PASS, then push only that reviewed SHA and create/update the non-Draft PR.
5. Hand the published PR to PR Manager. Team Lead decides when to retry the
   separate reviewed T022 tree after this repair lands.
