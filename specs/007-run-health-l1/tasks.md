# Tasks: Dev Team Run-Health L1 Collection

**Input**: Design documents from `specs/007-run-health-l1/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/l1-records.md`, `contracts/acceptance-matrix.md`, `quickstart.md`

**Tests**: Fixture, privacy, compatibility, read-only, offset, and replay tests are mandatory for RH-L1-002 through RH-L1-015. T004's real local collection is prepublication acceptance evidence, never CI.

**Organization**: T001–T003 are dependency-ordered, layer-scoped commits in one PR. T004 changes no tracked file: it freezes the candidate plus sanitized live evidence for independent review, then publishes only after PASS. Do not combine layer commits.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel only when dependencies and file ownership permit.
- **[Story]**: Primary user story; task acceptance can cover supporting requirements.
- Every implementation task has one owning layer and an exact file allowlist.

## Phase 1: AidataFoundation configuration and registration

- [ ] **T001 [US1] Add neutral run-health/OTel configuration and register the L1 source.**

  **Owning layer / commit**: `AidataFoundation`; first independent commit.

  **Files in scope**:
  - `aidata/config.py`
  - `aidata/config_local.example.py`
  - `aidata/tests/test_config_multica.py`

  **Files NOT to touch**:
  - `aidata/config_local.py`
  - `aidata/adapters/**`, `aidata/CONTEXT.md`
  - `aidata/scripts/**`
  - `aidata/schema/**`, `aidata/L4_serve/**`, `aidata/L5_apps/**`, `Packages/**`

  **Functional acceptance**:
  - Add empty typed `MULTICA_RUN_AGENTS` `(workspace_id, agent_id)` pairs, tracked `COPILOT_OTEL_SOURCE_SLOTS = (fullstack, pr-manager)`, and empty typed `COPILOT_OTEL_STREAMS` `(source_slot, local_path)` pairs; real IDs/paths exist only in ignored local config, and unknown/duplicate slots fail before file access.
  - Add ordered `MULTICA_RED_LINE_RULES = (gh_pr_merge_bypass, force_push_protected, no_verify, admin_flag)`, protected branches `main/master`, and merge-bypass flag `--admin`.
  - Register `copilot_otel` exactly once in `SOURCES`; keep it absent from `MERGE_SOURCES` and preserve all other source order/membership.
  - The example uses neutral placeholders only. Tests assert exact defaults/order/registration, local override shape, and zero real identity/path/email values.
  - No configuration returns zero without error.
  - Covers the configuration/registration portions of RH-L1-001, RH-L1-002, RH-L1-006, RH-L1-007, RH-L1-008, RH-L1-012, RH-L1-014, and RH-L1-015.

  **Dependencies**: None.

  **Commit checkpoint**: Commit only these three files; normal pre-commit hooks must select and pass `AidataFoundation`.

## Phase 2: AidataL1L2 collection contracts

