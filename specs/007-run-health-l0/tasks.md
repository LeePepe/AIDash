# Tasks: Dev Team Run-Health L0 Collection

**Input**: Design documents from `specs/007-run-health-l0/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/l0-records.md`, `contracts/acceptance-matrix.md`, `quickstart.md`

**Tests**: Fixture, privacy, compatibility, and read-only tests are mandatory because RH-L0-002 through RH-L0-012 explicitly require machine-verifiable behavior. The real local collection in T003 is acceptance evidence, never CI.

**Organization**: T001 and T002 are dependency-ordered, layer-scoped implementation slices in one PR. T003 is a no-code evidence gate after both commits. Do not combine Foundation and Adapter changes into one commit.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other tasks marked [P] after dependencies are satisfied.
- **[Story]**: Primary user story; task acceptance can cover supporting requirements from other stories.
- Every implementation task names an exact file allowlist.

## Phase 1: AidataFoundation configuration

**Purpose**: Establish neutral configuration contracts before adapters consume them.

- [ ] **T001 [US1] Add neutral run-health collection configuration and owned tests.**

  **Owning layer / commit**: `AidataFoundation`; one independent commit before T002.

  **Files in scope** (PR may only modify these for T001):
  - `aidata/config.py`
  - `aidata/config_local.example.py`
  - `aidata/tests/test_config_multica.py`

  **Files NOT to touch** (touching = constitutional 🔴 FAIL):
  - `aidata/config_local.py` (ignored machine-private state; never commit)
  - `aidata/adapters/**` (owned by T002)
  - `aidata/scripts/aidata_digest_run.sh` (existing schedule remains unchanged)
  - `aidata/schema/**`, `aidata/L4_serve/**`, `aidata/L5_apps/**`, `Packages/**`

  **Functional acceptance**:
  - Add empty typed `MULTICA_RUN_AGENTS` default containing `(workspace_id, agent_id)` pairs only when locally overridden; no real identifier appears in tracked files.
  - Add ordered `MULTICA_RED_LINE_RULES` with exact identifiers `gh_pr_merge_bypass`, `force_push_protected`, `no_verify`, `admin_flag` in that priority order.
  - Add `MULTICA_PROTECTED_BRANCHES` defaults `main`/`master` and `MULTICA_GH_MERGE_BYPASS_FLAGS` default `--admin`.
  - Extend the local example with placeholder-only documentation for all four values and preserve no-config degrade-to-zero behavior.
  - Tests assert exact defaults/order, local override compatibility, and absence of any real workspace/agent/runtime/email value.
  - Satisfies the configuration portions of RH-L0-002, RH-L0-006, RH-L0-007, RH-L0-008, and RH-L0-012.

  **Quality bars** (apply automatically — do not restate):
  Constitution §“Cross-Cutting Quality Bars” all sections.

  **Dependencies**: None.

  **Commit checkpoint**: Commit only the three allowed files. Normal pre-commit hooks must select and pass the `AidataFoundation` local gate before T002 begins.

---

## Phase 2: AidataL1L2 collection slice

**Purpose**: Deliver all seven raw families through the existing scheduled adapters while preserving current normalized consumers.

