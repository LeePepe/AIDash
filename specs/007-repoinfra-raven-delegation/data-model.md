# Data Model: RepoInfra Raven Interpreter Delegation

This repair changes no persisted or product-domain data. The following values
are transient process state used to make the delegation contract explicit.

## Interpreter Candidate

| Field | Meaning | Invariant |
|---|---|---|
| `command` | Executable path used for Raven Python work | Probed `python3` when 3.11+, otherwise probed `python3.11` |
| `origin` | `python3` or `python3.11` | Exactly one compatible command executes the target |
| `version_proven` | Result of the bounded version probe | Must prove at least 3.11 before contract execution |

## Delegated Contract Result

| Field | Meaning | Invariant |
|---|---|---|
| `returncode` | Contract subprocess status | Zero is the only passing value |
| `stdout` / `stderr` | Captured diagnostics | Preserved for the existing assertion; no credentials are introduced or inspected |
| `duration` | Bounded process lifetime | Version probe is bounded; contract retains its 90-second timeout |

## State Transitions

```text
outer wrapper
  ├─ current >= 3.11 ───────────────┐
  └─ current < 3.11 → lookup → probe├→ run contract once → pass/fail
                       └─ any failure└→ fail closed
```

There is no persisted state, migration, cache, retry counter, environment
mutation, or provider state.