- [ ] **T002 [US1] Implement privacy-safe Multica repair and the registered Copilot OTel L1 adapter.**

  **Owning layer / commit**: `AidataL1L2`; one dependent commit after T001.

  **Files in scope**:
  - `aidata/CONTEXT.md`
  - `aidata/adapters/CONTEXT.md`
  - `aidata/adapters/_multica.py`
  - `aidata/adapters/_multica_l1.py` (new)
  - `aidata/adapters/multica_run.py`
  - `aidata/adapters/multica_issue.py`
  - `aidata/adapters/multica_comment.py`
  - `aidata/adapters/copilot_otel.py` (new)
  - `aidata/tests/test_multica_shared.py`
  - `aidata/tests/test_multica_run_collect.py`
  - `aidata/tests/test_multica_issue_collect.py`
  - `aidata/tests/test_multica_comment_adapter.py`
  - `aidata/tests/test_copilot_otel_adapter.py` (new)

  **Files NOT to touch**:
  - T001 files
  - `aidata/rawio.py`, `aidata/state.py`, `aidata/cleanio.py`
  - `aidata/scripts/**`, `aidata/tests/test_runner_sources.py`
  - `aidata/schema/**`, `aidata/L4_serve/**`, `aidata/L5_apps/**`, `Packages/**`
  - `specs/007-run-health-l1/**`

  **Functional acceptance — Multica and privacy**:
  - `_multica.py` enforces the exact read-only prefix allowlist before subprocess launch, preserves existing `run_json`, and exposes classified successful-stderr facts for timeline truncation.
  - `_multica_l1.py` owns canonical bytes/hash/length, deterministic lifecycle sanitizer, ordered token-aware red-line matching, strict PR extraction, stable identities, and DTO constructors. `rawio` redaction remains defense-in-depth.
  - Lifecycle sanitizer covers `failure_reason`, `trigger_summary`, and `error` in contract order. Fixtures assert sentinels are absent in DTOs, serialized raw rows, and normalized compatibility rows while keys/string-null shapes remain unchanged; cancellation stores stable actor ID only.
  - Replace issue-number run discovery with paged `agent tasks`, explicit incomplete-page handling, and pending non-terminal re-reads. Old-issue/new-run, queued/running/unknown → terminal, write failure, replay, empty facts, and no-inference fixtures pass.
  - Messages are incremental/idempotent by `(run_id, sequence)` and retain only metadata, hashes, byte lengths, and first pre-hash rule ID. Each initial rule has positive and at least two near-miss fixtures; no raw message/tool field survives.
  - Agent snapshots use durable pending `(ordinal, config_hash, first_observed_at, canonical_allowed_projection)` plus committed state, and build retry rows only from pending. Fixtures cover `A → B → A`, unchanged replay, write failure, and `pending B → crash → live source C → retry B with its exact key/time/values → then persist C`.
  - Runtime usage/activity preserve exact payloads. Empty Copilot usage creates a truthful observation wrapper and never receives invented model/token/cost values.
  - Issue timelines use `--activity-only`, overlap, stable events, and an every-response collection marker that preserves empty truncation. Issue/comment PR candidates retain provenance without surrounding content.

  **Functional acceptance — Copilot OTel**:
  - `copilot_otel.collect()` reads configured slots in binary with `{device,inode,generation,offset}` state. It consumes only newline-terminated records; partial tails retain their starting offset; rotation/truncation increments generation and restarts at zero.
  - Observation identity hashes source slot, generation, line-start offset, and canonical allowed projection. Only chat operation timestamps, conversation ID, model, five verified token counters, neutral slot/key provenance, and `observed_at` persist.
  - Response IDs, `github.copilot.context.*`, content, arbitrary attributes/resources/events, whole spans, file paths, and offset internals never persist. Sentinel fixtures inspect serialized output.
  - Missing files/config degrade to zero. Unknown, duplicate, or non-neutral slots fail before file access/persistence. Complete malformed/non-chat lines can advance. Selected rows advance offset only after successful persistence.
  - `normalize() -> 0` creates no clean DB; source is absent from merge. Same-conversation/disjoint-window fixtures retain timestamps but perform no run attribution, leaving zero/multiple future matches unresolved.
  - Update both routing manifests so the new test resolves uniquely to `AidataL1L2`; `scripts/context/audit` stays clean.
  - All responses/files in automated tests are injected fixtures; a spy proves no live Multica call or private configured path read.
  - Covers RH-L1-002 through RH-L1-012 and RH-L1-014 through RH-L1-015; T004 owns RH-L1-013.

  **Dependencies**: T001.

  **Commit checkpoint**: Commit only the 13 allowed files; normal pre-commit hooks must select and pass `AidataL1L2`.

## Phase 3: AidataOps cadence wiring

- [ ] **T003 [US4] Wire `copilot_otel` into the existing daily repository runner.**

  **Owning layer / commit**: `AidataOps`; one dependent commit after T001–T002.

  **Files in scope**:
  - `aidata/scripts/aidata_digest_run.sh`

  **Files NOT to touch**:
  - Every T001/T002 file
  - `aidata/tests/test_runner_sources.py` (existing verifier; run through hook, do not weaken)
  - Machine-installed `~/.hermes/scripts/aidata_digest_run.sh` (never deploy an unreviewed candidate)

  **Functional acceptance**:
  - Add `copilot_otel` once to the existing `SOURCES="..."` list without adding/reordering timers or changing collect → normalize → merge → digest flow.
  - Existing `test_runner_sources.py` proves exact equality with `config.SOURCES`; the OTel no-op normalizer keeps the normalize pass successful without L2 output.
  - Record an external post-merge handoff: authorized operations sync the merged repository runner to the installed Hermes copy through the documented seam. This code PR neither deploys nor claims that host mutation.
  - Covers RH-L1-001 and the cadence portion of US3/AC5.

  **Dependencies**: T001 and T002.

  **Commit checkpoint**: Commit only the runner; normal pre-commit hooks must select and pass `AidataOps`.

