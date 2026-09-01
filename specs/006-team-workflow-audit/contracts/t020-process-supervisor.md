# T020 Process Supervisor Contract

## Purpose and trust boundary

`run_with_timeout` supervises one trusted reviewer CLI invocation on macOS and
Linux. Pull-request code is not checked out or executed. The supervisor must
clean the invocation's complete descendant tree within the trusted reviewer
CLI boundary without ever attributing an unrelated system process by
executable name, `PPID=1`, process age, or resemblance to an orphan.

The caller-facing interface remains:

```text
run_with_timeout <positive-seconds> <command> [args...]
```

Callers retain the existing stdout, stderr, stdin, exit-status, sticky-comment,
and 900-second configuration behavior. The shell function is a thin Bash
3.2-compatible adapter to `scripts/ci/review_process_supervisor.py`; no caller
learns the internal tracking interface.

## Invocation ownership

Before target code can run, the supervisor MUST:

1. create an unguessable invocation capability that is present only in the
   target environment;
2. prepare output relays and the Darwin/Linux membership adapter;
3. launch the target in a new session behind a release barrier;
4. record the root `ProcessIdentity(pid, birthMarker)`; and
5. set one absolute monotonic deadline immediately before releasing the target.

A process may enter the invocation ledger only when at least one positive proof
holds:

- its exact parent identity is already in the ledger;
- it is a verified member of the still-owned root process group and was born
  after launch; or
- it carries the exact target-only invocation capability inherited across
  normal fork, exec, `setsid`, and reparenting.

The implementation MAY enumerate same-user processes to resolve the exact
invocation capability. That is capability-scoped membership, not global orphan
discovery. It MUST NOT admit a process because it has `PPID=1`, has its own
PGID, matches `bash|sh|python|sleep|node`, or appeared recently.

Ledger identity is the pair `(pid, birthMarker)`, using Linux `/proc` start
ticks and Darwin process birth metadata. Second-resolution `ps lstart` alone is
insufficient. Reparenting or a PGID change never removes an admitted identity.
Every individual or group signal revalidates ownership and the birth marker;
PID or PGID reuse MUST NOT be signalled.

## Outcome ordering

One state machine owns launch, leader completion, the absolute deadline,
membership, output relays, and cleanup.

- The leader completion timestamp is recorded at the wait/SIGCHLD event.
- A completion at or before the deadline retains the leader's real status only
  after cleanup is proven complete.
- Once the deadline wins, the terminal result is fixed at 124. A TERM handler
  that later exits 0 cannot overwrite it.
- Adapter startup, membership, identity, relay, signalling, or cleanup-proof
  failure returns reserved supervisor status 125 and MUST NOT return the
  leader's success.
- The timeout budget classifies leader completion only. Bounded cleanup after a
  pre-deadline completion does not convert success into 124.

## Cleanup

Cleanup runs after both leader completion and timeout:

1. refresh capability/ancestry-proven membership;
2. TERM verified members, including out-of-PGID identities;
3. continue admitting only positively proven descendants during the existing
   bounded grace period;
4. KILL every surviving exact identity;
5. reap the leader and internal children, drain relays to EOF, and prove no
   live non-zombie ledger member remains; and
6. remove private state in a `finally` path.

If quiescence cannot be proven, the supervisor fails closed. It never falls
back to a name-based or global-orphan kill.

For a valid call, the result table is exact: a pre-deadline leader returns its
real status after proven cleanup; an elapsed deadline returns 124; and an
internal supervision/cleanup-proof failure returns 125. Existing callers
already treat every nonzero result as a merge-blocking tool failure and retain
their special timeout diagnostic for 124.

## Internal adapters

`review_process_supervisor.py` owns a small internal membership/clock seam with
real Darwin and Linux adapters plus a deterministic scripted test adapter. It
uses the repository-supported Python standard library only. No dependency,
routing, workflow, ruleset, timeout-budget, or reviewer-verdict change is
authorized.

The trusted reviewer CLI and its normal descendants are expected to preserve
the inherited capability. Deliberate anti-supervision that strips ownership
evidence while escaping the process group is outside this trusted-command
boundary; uncertainty still fails closed and never authorizes an ambiguous
signal.

## Required proof surface

`scripts/ci/tests/test_review_shell.py` MUST cover the public shell interface
and scripted internal adapter through observable outcomes:

- fast success and ordinary nonzero status;
- true deadline and TERM-trap exit-zero returning 124;
- a zero-sleep leader that spawns a PID-confirmed `setsid` descendant and exits
  0, with real status retained only after descendant and inherited-pipe cleanup;
- nested `env -> bash -> child`, TERM-resistant, and spawn-during-cleanup trees;
- an unrelated simultaneous orphan-shaped shell/Python/Node/sleep process
  surviving untouched;
- concurrent invocations never cross-signalling;
- reparented ledger identities retained through KILL;
- PID/birth-marker reuse never signalled;
- pre-deadline, post-deadline, and tie ordering against a scripted clock;
- membership/inspection/cleanup-proof failures returning 125 rather than
  leader success;
- caller continuation and diagnostic behavior under `bash -e`; and
- the existing no-heredoc source check and 900-second default unchanged.

Tests use readiness pipes/files or the scripted adapter for ordering. Sleeps
may represent the timeout itself but MUST NOT be the synchronization mechanism
for the fast-leader or reparenting proofs.
