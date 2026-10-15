# Feature Specification: RepoInfra Raven Interpreter Delegation

**Feature Branch**: `007-repoinfra-raven-delegation`
**Created**: 2026-10-15
**Status**: Ready for spec-gate review
**Input**: MY-1746 and Owner-delegated decision A in MY-1503 comment `01a139a8-a34a-7e30-91b2-393f6e389fb6`

## Existing Behaviour

The RepoInfra local gate deliberately starts pytest with `/usr/bin/python3`,
which is Python 3.9.6 on the supported local runner. Both the Raven test wrapper
and the production caller then start `review-raven.py` work with the
unqualified command `python3`. On that runner the command resolves back to
Python 3.9.6; importing `review-raven.py` therefore fails at its top-level
`tomllib` import before either the offline contract or caller watchdog runs.

The outer hook fails closed. The production review launcher, caller isolation,
watchdog, provider-neutral configuration, result validation, and nested-hook
contracts are already implemented and independently covered.

## User Scenarios & Testing

### User Story 1 - Complete the RepoInfra gate through explicit delegation (Priority: P1)

As a repository contributor, I need the documented Python 3.9 RepoInfra gate
to delegate only its Raven contract to an available Python 3.11+ interpreter,
so normal hooks can finish without weakening any review or hook invariant.

**Why this priority**: The current interpreter loop blocks every normal
RepoInfra publication path, including the reviewed T022 retry.

**Independent Test**: Stage only the four allowed RepoInfra files and use a
normal commit. The resolver-selected RepoInfra gate must begin under the
unchanged Python 3.9 entrypoint, route both the offline contract and real
caller through one shared Python 3.11+ adapter, and finish through the existing
hook path. No proactive pytest run is part of acceptance.

**Acceptance Scenarios**:

1. **US1/AC1** — Given the outer interpreter is Python 3.9 and `python3`
   resolves to that same interpreter, when either Raven entrypoint invokes the
   shared adapter, then it selects an available, probed `python3.11` and the
   outer interpreter never imports `tomllib`.
2. **US1/AC2** — Given `python3` already proves Python 3.11 or newer, when the
   shared adapter runs, then it executes through that command and does not
   introduce a second delegation hop.
3. **US1/AC3** — Given no compatible delegated interpreter exists, or the
   candidate cannot prove Python 3.11+, when selection runs, then the adapter
   fails with an actionable compatibility error; it never skips, falls back to
   Python 3.9, starts Codex, or reports success.
4. **US1/AC4** — Given a selected interpreter whose Raven contract exits
   non-zero or times out, when the wrapper executes it, then the existing
   assertion/timeout path remains fail-closed and reports captured output.

### Edge Cases

- `python3` and `/usr/bin/python3` are both Python 3.9.
- `python3.11` is absent, is not executable, reports an older version, or its
  version probe times out.
- The delegated contract exits non-zero, emits only stderr, or exceeds the
  existing 90-second bound; the real caller exceeds its existing watchdog.
- The full RepoInfra gate is reached through the existing nested-hook
  regression; delegation must not add recursion, environment mutation, or a
  second gate invocation.

## Requirements

### Functional Requirements

- **FR-001**: The RepoInfra local gate MUST retain `/usr/bin/python3 -m pytest
  scripts/ci/tests scripts/context/tests -q` as its outer entrypoint.
- **FR-002**: One RepoInfra adapter MUST accept a Python script plus exact argv,
  execute them with `python3` when that command proves Python 3.11+, otherwise
  execute them with a probed `python3.11` from `PATH`, and fail if neither
  candidate proves compatible.
- **FR-003**: Both the Raven test wrapper and `codex-review.sh` MUST invoke the
  shared adapter. Python 3.9 MUST NOT import `review-raven.py`, `tomllib`, or
  the delegated contract module.
- **FR-004**: A missing, unexecutable, too-old, or failed interpreter probe
  MUST fail closed with no skip, compatibility shim, dependency installation,
  host mutation, or fallback parser.