## Phase 4: Fixed-candidate acceptance, review, and publication

- [ ] **T004 [US3] Prove all eight families, obtain prepublication PASS, then publish the reviewed SHA.**

  **Files in scope**: None; evidence/handoff only.

  **Files NOT to touch**:
  - Every tracked repository file
  - `aidata/config_local.py` except already-authorized ignored values that stay absent from diffs/evidence
  - Machine-global Python, Git, cron, Multica, or installed Hermes configuration

  **Prepublication acceptance**:
  - After T001–T003 local commits and commit-hook success, run authorized local collection for `multica_issue`, `multica_comment`, `multica_run`, and `copilot_otel`.
  - Report at least one persisted logical row and exactly one sanitized sample for each family: `multica_run`, `multica_run_message`, `multica_agent_snapshot`, `multica_runtime_usage`, `multica_runtime_activity`, `multica_issue_timeline`, `multica_issue_pr_link`, and `copilot_otel`. Any zero-row family blocks RH-L1-013; do not fabricate data.
  - The runtime-usage sample may truthfully contain empty usage, but the wrapper row must exist. OTel evidence retains allowed timestamps/conversation/model/token fields only. Replace local IDs; expose no raw content, email, private metadata, local path, stderr, or configured value.
  - Freeze the local candidate HEAD/tree and include changed-path/three-commit manifest, hook evidence, privacy assertions, and the eight-family table in the independent AI Reviewer package. Request explicit PASS/publication permission before any push or PR creation/update.

  **Post-PASS publication**:
  - If review changes any tracked byte or candidate SHA, repeat prepublication review. Otherwise run the normal pre-push hook, push only the reviewed SHA, and create/update the non-Draft PR.
  - Capture the exact local HEAD and verify byte-for-byte equality with the remote branch SHA and PR `headRefOid`; this proof occurs after publication, never before review.
  - Confirm `config_local.py`, normalized schemas/output, `MERGE_SOURCES`, L3/L4/L5, Swift packages, and UI are absent from the diff.
  - Covers RH-L1-013 and SC-007.

  **Dependencies**: T003, authorized local configuration, local commit-hook success, then independent prepublication PASS before push/PR.

## Dependencies & execution order

```text
T001 AidataFoundation config/source registration
  └──> T002 AidataL1L2 Multica + OTel implementation/fixtures
         └──> T003 AidataOps existing-cadence wiring
                └──> T004 local eight-family evidence + fixed candidate
                       └──> AI Reviewer PASS/publication permission
                              └──> push + non-Draft PR + SHA equality proof
```

## Verification map

| Gate | Owner | Evidence |
|---|---|---|
| Config privacy/registration/no-merge | T001 | `test_config_multica.py`; Foundation hook |
| Read-only CLI, sanitizer, red-lines | T002 | shared/run fixtures; serialized raw + normalized sentinel proof |
| Run lifecycle and snapshot replay | T002 | old-issue, pending, `A→B→A`, failure/crash retry fixtures |
| Timeline/PR candidates | T002 | issue/comment fixtures |
| OTel offset/projection/no-op normalize | T002 | complete/partial/resume/rotate/truncate/privacy/window fixtures |
| Routing uniqueness | T002 | `scripts/context/audit` |
| Existing daily cadence | T003 | unchanged runner structure + existing registry equality test |
| Eight nonzero families | T004 | sanitized prepublication evidence table |
| Publication identity | T004 | post-PASS local HEAD = remote branch = PR head |

## Definition of Done

- T001–T003 stay within exact allowlists as three layer-scoped commits in one PR; no test is removed, skipped, or weakened.
- Normal commit hooks and, only after prepublication PASS, the pre-push hook report success without bypass or redundant manual full-suite runs.
- Every one of the 42 acceptance IDs (18 US, 15 RH-L1, 9 SC) maps to a task with no uncovered row.
- All eight real-local families have a persisted row and privacy-safe sample; zero rows fail acceptance and empty usage remains truthful.
- No raw message/tool/lifecycle/OTel prohibited content, local identity/path, or ignored config enters the published diff/evidence.
- `copilot_otel` is registered on the existing cadence, has no clean/merge/downstream consumer, and later run attribution remains out of scope.
- Independent review precedes publication; only the reviewed SHA is pushed and post-publication local/remote/PR equality is proven.
- Team Lead uses the exact planning commit that receives AI Reviewer PASS as the implementation base, or an explicitly approved descendant with byte-identical reviewed planning artifacts.
