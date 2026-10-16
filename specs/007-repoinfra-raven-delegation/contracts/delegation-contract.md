# Raven Contract Delegation Contract

## Outer Interface

The RepoInfra local gate remains:

```text
/usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q
```

The outer interpreter may be Python 3.9 and must be able to collect and run
`scripts/ci/tests/test_review_raven.py` without importing `tomllib`,
`review-raven.py`, or `review_raven_contract.py`.

## Adapter Interface

```text
scripts/ci/review-python311 <python-script> [args...]
```

The adapter forwards the script and arguments unchanged and never prints them.

## Selection Matrix

| Current interpreter | Candidate state | Required outcome |
|---|---|---|
| `python3` proves 3.11+ | N/A | Execute the target through `python3` |
| `python3` is older | `python3.11` exists and proves 3.11+ | Execute the target through resolved `python3.11` |
| Neither command proves 3.11+ | Missing/unexecutable/too old | Fail with a sanitized compatibility error before target execution |

There is no unqualified-`python3` fallback, skip, dependency installation,
host mutation, alternate TOML parser, or retry.

## Delegated Invocation

The wrapper executes exactly one offline contract process with equivalent
argv:

```text
scripts/ci/review-python311 -B scripts/ci/tests/review_raven_contract.py
```

Capture text stdout/stderr, retain the existing 90-second timeout, and require
exit code zero. A spawn error, timeout, or non-zero exit is a gate failure.

The production caller keeps the same helper and all existing arguments, but
replaces only its interpreter prefix:

```text
scripts/ci/review-python311 scripts/ci/review-raven.py <existing-caller-argv>
```

That invocation remains inside the existing `run_with_timeout` call.

The mandatory source contract in
`scripts/ci/tests/review_raven_contract.py` must replace only its literal
`python3` launcher-prefix expectation with the adapter prefix shown above.
Its helper and argv, isolated review home, read-only/never-approval settings,
provider-neutral behavior, and watchdog assertions remain unchanged.

## Preserved Interfaces

The following files and their interfaces are unchanged by implementation:

- `scripts/ci/review-raven.py`
- `scripts/ci/review-common.sh`
- `scripts/ci/review_process_supervisor.py`
- `scripts/ci/tests/test_review_shell.py`
- `scripts/context/**`, `scripts/hooks/**`, `.github/**`

Consequently provider selection remains neutral, review-home isolation remains
authoritative, caller argv and read-only/never-approval settings remain exact,
and watchdog/nested-hook behavior stays fail-closed.
