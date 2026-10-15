# Contract: Acceptance-to-Task Matrix

Every acceptance row is stable and mapped exactly once. “Fixture” means injected canned CLI/file input. Only T004 reads a real configured environment.

## User-story acceptance (18)

| Acceptance | Owning task | Required proof |
|---|---|---|
| US1/AC1 old-issue new run | T002 | agent-task fixture persists it independent of issue watermark |
| US1/AC2 non-terminal through terminal | T002 | two-pass queued/running/unknown → terminal plus pending state |
| US1/AC3 absence + lifecycle sanitizer | T002 | null/no-fallback assertions; field-by-field DTO/raw/normalized sentinels |
| US1/AC4 empty Copilot run/runtime usage | T002; T004 | empty fixtures; persisted live wrapper with no invented value |
| US2/AC1 incremental message sequence | T002 | `--since`, overlap, and new-sequence fixtures |
| US2/AC2 hash/length only | T002 | canonical vectors and serialized sentinel absence |
| US2/AC3 first pre-hash match | T001; T002 | ordered dual-match DTO fixture |
| US2/AC4 four token-aware rules | T001; T002 | positive + two near misses per rule |
| US2/AC5 replay without duplicate/gap | T002 | stable `(run_id, sequence)` fixtures |
| US3/AC1 replay-safe change-only snapshot | T002 | unchanged + `A→B→A` + pending-B/crash/source-C exact replay |
| US3/AC2 exact runtime usage/activity | T002; T004 | exact/empty fixtures and live wrapper sample |
| US3/AC3 timeline/truncation | T002 | activity vector, overlap, event/collection keys, empty truncation |
| US3/AC4 PR candidate provenance only | T002 | valid/repeated/malformed/sentinel fixtures |
| US3/AC5 existing cadence produces eight | T001–T004 | registration, runner equality, eight nonzero live samples |
| US4/AC1 complete/partial line cursor | T002 | partial tail emits only after completion |
| US4/AC2 rotate/truncate generation | T002 | generation/reset/replay identities |
| US4/AC3 allowlisted OTel projection | T001; T002 | fixed neutral-slot validation + serialized prohibited-sentinel absence |
| US4/AC4 future window join only | T002 | shared conversation/disjoint windows remain unassigned |

## Functional requirements (15)

| Requirement | Owning task | Required proof |
|---|---|---|
| RH-L1-001 cadence + L1-only source | T001; T002; T003 | `SOURCES` registration, no-op normalize/no DB, runner equality, no downstream diff |
| RH-L1-002 per-agent discovery | T001; T002 | neutral config + old-issue fixture |
| RH-L1-003 lifecycle/pending/sanitizer | T002 | terminal/unknown transitions and raw+normalized privacy fixtures |
| RH-L1-004 messages by run/sequence | T002 | incremental overlap/replay |
| RH-L1-005 canonical hash/length | T002 | vectors and serialized sentinel test |
| RH-L1-006 ordered red-line rules | T001; T002 | defaults, positives, near misses, order |
| RH-L1-007 transition snapshots | T002 | complete pending projection, `A→B→A`, pending-B/crash/source-C retry |
| RH-L1-008 runtime exact/empty | T002; T004 | empty/exact fixtures and persisted live wrapper |
| RH-L1-009 timeline overlap/truncation | T002 | command vector, state, marker, stderr classification |
| RH-L1-010 PR-link provenance/privacy | T002 | strict extraction and sentinel fixtures |
| RH-L1-011 compatibility | T002 | existing normalize/issue/comment/GitHub tests active |
| RH-L1-012 read-only + hermetic CI | T002 | prefix rejection, no-live-call/path spy |
| RH-L1-013 eight nonzero rows/samples | T004 | sanitized prepublication table; zero blocks |
| RH-L1-014 offset/partial/replay/no L2 | T001; T002 | binary file-state fixtures, no-op normalize/no clean DB |
| RH-L1-015 OTel allowlist/window sufficiency | T001; T002 | fixed-slot rejection, projection/privacy, and ambiguous-window fixtures |

## Success criteria (9)

| Criterion | Owning task | Required proof |
|---|---|---|
| SC-001 old-issue + lifecycle closure | T002 | run fixtures |
| SC-002 zero secret/private bytes | T002 | message + lifecycle raw/normalized serialized capture |
| SC-003 red-line positives/near misses | T002 | parameterized matcher fixtures |
| SC-004 empty usage remains empty | T002; T004 | fixtures + live wrapper sample |
| SC-005 stable replay/no gaps | T002 | all family identities/cursors plus exact pending-projection retry |
| SC-006 approved commands/hermetic CI | T002 | command/path spies |
| SC-007 privacy-safe eight-family live evidence | T004 | nonzero table in fixed-candidate review package |
| SC-008 OTel offset correctness | T002 | complete/partial/resume/rotate/truncate fixtures |
| SC-009 OTel privacy/window preservation | T001; T002 | neutral-slot rejection + allowlist sentinels + shared-session window fixture |

## Scope invariants

| Invariant | Enforced by |
|---|---|
| Tracked config has no real IDs/paths | T001 tests and final diff scan |
| Lifecycle text sanitized before DTO/write | T002 raw + normalized sentinel tests |
| Message/tool/OTel payloads projected before persistence | T002 DTO and serialized sentinels |
| Red-line match precedes hashing | T002 ordered helper fixture |
| State advances after write; complete snapshot pending is retry-stable | T002 pending-B/crash/source-C fixture |
| Unknown run status stays pending | T002 terminal-allowlist fixture |
| Empty usage is not zero | T002 fixtures; T004 wrapper sample |
| Timeline truncation is not completeness | T002 collection-marker fixture |
| OTel is L1-only, deterministic, no AI | T001 registration, T002 no-op normalize, no downstream diff |
| Existing timer; registered source wired | T003 runner + existing equality test |
| Evidence precedes review; publication follows PASS | T004 review/publication receipts |
| Installed runner sync is post-merge authorized ops | T003 external handoff, no prepublication host mutation |

Coverage result: **42/42 mapped** (18 US + 15 RH-L1 + 9 SC); zero unresolved row.
