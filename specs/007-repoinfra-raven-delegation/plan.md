# Implementation Plan: RepoInfra Raven Interpreter Delegation

**Branch**: `007-repoinfra-raven-delegation` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: MY-1746 at approved base
`c1f6ea8ec4a41a1993591fd454aafdae08194358`.

## Summary

Add one deep internal RepoInfra module, `scripts/ci/review-python311`, as the
shared compatibility seam for the Raven test wrapper and production caller.
It executes the supplied Python script and exact argv through a probed
Python 3.11+ command, or fails closed. The wrapper remains importable under the
documented Python 3.9 outer gate; the caller stays inside its existing
watchdog. The Raven helper and production review policy modules remain
no-touch; the caller contract changes only its launcher-prefix assertion.

## Technical Context

**Language/Version**: Outer Python 3.9.6; delegated contract Python 3.11+;
CI Python 3.13
**Primary Dependencies**: POSIX shell plus Python standard library
(`pathlib`, `subprocess`, `unittest`); no new package
**Storage**: N/A
**Testing**: Existing resolver-selected RepoInfra pytest gate through normal
commit/push hooks; focused `unittest` cases live in the changed wrapper
**Target Platform**: macOS local hook runner and GitHub Actions RepoInfra job
**Project Type**: Repository automation compatibility repair
**Performance Goals**: One bounded interpreter probe and one existing bounded
contract process; no retry loop
**Constraints**: Fail closed; no host/toolchain/configuration mutation; no
manual suite repetition; exact four-file implementation/test allowlist
**Scale/Scope**: One RepoInfra implementation task, one adapter, one caller
line, one focused test wrapper, and one caller-contract source assertion

## Constitution Check

### Before design

- **Spec-driven**: PASS — dedicated Spec Kit package with stable FR and AC IDs.
- **Single owning leaf**: PASS — resolver classifies all four implementation
  and test paths as RepoInfra through `CONTEXT.md → scripts/CONTEXT.md`.
- **Scope discipline**: PASS — exact four-file allowlist; likely drift targets
  are explicit no-touch paths.
- **Gate preservation**: PASS — outer command and all mandatory gates remain.
- **Test ownership**: PASS — verification is hook-driven; no local host App
  test or proactive duplicate pytest run is planned.
- **Identity/privacy**: PASS — no credentials, identity, provider state, or
  user data enters source, fixtures, or output.
- **Dependencies**: PASS — standard library only; no ADR or package change.

### After design

PASS with no constitutional exception. The interface is intentionally deep:
callers ask for one compatible interpreter or receive one compatibility
failure; discovery, version proof, and diagnostics stay local to the wrapper.
No new public seam, package, or configuration surface is introduced.

## Project Structure

### Documentation (this feature)

```text
specs/007-repoinfra-raven-delegation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   └── delegation-contract.md
├── quickstart.md
├── tasks.md
└── checklists/
    └── requirements.md
```

### Implementation

```text
scripts/ci/
├── review-python311       # shared fail-closed interpreter adapter (new)
├── codex-review.sh        # same helper/argv/watchdog; adapter prefix only
└── tests/
    ├── test_review_raven.py  # outer-3.9 invocation + adapter regressions
    └── review_raven_contract.py  # caller-prefix assertion only
```

**Structure Decision**: Put interpreter selection behind one executable
adapter used by both callers. This avoids duplicated selection logic, keeps
`review-raven.py` untouched, preserves caller/watchdog locality, and gives the
outer-compatible wrapper a deterministic regression surface.

## Design

### Interpreter-adapter interface

`review-python311 <python-script> [args...]` is the only new interface.

1. Reject a missing script argument.
2. If `python3` is present and a version probe proves 3.11+, `exec` that
   command with the supplied argv unchanged.
3. Otherwise resolve `python3.11`; require the same 3.11+ proof, then `exec`
   it with the supplied argv unchanged.
4. If lookup, spawn, or proof fails for both candidates, emit one sanitized
   compatibility diagnostic and exit non-zero without running the target.
5. Do not source shell state, inspect credentials, mutate `PATH`, install a
   dependency, retry the target, or print its arguments.

The wrapper calls the adapter as
`review-python311 -B review_raven_contract.py`; its existing 90-second timeout
bounds adapter selection and contract execution. The production caller calls
`review-python311 review-raven.py <existing argv>` inside the unchanged
`run_with_timeout` invocation, so the watchdog continues to bound selection,
helper import, and Codex execution as one process group.

### Preserved contracts

`contracts/delegation-contract.md` freezes the unchanged outer command,
adapter matrix, delegated invocations, and no-touch behavior. The existing
caller-contract source assertion changes only from the literal Python prefix
to the adapter prefix; its provider, argv, isolation, read-only/never-approval,
and watchdog assertions stay intact. Existing timeout, nested-hook, and
result-schema regressions continue to prove the production surfaces; this task
does not duplicate or relocate them.

## Dependencies and Completion Conditions

- **Input dependency**: immutable base
  `c1f6ea8ec4a41a1993591fd454aafdae08194358`.
- **Task graph**: T001 only; no parallel or downstream task inside this repair.
- **Completion**: T001 implementation diff stays within its allowlist; normal
  commit and push hooks pass; exact-SHA implementation review passes before
  publication; CI then reruns the RepoInfra gate under Python 3.13.
- **After landing**: Team Lead may retry the separately reviewed T022 tree
  through normal hooks. This plan neither performs that retry nor promotes
  T023.

## Complexity Tracking

No constitution violation or complexity exception.
