# Contract: Acceptance-to-Task Matrix

Every acceptance row is stable and must remain mapped during implementation review. “Fixture” always means an injected canned response; only T003 contacts a real configured Multica environment.

## User-story acceptance

| Acceptance | Owning task | Required proof |
|---|---|---|
| US1/AC1 new run on an issue below the former watermark | T002 | Old-issue/new-agent-task fixture persists the run |
| US1/AC2 non-terminal re-read through final state | T002 | Two-pass queued/running → completed/failed/cancelled fixtures and pending-state assertions |
| US1/AC3 absent queue/failure/cancel/model/usage facts remain absent | T002 | Projection fixture asserts null/omission and no fallback |
| US1/AC4 empty Copilot run/runtime usage stays empty | T002; live confirmation T003 when observed | Empty-list fixtures; sanitized live evidence without fabricated tokens/model |
| US2/AC1 incremental messages by run/sequence | T002 | `--since` call and new-sequence fixtures |
| US2/AC2 hash/length only, zero raw content | T002 | Canonical SHA-256 vectors and serialized secret-sentinel absence |
| US2/AC3 first configured match occurs before hashing | T001 config; T002 matcher | Ordered dual-match fixture and persistence DTO assertion |
| US2/AC4 all four initial rules are token-aware | T001 config; T002 matcher | Positive plus at least two near-miss fixtures per rule |
| US2/AC5 overlap replay has no duplicate/gap | T002 | Replayed sequence fixture with stable `(run_id, sequence)` keys |
| US3/AC1 change-only agent snapshot | T002 | unchanged/change/absent-value fixture sequence |
| US3/AC2 runtime usage/activity exact, including empty | T002 | Exact-payload and empty-usage fixtures |
| US3/AC3 activity-only timeline, idempotency, truncation | T002 | CLI-vector, overlap/replay, event/collection-key, empty-truncated-response, and successful-stderr fixtures |
| US3/AC4 issue/comment PR candidate with provenance only | T002 | Repeated valid URL, query/fragment, malformed/non-PR, and sentinel fixtures |
| US3/AC5 existing schedule produces all families | T002 wiring; T003 live proof | Registry/runner unchanged plus seven-family sanitized evidence |

## Functional requirements

| Requirement | Owning task | Required proof |
|---|---|---|
| RH-L0-001 existing schedule, raw-only boundary | T002 | No registry/runner/schema/downstream diff; existing runner-source test |
| RH-L0-002 per-agent discovery catches old-issue new run | T001 config; T002 collection | Config default/override test and old-issue fixture |
| RH-L0-003 stable run, pending revisit, lifecycle fields, explicit terminal set | T002 | State-transition, unknown-status, projection, replay fixtures |
| RH-L0-004 messages keyed by `(run_id, sequence)` | T002 | Incremental/overlap/replay fixtures |
| RH-L0-005 canonical SHA-256/byte length, no raw content | T002 | Known hash vectors and secret-sentinel serialized-output test |
| RH-L0-006 configured ordered pre-hash red-line rules | T001; T002 | Exact defaults plus positive/near-miss/order fixtures |
| RH-L0-007 change-only agent snapshots | T002 | Canonical config-hash fixtures |
| RH-L0-008 runtime usage/activity; no Copilot fabrication | T002; evidence T003 | Empty/exact payload fixtures and live sanitized observation when available |
| RH-L0-009 issue timeline with cursor overlap/truncation | T002 | Activity-only vector, per-issue state, same-time overlap, collection marker, stderr classification |
| RH-L0-010 issue/comment PR candidates with provenance | T002 | Strict URL/provenance/privacy fixtures |
| RH-L0-011 existing consumers remain compatible | T002 | Existing normalize/issue/comment/GitHub PR tests unmodified and passing |
| RH-L0-012 read-only CLI and fixture-only CI | T002 | Prefix rejection before subprocess and no-live-call spy |
| RH-L0-013 real local count/sample per raw family | T003 | Sanitized seven-family handoff table |

## Success criteria

| Criterion | Owning task | Required proof |
|---|---|---|
| SC-001 old-issue discovery and lifecycle closure | T002 | Run fixtures |
| SC-002 zero secret sentinel bytes | T002 | Serialized DTO/raw-write capture |
| SC-003 positive + two near misses per rule | T002 | Parameterized matcher fixtures |
| SC-004 empty usage with no invented values | T002; T003 if observed | Empty Copilot fixtures and sanitized live evidence |
| SC-005 replay stability/no gaps | T002 | Stable-key and cursor overlap fixtures across all raw families |
| SC-006 approved commands only, zero live CI calls | T002 | Command spy and mutation rejection fixtures |
| SC-007 privacy-safe real local evidence | T003 | Handoff table following `quickstart.md` |

## Scope invariants

| Invariant | Enforced by |
|---|---|
| Tracked configuration contains no real identifiers | T001 allowlist, config tests, final diff scan |
| Agent/task/message payloads are projected before `write_raw` | T002 DTO construction and sentinel tests |
| Red-line matching precedes input hashing | T002 ordered helper call and dual-match fixture |
| State advances only after successful persistence | T002 write-failure fixtures |
| Unknown status remains pending | T002 explicit terminal allowlist fixture |
| Empty usage is not zero usage | T002 null/empty fixtures; T003 honest sample |
| Timeline truncation is not full history | T002 successful-stderr metadata fixture |
| No new scheduled or normalized source | T002 changed-path review and existing registry test |
| No implementation change during evidence capture | T003 zero tracked-file diff |

Coverage result: **100% mapped; zero unresolved acceptance row**.
