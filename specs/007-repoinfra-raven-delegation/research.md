# Research: RepoInfra Raven Interpreter Delegation

## R-001 — Root cause

**Decision**: Treat interpreter selection shared by the wrapper and production
caller as the compatibility seam. The outer RepoInfra gate, Raven helper, and
watchdog implementation are not the repair seam.

**Evidence**:

- `scripts/CONTEXT.md` fixes the local gate at `/usr/bin/python3 -m pytest ...`.
- On the approved runner `/usr/bin/python3` and unqualified `python3` are both
  3.9.6; `tomllib` is absent.
- The wrapper and production caller invoke Raven work through unqualified
  `python3`, which returns to 3.9.6.
- The delegated contract imports `review-raven.py`; that module imports
  `tomllib` at top level.
- An existing `python3.11` is available at version 3.11.17.

## R-002 — Delegation strategy

**Decision**: Add one executable `review-python311` adapter. It probes
`python3`, uses it when it is 3.11+, otherwise probes `python3.11`, then
executes the supplied Python script and exact argv. Use no target retry or
alternative parser.

**Rationale**: This makes the smallest interface deterministic on local and CI
runners, avoids the known unqualified-`python3` loop, and proves rather than
assumes the delegated interpreter contract.

**Rejected alternatives**:

- Change the outer RepoInfra gate to Python 3.11+: violates Owner decision A
  and the documented compatibility contract.
- Add `tomli` or another dependency: changes the toolchain and dependency
  posture for a standard-library-only repository gate.
- Guard or reimplement TOML parsing in Python 3.9: duplicates production
  behavior and weakens the authorized 3.11+ delegation.
- Duplicate selection independently in the wrapper and caller: creates two
  shallow interfaces that can drift and leaves no single regression seam.
- Hard-code `/opt/homebrew/bin/python3`: binds the contract to one host layout;
  the already-installed versioned command is the narrower interface.

## R-003 — Fail-closed proof

**Decision**: Missing lookup, failed spawn, timeout, non-zero probe, too-old
version, contract non-zero, and contract timeout all remain failures. No case
may call `skipTest`, fall back to Python 3.9, install tooling, or report success.

**Rationale**: The hook is a mandatory gate. Compatibility failure is evidence
that the contract did not run, not evidence that the contract can be waived.

## R-004 — Scope and ownership

**Decision**: One RepoInfra task may modify only the new
`scripts/ci/review-python311`, the interpreter prefix in
`scripts/ci/codex-review.sh`, focused coverage in
`scripts/ci/tests/test_review_raven.py`, and the single caller-prefix source
assertion in `scripts/ci/tests/review_raven_contract.py`.

**Evidence**: The resolver maps the path through
`CONTEXT.md → scripts/CONTEXT.md` to RepoInfra. The mandatory caller contract
pins the old literal launcher, so that assertion must move atomically with the
caller prefix; its provider neutrality, isolated review home, caller arguments,
watchdog, terminal schema, nested-hook recursion guard, and PATH preservation
assertions remain unchanged.

## R-005 — Verification

**Decision**: Use normal commit and push hooks as the only local verification;
do not proactively invoke pytest.

**Rationale**: `AGENTS.md`, `CLAUDE.md`, and the constitution require
resolver-driven hook verification and forbid redundant manual suites. The
planning package is validated separately with Spec Kit freshness, routing,
and diff checks.