- [ ] **T002 [US1] Implement complete privacy-safe run-health raw collection with canned contract tests.**

  **Owning layer / commit**: `AidataL1L2`; one dependent commit after T001.

  **Files in scope** (PR may only modify these for T002):
  - `aidata/adapters/_multica.py`
  - `aidata/adapters/_multica_l0.py` (new)
  - `aidata/adapters/multica_run.py`
  - `aidata/adapters/multica_issue.py`
  - `aidata/adapters/multica_comment.py`
  - `aidata/tests/test_multica_shared.py`
  - `aidata/tests/test_multica_run_collect.py`
  - `aidata/tests/test_multica_issue_collect.py`
  - `aidata/tests/test_multica_comment_adapter.py`

  **Files NOT to touch** (touching = constitutional 🔴 FAIL):
  - `aidata/config.py`, `aidata/config_local.example.py`, `aidata/tests/test_config_multica.py` (owned and committed by T001)
  - `aidata/rawio.py`, `aidata/state.py`, `aidata/cleanio.py` (reuse existing contracts)
  - `aidata/scripts/aidata_digest_run.sh`, `aidata/tests/test_runner_sources.py` (schedule stays unchanged; existing test is verification only)
  - `aidata/schema/**`, `aidata/L4_serve/**`, `aidata/L5_apps/**`, `Packages/**`
  - `specs/007-run-health-l0/**` (reviewed planning authority, not implementation scope)

  **Functional acceptance**:
  - Extend `_multica.py` with the exact read-only prefix allowlist from `contracts/l0-records.md`; reject an unlisted prefix before subprocess launch, preserve current `run_json` caller behavior, and expose classified successful-stderr metadata needed for timeline truncation.
  - Add `_multica_l0.py` pure helpers for canonical UTF-8 bytes, full lowercase SHA-256 and byte length, ordered token-aware red-line matching, strict PR URL extraction, stable derived identities, and persistence DTO construction. Raw message/tool fields cannot appear in returned DTOs.
  - Replace issue-number run discovery with configured `agent tasks` reads, documented-cursor pagination, explicit incomplete bare-list handling, per-agent discovery state, and pending non-terminal re-reads. A fixture must discover a new run on an old issue; queued/running/unknown fixtures must remain pending until a later completed/failed/cancelled observation is successfully persisted.
  - Project task payloads before `write_raw`. Preserve source queue timestamps, `failure_reason`, `cancelled_by`, usage, and usage-supplied run model. Preserve current `multica_run.normalize()` schema/behavior and any compatible per-issue usage enrichment, but never use issues to discover or filter runs.
  - Collect `multica_run_message` incrementally by `(run_id, sequence)` with replay overlap. Run red-line matching before input hashing; persist only metadata, hashes, lengths, and first matched rule identifier. Secret-sentinel serialized-output tests must prove no raw body/input/output or whole source object survives.
  - Collect change-only `multica_agent_snapshot` records and de-duplicate calls for repeated configured agents/runtimes.
  - Collect `multica_runtime_usage` and `multica_runtime_activity` exactly as supplied with provenance. Copilot fixtures with empty run and runtime usage must remain empty and must contain no fabricated zero token, cost, or fallback model.
  - Extend `multica_issue` with per-issue activity-only timeline backfill/incremental overlap, stable event identity, and one stable per-response collection marker that preserves classified truncation metadata even for an empty response; extend issue/comment adapters with provenance-bearing `multica_issue_pr_link` extraction that stores no surrounding content.
  - All new test responses are canned/injected. A subprocess spy proves fixture tests make no live call and mutation commands cannot launch. Replay tests prove stable identities/no gaps. Existing collection, normalization, no-config, and runner-source tests remain active and unweakened.
  - Satisfies RH-L0-001 through RH-L0-012 and every US1/US2/US3 acceptance scenario except the live evidence in RH-L0-013.

  **Quality bars** (apply automatically — do not restate):
  Constitution §“Cross-Cutting Quality Bars” all sections.

  **Dependencies**: T001 (hard; import the committed configuration contract).

  **Commit checkpoint**: Commit only the nine allowed files. Normal pre-commit hooks must select and pass the `AidataL1L2` local gate. Do not manually repeat the full aidata suite.

---

## Phase 3: Acceptance evidence and handoff

**Purpose**: Prove real CLI wiring once without turning remote state into a test dependency.

