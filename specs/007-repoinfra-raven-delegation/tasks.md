# Tasks: RepoInfra Raven Interpreter Delegation

**Input**: Design documents from `specs/007-repoinfra-raven-delegation/`

**Prerequisites**: [spec.md](spec.md), [plan.md](plan.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/delegation-contract.md](contracts/delegation-contract.md), and
[quickstart.md](quickstart.md)

## Phase 1: User Story 1 — Complete the RepoInfra gate through explicit delegation

**Goal**: Preserve the Python 3.9 outer RepoInfra gate while executing the
Raven contract exactly once under a proven Python 3.11+ interpreter.

**Round 2 correction**: The mandatory existing caller contract is a necessary
in-scope adaptation: only its literal launcher-prefix assertion joins the
allowlist; every other assertion remains unchanged.

**Independent Test**: A normal commit containing only the four allowed files
invokes the resolver-selected RepoInfra gate; the outer 3.9 process delegates
both Raven entrypoints, focused fail-closed regressions pass, the real caller
reaches its watchdog, and the existing nested-hook path terminates.

- [ ] **T001 [US1]** Add the shared Raven Python 3.11+ adapter, route the existing caller and contract wrapper through it, add focused regressions, and update only the existing caller-prefix source assertion in `scripts/ci/review-python311`, `scripts/ci/codex-review.sh`, `scripts/ci/tests/test_review_raven.py`, and `scripts/ci/tests/review_raven_contract.py`.

| Metadata | T001 |
|---|---|
| Owning layer / context | **RepoInfra** — `CONTEXT.md → scripts/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `scripts/ci/review-python311` (new); `scripts/ci/codex-review.sh`; `scripts/ci/tests/test_review_raven.py`; `scripts/ci/tests/review_raven_contract.py` (caller-prefix source assertion only) |
| Files NOT to touch | `scripts/CONTEXT.md`; `scripts/ci/review-raven.py`; `scripts/ci/review-common.sh`; `scripts/ci/review_process_supervisor.py`; `scripts/ci/tests/test_review_shell.py`; `scripts/ci/raven-review-operations.md`; `scripts/context/**`; `scripts/hooks/**`; `.github/**`; `.specify/**`; `specs/**`; every product/data leaf |
| Interface / contract | [delegation-contract.md](contracts/delegation-contract.md): `review-python311 <python-script> [args...]` executes exact argv under probed Python 3.11+ or fails before the target. Wrapper contract argv remains `-B review_raven_contract.py`; caller helper/argv remain unchanged behind the same watchdog. The existing caller-contract source assertion must require the adapter prefix; every other assertion remains byte-for-byte unchanged. |
| Functional acceptance | Satisfies FR-001–FR-008 and US1/AC1–US1/AC4. Probe `python3` first and use it only at 3.11+; otherwise resolve and prove `python3.11`; missing/unexecutable/old/timeout/non-zero selection and target failure all fail without skip/target retry/fallback. Python 3.9 never imports the delegated module or `tomllib`. Preserve exact argv, capture, 90-second wrapper timeout, provider-neutral behavior, caller isolation, read-only/never-approval settings, caller watchdog, all non-prefix contract assertions, and nested-hook behavior. |
| Exact verification | No proactive suite. Normal `git commit` and `git push` with configured hooks must report a clean routing audit and zero-exit hook-selected RepoInfra local gate. `git diff --name-only` must contain exactly the four allowed implementation/test paths. CI reruns RepoInfra under Python 3.13. Exact-SHA implementation review must PASS before push. |
| Dependencies / slice | No implementation predecessor inside this repair; approved base `c1f6ea8ec4a41a1993591fd454aafdae08194358`; serves US1 only. T022 retry is a post-landing Team Lead action, not a task edge. |

## Dependency Graph

```text
T001
```

No task is parallelized. T001 is independently schedulable and owns one leaf,
four files, one internal interface, and one hook-driven verification path.

## Acceptance Coverage

| Acceptance | Task |
|---|---|
| US1/AC1, FR-001–FR-003 | T001 |
| US1/AC2, FR-002 | T001 |
| US1/AC3, FR-004, FR-006 | T001 |
| US1/AC4, FR-005–FR-007 | T001 |
| FR-008, SC-003–SC-004 | T001 |