- **FR-005**: Wrapper execution MUST preserve the existing `-B` invocation,
  captured stdout/stderr, 90-second timeout, and non-zero-result assertion.
  Caller execution MUST preserve all existing argv and remain inside the
  unchanged `run_with_timeout` watchdog.
- **FR-006**: Focused tests in the wrapper MUST prove both adapter branches,
  exact argv forwarding, and missing/incompatible delegation failures without
  importing Python-3.11-only modules under the outer interpreter. The existing
  caller-contract regression MUST update only its literal launcher-prefix
  assertion to require the adapter; all of its helper/argv, isolation,
  read-only/never-approval, provider-neutral, and watchdog assertions, plus
  every nested-hook regression, MUST remain unchanged and passing.
- **FR-007**: The change MUST remain provider-neutral and MUST NOT read,
  inspect, inject, log, or mutate credentials, review-home state, provider
  configuration, caller arguments, or model policy.
- **FR-008**: Implementation MUST modify only `scripts/ci/review-python311`
  (new), `scripts/ci/codex-review.sh`,
  `scripts/ci/tests/test_review_raven.py`, and
  `scripts/ci/tests/review_raven_contract.py`. The caller change is limited to
  the interpreter prefix, and the existing caller-contract change is limited
  to the exact source assertion for that prefix. Every Raven helper, watchdog,
  other contract assertion, hook, resolver, workflow, and MY-1503/T022
  planning artifact is out of scope.

### Key Entities

No persisted or product-domain entity changes. The only transient concepts
are an interpreter candidate, its version-probe result, and the delegated
contract process result; they are described in `data-model.md`.

## Compatibility

- The outer Python 3.9 gate and RepoInfra ownership remain unchanged.
- Python 3.11+ and CI Python 3.13 continue to reuse their current executable.
- The production `review-raven.py` interface stays byte-for-byte outside the
  implementation scope. `codex-review.sh` changes only its interpreter prefix;
  caller argv, isolation, output handling, and watchdog remain unchanged.
- Provider neutrality, sanitized fail-closed launcher errors, read-only and
  never-approval arguments, watchdog timeout, nested-hook recursion guard,
  and PATH preservation remain governed by their existing tests.
- No product behavior, stored data, public interface, host configuration, or
  toolchain installation changes.

## Removed Behaviour

None. No test, gate, caller path, timeout, provider, or compatibility behavior
may be removed or weakened. The accidental Python-3.9-to-Python-3.9 delegation
loop is a defect, not an accepted behavior.

## Non-Goals

- Changing `scripts/CONTEXT.md`, any hook, workflow, runner image, host PATH,
  Python installation, or package dependency.
- Editing the Raven helper, watchdog implementation, review-contract behavior
  or any contract assertion other than the caller's literal launcher prefix,
  provider setup, credential handling, or any caller behavior beyond routing
  the same helper and argv through the shared adapter.
- Changing AIDash product behavior or any non-RepoInfra leaf.
- Mutating the reviewed MY-1503/T022 tree, promoting T023, or retrying T022
  before this separate repair lands.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The normal resolver-selected RepoInfra local gate completes from
  its Python 3.9 outer entrypoint on the approved runner with zero `tomllib`
  import under that interpreter.
- **SC-002**: Focused regression cases deterministically cover current-3.11+,
  delegated-3.9, missing candidate, incompatible candidate, and failed
  contract outcomes.
- **SC-003**: Git diff contains exactly the four allowed RepoInfra
  implementation/test files. The caller-contract launcher-prefix assertion
  requires the adapter, every other existing assertion is unchanged, and no
  test is removed or weakened.
- **SC-004**: Normal commit and push hooks pass without `--no-verify`; CI
  remains authoritative for its Python 3.13 RepoInfra rerun.

## Assumptions

- Approved implementation base is
  `c1f6ea8ec4a41a1993591fd454aafdae08194358`.
- The local runner already provides `python3.11` 3.11.17; using it requires no
  host or toolchain change.
- MY-1692's PR #199 has landed and MY-1698 is cancelled, superseding the stale
  dependency wording in the original MY-1746 body.