- [ ] **T003 [US3] Capture sanitized real-local collection and exact-revision handoff evidence.**

  **Files in scope**:
  - None. This task produces Multica/PR handoff evidence only.

  **Files NOT to touch** (touching = constitutional 🔴 FAIL):
  - Every tracked repository file
  - `aidata/config_local.py` except an already-authorized local-only configuration value change that remains ignored and absent from every diff/evidence sample
  - Machine-global Python, Git, cron, or Multica configuration

  **Functional acceptance**:
  - After T001 and T002 hooks succeed, run the existing `multica_issue`, `multica_comment`, and `multica_run` collect entry points once with authorized local configuration; do not add a live test, new schedule, or mutation command.
  - Report a logical row count for each of `multica_run`, `multica_run_message`, `multica_agent_snapshot`, `multica_runtime_usage`, `multica_runtime_activity`, `multica_issue_timeline`, and `multica_issue_pr_link`.
  - Include at most one sanitized sample per non-empty family following `quickstart.md`: replace machine-local IDs, retain only allowed field names/values, and expose no raw message/tool content, email, private metadata, local path, or CLI stderr. A zero-row family reports zero and reason without a fabricated sample.
  - Explicitly identify any truthful empty Copilot usage observation and confirm no model/token value was substituted.
  - Confirm `config_local.py`, source registries, cron runner, normalized schemas, L3/L4/L5, and UI are absent from the diff.
  - Capture exact local HEAD and verify it byte-for-byte against the pushed branch and PR `headRefOid` before independent implementation review.
  - Satisfies RH-L0-013 and SC-007.

  **Quality bars** (apply automatically — do not restate):
  Constitution §“Cross-Cutting Quality Bars” all sections.

  **Dependencies**: T002 (hard), successful normal commit/push hooks (hard), authorized local Multica configuration (hard).

## Dependencies & Execution Order

```text
T001 AidataFoundation configuration
  └──> T002 AidataL1L2 collection + fixture proof
         └──> T003 real-local sanitized evidence + SHA handoff
```

- T001 and T002 are deliberately serial because the adapter imports the configuration contract.
- T002 may implement run/message work and timeline/PR work in parallel internally only if one owner preserves the single `AidataL1L2` commit and fixed candidate tree.
- T003 changes no tracked source and begins only after the two implementation commits and their normal hook evidence exist.
- The feature is one PR/goal. Do not create separate PRs for raw families.

## Verification Map

| Gate | Owner | Evidence |
|---|---|---|
| Foundation defaults/override privacy | T001 | `test_config_multica.py`; Foundation hook |
| Read-only CLI + successful stderr | T002 | `test_multica_shared.py`; Adapter hook |
| Run discovery/lifecycle/compatibility | T002 | `test_multica_run_collect.py` plus existing normalize assertions |
| Hash/privacy/rules/agent/runtime | T002 | `test_multica_shared.py` and run fixtures |
| Timeline and metadata PR candidates | T002 | `test_multica_issue_collect.py` |
| Comment PR candidates | T002 | `test_multica_comment_adapter.py` |
| Schedule unchanged | T002 verification | existing `test_runner_sources.py`; changed-path review |
| Real seven-family wiring | T003 | sanitized local evidence |
| Published revision identity | T003 | local HEAD = remote branch SHA = PR `headRefOid` |

## Definition of Done

- T001 and T002 each remain within their exact file allowlist and are separate layer-scoped commits in one PR.
- Normal commit/push hooks select the affected leaf gates and report success; no suite is manually repeated and no verification flag is bypassed.
- CI uses fixtures only and the implementation introduces no live Multica dependency.
- Every RH-L0 requirement and user-story acceptance scenario maps to an implementation task in `contracts/acceptance-matrix.md` with no uncovered row.
- The seven-family real-local evidence is privacy-safe and truthful about zero rows, empty usage, pagination incompleteness, and timeline truncation.
- No raw message body, tool input, tool output, whole agent-task payload, machine-local identifier, or `config_local.py` enters the published diff.
- Existing schedule, clean schemas, warehouse, queries, digest, cards, and UI are unchanged.
- Exact implementation SHA matches local HEAD, pushed branch, and PR head before independent review.
- Team Lead uses the exact planning commit that received AI Reviewer PASS as the implementation base, or an explicitly approved descendant with all planning artifact blobs byte-identical.
