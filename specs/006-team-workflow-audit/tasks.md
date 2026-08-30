# Tasks: On-Demand Team Workflow Audit

**Input**: Design documents in `specs/006-team-workflow-audit/`

**Organization**: Each user-story phase is a vertical product slice. Every
executable row owns one resolver layer; cross-layer behavior is locked by the
contracts and blocking edges below. Constitution §Cross-Cutting Quality Bars
applies to every task.

## Phase 0: Recovery publication and compatibility gates

**Goal**: Publish the reviewed planning/constitution package under its required
PR contract, first repair the baseline RepoInfra gate in its own PR, and make
the existing AIDashUI CardType consumers forward-compatible before AIDashCore
introduces the eleventh case.

- [ ] **T020 [POLISH]** Repair timeout process-tree cleanup in `scripts/ci/review-common.sh`.

| Metadata | T020 |
|---|---|
| Owning layer / context | **RepoInfra** — CONTEXT.md → scripts/CONTEXT.md; root tech-context.md |
| Files in scope | `scripts/ci/review-common.sh`; `scripts/ci/tests/test_review_shell.py` |
| Files NOT to touch | .specify/**; specs/**; AGENTS.md; Packages/**; Apps/**; CLI/**; aidata/**; .github/workflows/**; rulesets; context routing; reviewer trust/verdict semantics; timeout budget |
| Authorized base / review surface | Base is exact synchronized main `2c75188c010ded876e9f3bb62412f011c7b9da14`. Candidate HEAD MUST differ from the base; its committed three-dot surface MUST include `scripts/ci/review-common.sh` and MAY additionally include only `scripts/ci/tests/test_review_shell.py`. Base-equals-head, local-only, or unpublished candidates are not deliveries. |
| Interface / contract | Preserve `run_with_timeout`'s leader exit status and fail-closed deadline semantics while terminating the complete descendant process tree and closing inherited output pipes |
| Baseline failure evidence | The T020 blobs are unchanged from planning fixed point `d8f156bf...`. A fresh normal macOS pre-commit gate reproduced `test_run_with_timeout_cleans_up_descendants_after_leader_exits_zero`: descendant cleanup completed but `run_with_timeout` returned 124 instead of the leader's 0, and the nested RepoInfra gate failed. The prior current-main no-change implementation review was INCONCLUSIVE because its surface was empty. |
| Functional acceptance | Fast success and ordinary failure return their real status; deadline returns 124; `bash -e` callers emit the fail-closed diagnostic; TERM→KILL removes `env → bash → child` descendants; leader-exits-zero with lingering descendants cleans promptly and returns 0 on both macOS and Linux; TERM-trapping leaders cannot hide a timeout; no PID or stdout/stderr pipe leaks; existing sticky-comment/security/900-second semantics are unchanged |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected RepoInfra syntax plus `/usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q` must exit 0; CI `review-gate (pytest)` must pass; local HEAD, remote task ref, and PR `headRefOid` must be equal; exact-SHA implementation review must PASS before merge |
| Dependencies / slice | None; first recovery gate and hard prerequisite for T021. Preserve the existing T020 workspace and PR #202; do not transplant PR #202 or unrelated historical patches. Team Lead owns redispatch, merge acceptance, Stage 1 closure, and Stage 2 promotion. |

- [ ] **T021 [POLISH]** Publish the exact reviewed planning and constitution amendment.

| Metadata | T021 |
|---|---|
| Owning layer / context | **RepoInfra planning-only** — CONTEXT.md → scripts/CONTEXT.md; .specify/memory/constitution.md Governance |
| Files in scope | `.specify/feature.json`; `.specify/memory/constitution.md`; `AGENTS.md` (managed Spec Kit marker only); `specs/006-team-workflow-audit/spec.md`; `specs/006-team-workflow-audit/plan.md`; `specs/006-team-workflow-audit/research.md`; `specs/006-team-workflow-audit/data-model.md`; `specs/006-team-workflow-audit/quickstart.md`; `specs/006-team-workflow-audit/tasks.md`; `specs/006-team-workflow-audit/checklists/requirements.md`; `specs/006-team-workflow-audit/contracts/card-payload.md`; `specs/006-team-workflow-audit/contracts/manual-import.md`; `specs/006-team-workflow-audit/contracts/owner-decision-events.md`; `specs/006-team-workflow-audit/contracts/t005-acceptance-matrix.md` |
| Files NOT to touch | Packages/**; Apps/**; CLI/**; aidata/**; scripts/ci/review-common.sh; any PR #202 branch/workspace file |
| Interface / contract | Planning/constitution-only PR from Team Lead's approved main lineage; title exactly `constitution: authorize team audit decision receipts`; PR body repeats the 1.13.0 in-flight migration note |
| Functional acceptance | PR surface is exactly the reviewed planning artifact set; constitution is 1.13.0; body states existing events remain valid, new actions are additive, unknown consumers preserve or visibly ignore them, and audit invocation/remediation remain outside AIDash; local/remote/PR SHA pin is exact; no product/watchdog implementation appears |
| Exact verification | Normal `git commit` and `git push` with configured hooks; Spec Kit prerequisites, routing/frontmatter/task-freshness checks selected by RepoInfra must exit 0; constitution PR metadata is part of acceptance |
| Dependencies / slice | Exact-revision planning review PASS and T020; recovery publication gate for T019, T005, and later audit-action work |

- [ ] **T019 [US1]** Prepare AIDashUI CardType switches for a future Core enum case.

| Metadata | T019 |
|---|---|
| Owning layer / context | **AIDashUI** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashUI/CONTEXT.md; Packages/AIDashUI/tech-context.md |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/DesignTokens.swift`; `Packages/AIDashUI/Tests/AIDashUITests/CardRouterTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/DesignTokensComplianceTests.swift` |
| Files NOT to touch | Packages/AIDashCore/**; Packages/DesignKit/**; Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift; TeamAuditCardView.swift; Apps/**; CLI/**; aidata/** |
| Interface / contract | Existing imported `CardType` switches have an explicit future-case fallback that preserves current mappings and generic-card behavior; this task does not add or render `teamAudit` |
| Functional acceptance | All ten current CardType symbol/classification/payload-name mappings remain exact; a future imported enum case compiles through the documented fallback until T008 adds the explicit renderer; tests/helpers do not reintroduce exhaustive future-case failure; no visual token or current renderer behavior changes |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashUI Swift build/test gates must exit 0; required repository-wide CI build remains green |
| Dependencies / slice | T021; merge-before prerequisite for T005; US1 expand step |

## Phase 1: User Story 1 — Read a trustworthy snapshot (P1 / MVP)

**Goal**: Explicitly import a baseline or incremental snapshot and display its
scope, provenance, limitations, three core axes, and separate Task
Effectiveness in today's briefing.

**Independent test**: Neutral baseline and incremental fixtures traverse the
manual import, immutable facts, named queries, bounded card mapping, and
overview renderer; default collection performs no audit import or invocation.

- [ ] **T001 [US1]** Add the manual-only source registry in `aidata/cli.py`, `aidata/config.py`, and `aidata/config_local.example.py`.

| Metadata | T001 |
|---|---|
| Owning layer / context | **AidataFoundation** — CONTEXT.md → aidata/CONTEXT.md → aidata/CONTEXT.foundation.md; aidata/tech-context.md |
| Files in scope | `aidata/cli.py`; `aidata/config.py`; `aidata/config_local.example.py`; `aidata/CONTEXT.md`; `aidata/CONTEXT.foundation.md`; `aidata/tests/test_team_audit_manual_source.py` |
| Files NOT to touch | aidata/scripts/**; aidata/adapters/**; aidata/schema/**; any cron or machine-local config |
| Interface / contract | `contracts/manual-import.md`: `MANUAL_SOURCES` is selectable only with explicit `--source`; default source iteration excludes it; empty ignored-local import root returns zero |
| Functional acceptance | Parser accepts `team_audit_snapshot` explicitly for collect/normalize; default collect/normalize never selects it; neutral default contains no identity/path; no schedule, subprocess, network, or audit invocation is introduced; new test path is routed to AidataFoundation |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataFoundation tests and the routing audit must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | None; US1 foundation |

### T002 contract-first repair graph

The former executable T002 is retired as a coordination anchor. Its
implementation scope is replaced by the serial T022–T026 graph below. No
Fullstack task owns the old monolithic surface, and downstream tasks consume
only T026's completed adapter interface.

- [ ] **T022 [US1]** Define the strict Team Audit decoder and immutable model seam in `aidata/adapters/team_audit_contract.py`.

| Metadata | T022 |
|---|---|
| Owning layer / context | **AidataL1L2** — CONTEXT.md → aidata/CONTEXT.md → aidata/adapters/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/adapters/team_audit_contract.py`; `aidata/tests/test_team_audit_contract.py`; `aidata/CONTEXT.md`; `aidata/adapters/CONTEXT.md` |
| Files NOT to touch | `aidata/adapters/team_audit_snapshot.py`; `aidata/adapters/team_audit_bundle.py`; `aidata/adapters/team_audit_index.py`; `aidata/adapters/fixtures/team_audit/**`; `aidata/tests/test_team_audit_adapter.py`; Foundation `state.py`/`rawio.py`/`cleanio.py`; config/CLI; schema/merge/L4/L5; scripts/cron; generated raw/clean data; Swift files |
| Interface / contract | `contracts/manual-import.md`, `contracts/t002-acceptance-matrix.md`, `contracts/l1l2-normalized-output.md`, and `data-model.md`: pure `decode_team_audit_bundle(snapshot_bytes, sidecar_bytes)` returns one immutable decoded bundle or structured rejection. The interface owns the only snapshot/sidecar schema validation, exact nested allowlists, locked enums, mode/count/referential invariants, exact byte hashes, and optional-link safety classification; it performs no filesystem, state, raw, clean, subprocess, or network I/O. |
| Functional acceptance | Valid baseline/incremental bytes decode without key aliases or fabrication; baseline cohort versus incremental cursor rules, UTC, instruction hashes, three reconciled core axes, separate Task Effectiveness, cases/events/attempts, explicit finding subject/responsibility, complete lineage/five-role repeats, sidecar parent/version/ID, mandatory typed artifacts, and optional grill fields are preserved exactly. Invalid mandatory artifact URLs, and invalid hashes, references, or counts, reject before raw storage; unknown/future keys or enums, generic body/payload/log fields at any typed level, and malformed UTF-8/JSON also reject. Unsafe optional artifact or grill URL strings do not reject: preserve the exact untrusted string and mark it `actionableHTTPS` only for HTTPS with a non-empty host, otherwise `nonActionable`; absent optional artifact URL is null/`absent`, and absent grill fields emit no link record. The two context files pre-register `test_team_audit_contract.py`, `test_team_audit_bundle.py`, `test_team_audit_index.py`, `test_team_audit_acceptance.py`, and `test_team_audit_adapter.py` for AidataL1L2 before later tasks create them. |
| Exact verification | Normal `git commit` and `git push` with `core.hooksPath=scripts/hooks`; pre-commit/pre-push must report a clean routing audit and a zero-exit hook-selected AidataL1L2 local gate. Both context indexes contain the complete five-test route set. A focused `scripts/context/run AidataL1L2 --mode local` rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T001; first node of the T002 repair graph; US1 import contract foundation and US2 evidence model |

- [ ] **T023 [US1]** Add the read-once atomic snapshot/sidecar filesystem adapter in `aidata/adapters/team_audit_bundle.py`.

| Metadata | T023 |
|---|---|
| Owning layer / context | **AidataL1L2** — CONTEXT.md → aidata/CONTEXT.md → aidata/adapters/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/adapters/team_audit_bundle.py`; `aidata/tests/test_team_audit_bundle.py` |
| Files NOT to touch | `aidata/CONTEXT.md` and `aidata/adapters/CONTEXT.md` (routes pre-registered by T022); `aidata/adapters/team_audit_contract.py` (T022); `aidata/adapters/team_audit_snapshot.py`; `aidata/adapters/team_audit_index.py`; production fixtures; `aidata/tests/test_team_audit_adapter.py`; Foundation/config/CLI; schema/merge/L4/L5; scripts/cron; generated data; Swift files |
| Interface / contract | `read_bundle(root, bundle_dir)` returns the exact `snapshot.json` and optional `artifacts.json` byte buffers, portable bundle identity, or a typed skip/rejection. It enumerates only immediate bundle directories, rejects symlinks/path escapes/extra JSON-like files, reads each accepted file once, and passes those same buffers to T022 for parsing and hashing. |
| Functional acceptance | Tests prove containment after resolution, regular-file enforcement, exact two-file shape for publishable input, deliberate missing-sidecar limitation input, same-buffer parse/hash behavior under replacement races, and graceful zero/skip on root/directory/file `OSError`, deletion, permission loss, malformed partial pairs, and empty/unconfigured roots. The module performs no raw/index/clean write and exposes no local absolute path as portable provenance. |
| Exact verification | Normal hook-running `git commit` and `git push`; routing audit and hook-selected AidataL1L2 tests must exit 0 using the route pre-registered by T022. A focused resolver rerun is diagnostic only after a hook failure. |
| Dependencies / slice | T022 hard; second node of the T002 repair graph; US1 atomic bundle read seam |

- [ ] **T024 [US1]** Implement the recoverable persisted identity/collision index in `aidata/adapters/team_audit_index.py`.

| Metadata | T024 |
|---|---|
| Owning layer / context | **AidataL1L2** — CONTEXT.md → aidata/CONTEXT.md → aidata/adapters/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/adapters/team_audit_index.py`; `aidata/tests/test_team_audit_index.py` |
| Files NOT to touch | `aidata/CONTEXT.md` and `aidata/adapters/CONTEXT.md` (routes pre-registered by T022); T022/T023 modules; `aidata/adapters/team_audit_snapshot.py`; production fixtures; `aidata/tests/test_team_audit_adapter.py`; Foundation `state.py`/`rawio.py`/`cleanio.py`; config/CLI; schema/merge/L4/L5; scripts/cron; generated data; Swift files |
| Interface / contract | `TeamAuditIdentityIndex.open(index_path, raw_history)` maintains a derived SQLite index at an injected git-ignored path; T026 supplies `raw_source_dir("team_audit_snapshot") / ".identity-index.sqlite"`, while tests supply `tmp_path`. `classify(decoded_bundle, observed_at)` returns an append-only import plan for snapshot, every stable child entity, and sidecar identities; `commit(import_plan)` atomically updates the cache only after the expected raw append succeeds. Raw history is authoritative: missing/corrupt/stale index state rebuilds from accepted raw records and body-free observations; the index never stores rejected content. |
| Functional acceptance | Across process restarts, same identity+hash is replay/no-op; same snapshot, sidecar, or child identity+different hash keeps the first accepted hash and returns a body-free `rejectedIdentityHashCollision` observation with entity kind, stable identity, accepted/rejected hashes, UTC time, portable source, limitation, and explicit accepted parent snapshot ID/hash. Observation IDs follow the normative SHA-256 tuple; the same observation ID is idempotent, distinct attempts remain append-only; overlap event IDs dedupe; failed/short raw writes do not commit; raw-ahead/index-behind and corrupt/index-ahead recovery converge without accepting a rejected body. |
| Exact verification | Normal hook-running `git commit` and `git push`; routing audit and hook-selected AidataL1L2 tests must exit 0 using the route pre-registered by T022. A focused resolver rerun is diagnostic only after a hook failure. |
| Dependencies / slice | T023 hard (and therefore T022); third node of the T002 repair graph; US1 persisted immutable-identity decision seam |

- [ ] **T025 [US1]** Add contract-valid neutral bundles and lock the full L1/L2 acceptance matrix.

| Metadata | T025 |
|---|---|
| Owning layer / context | **AidataL1L2** — CONTEXT.md → aidata/CONTEXT.md → aidata/adapters/CONTEXT.md; aidata/tech-context.md |
| Files in scope | neutral two-file bundles under `aidata/adapters/fixtures/team_audit/**`; `aidata/tests/test_team_audit_acceptance.py` |
| Files NOT to touch | `aidata/CONTEXT.md` and `aidata/adapters/CONTEXT.md` (routes pre-registered by T022); all production Python modules, including T022–T024 and `team_audit_snapshot.py`; `aidata/tests/test_team_audit_adapter.py`; `aidata/tests/fixtures/**` (AidataL5-owned); Foundation/config/CLI; schema/merge/L4/L5; scripts/cron; generated data; Swift files; planning contracts |
| Interface / contract | `contracts/t002-acceptance-matrix.md`: hermetic baseline and incremental directory bundles are the neutral source of truth. Matrix tests exercise the T022 decoder, T023 byte reader, and T024 restartable index only through their declared interfaces; implementation-private helpers are not a test surface. |
| Functional acceptance | Every matrix row assigned to T022–T025 passes: valid baseline/incremental preservation; all locked model/referential/sidecar/artifact cases; recursive raw-body/future-schema rejection; read-once/race/path/symlink/OSError behavior; cross-run snapshot/child/sidecar replay and collision; exact observation fields/IDs; overlap dedupe; missing-sidecar limitation; rejected-body absence; and zero subprocess/network/audit/dispatch/issue/run/source-mutation calls. Fixtures contain only invented neutral identities and valid 64-hex hashes. |
| Exact verification | Normal hook-running `git commit` and `git push`; routing audit and hook-selected AidataL1L2 tests must exit 0 using the matrix-test route pre-registered by T022. No production code exception is permitted in this fixture/test task. A focused resolver rerun is diagnostic only after a hook failure. |
| Dependencies / slice | T024 hard; fourth node of the T002 repair graph; US1/US2 contract proof before collector wiring |

- [ ] **T026 [US1]** Replace the monolith with thin collector/normalizer wiring in `aidata/adapters/team_audit_snapshot.py`.

| Metadata | T026 |
|---|---|
| Owning layer / context | **AidataL1L2** — CONTEXT.md → aidata/CONTEXT.md → aidata/adapters/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/adapters/team_audit_snapshot.py`; `aidata/tests/test_team_audit_adapter.py` |
| Files NOT to touch | `aidata/CONTEXT.md` and `aidata/adapters/CONTEXT.md` (routes owned by T022); T022–T024 production modules; T025 fixtures/matrix test; `aidata/tests/fixtures/**`; Foundation `state.py`/`rawio.py`/`cleanio.py`; config/CLI; schema/merge/L4/L5; scripts/cron; external audit sources; generated raw/clean data; Swift files |
| Interface / contract | Preserve public `collect() -> int` and `normalize() -> int`. The adapter composes T023 read-once buffers → T022 strict decode → T024 persisted classification before `rawio.write_raw`, then produces exactly the `team_audit_record` table defined by `contracts/l1l2-normalized-output.md` through `cleanio.write_clean`. Only accepted records and body-free observations normalize; no duplicate schema validator, fallback key alias, second file read, or in-memory-only identity map remains on the active path. |
| Functional acceptance | The existing manual CLI seam imports valid baseline/incremental bundles and returns exact accepted counts; replay returns zero; every rejected/colliding body is excluded before raw write; accepted raw data still passes the existing redaction helper. Clean output has the exact common columns, composite key, 24 locked record types/grains, canonical `record_json`, `entity_sha256`, snapshot/sidecar hashes and linkage, optional URL status, and collision key `(parentSnapshotID, observationID)` from `contracts/l1l2-normalized-output.md`; no legacy `snapshot`/`observation`/`sidecar` ad hoc table is part of the interface, and `normalize()` returns accepted snapshot-row count rather than total tagged rows. Missing/unreadable configuration degrades to zero; patched I/O is restored after tests; spies prove no subprocess/network/audit/dispatch/issue/run/source mutation. Wiring tests close the T026 rows of `contracts/t002-acceptance-matrix.md` without altering the previously passing module matrix. |
| Exact verification | Normal `git commit` and `git push` with configured hooks; pre-commit/pre-push must report a clean routing audit and zero-exit hook-selected AidataL1L2 local gate. A focused resolver rerun is diagnostic only after an emitted hook failure and never replaces the next normal hook run. |
| Dependencies / slice | T025 hard; final node of the T002 repair graph and sole dependency exposed to T003/T016 |

- [ ] **T003 [US1]** Add immutable Team Audit warehouse facts in `aidata/schema/warehouse.sql` and `aidata/merge.py`.

| Metadata | T003 |
|---|---|
| Owning layer / context | **AidataL3** — CONTEXT.md → aidata/CONTEXT.md → aidata/schema/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/schema/warehouse.sql`; `aidata/merge.py`; `aidata/tests/test_warehouse_integrity.py`; `aidata/tests/test_warehouse_quality.py` |
| Files NOT to touch | aidata/adapters/**; aidata/L4_serve/**; aidata/L5_apps/**; generated databases |
| Interface / contract | Consume only the `team_audit_record` table in `clean_path("team_audit_snapshot")`, as defined by `contracts/l1l2-normalized-output.md`; map its 24 locked record types one-to-one into the `data-model.md` warehouse grains/bridges. T003 does not read raw shards, the identity cache, or adapter-private models and does not infer a mapping for unknown record types. |
| Functional acceptance | T003 verifies the normalized common columns, composite key, canonical record JSON, accepted snapshot hash, sidecar nullability/linkage, and type-specific parent/stable identities before mapping. Merge produces one row per named grain/bridge; accepted facts never update; parented collision IDs merge independently; finding identity fields, full lineage/repeats, exact sidecar hash, artifact/grill sidecar foreign keys, and optional URL raw value/status round-trip unchanged; same sidecar ID/different hash observes a collision; unknown/foreign/mode/axis violations fabricate nothing; generated DB stays untracked. |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL3 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T026; US1 immutable warehouse |

- [ ] **T004 [US1]** Add overview and required-publication input queries under `aidata/L4_serve/queries/team-audit/`.

| Metadata | T004 |
|---|---|
| Owning layer / context | **AidataL4** — CONTEXT.md → aidata/CONTEXT.md → aidata/L4_serve/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/L4_serve/queries/team-audit/latest-snapshot.sql`; `aidata/L4_serve/queries/team-audit/axis-summary.sql`; `aidata/L4_serve/queries/team-audit/task-effectiveness.sql`; `aidata/L4_serve/queries/team-audit/required-publication-inputs.sql`; `aidata/L4_serve/queries/team-audit/mandatory-findings.sql`; `aidata/L4_serve/queries/team-audit/mandatory-artifacts.sql`; `aidata/L4_serve/queries/team-audit/import-collision-summary.sql`; `aidata/tests/test_query_tiers.py` |
| Files NOT to touch | aidata/schema/**; aidata/merge.py; aidata/L5_apps/**; any write path |
| Interface / contract | Named read-only bundles expose accepted snapshot/sidecar provenance, cohort/cursors, axes/effectiveness, collision summary, and required entity/count inputs including exact `requiredP0P1FindingCount` plus generic/team/P0/P1-artifact counts; L4 has no published/omitted/externalized result |
| Functional acceptance | Query grains are explicit; latest ordering is deterministic; finding subject/responsibility and parented collisions survive; sidecar ID/hash reaches every required input; `requiredP0P1FindingCount` derives from immutable mandatory-finding facts independently of chain counts; columns named `published*`, `omitted*`, or `externalized*` are absent; query fixtures cover zero/one/multiple required P0/P1 findings; empty warehouse returns an empty/degraded bundle |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL4 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T003; US1 query seam |

- [ ] **T005 [US1]** Define and validate `teamAudit` in `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`.

| Metadata | T005 |
|---|---|
| Owning layer / context | **AIDashCore** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashCore/CONTEXT.md; Packages/AIDashCore/tech-context.md |
| Files in scope | `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`; `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift` |
| Files NOT to touch | Packages/AIDashCore/Sources/AIDashCore/Models/UserEvent*.swift (T013); Packages/AIDashUI/**; Apps/**; CLI/** |
| Interface / contract | `contracts/card-payload.md`, `data-model.md`, and `contracts/t005-acceptance-matrix.md`: one `teamAudit` type, eight variants, complete public type surface, exact locked wire vocabulary, and semantic/referential/wire-byte validation |
| Functional acceptance | Every row of the T005 acceptance matrix passes: typed cohort/cases and evidence coverage; three locked axis verdicts plus separate reconciled Task Effectiveness; ordered embedded timeline events/attempts with case/role/cycle integrity; five-role tagged repeat metrics with non-negative/reconciled counters; exact `P0/P1/P2/info`, release-channel, and collision-disposition enums; typed grill/full-report/externalized artifacts bound to snapshot+sidecar; exact SHA-256 and collision/artifact/full-report references; independent coverage equality including unequal findings rejected when chains match; all eight exact source-field round trips; public initializers; structured unknown-enum fallback; CardType 10→11; no size downgrade; received UTF-8 262,144 accepts and 262,145 mandatory rejects |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashCore Swift build/test gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T021, T019; T019 must merge first so the AIDashCore-only PR passes required repository-wide builds; US1/US2 contract foundation |

- [ ] **T006 [P] [US1]** Add `Classification.teamAudit` in `Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift`.

| Metadata | T006 |
|---|---|
| Owning layer / context | **DesignKit** — CONTEXT.md → Packages/CONTEXT.md → Packages/DesignKit/CONTEXT.md; Packages/DesignKit/tech-context.md |
| Files in scope | `Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift`; `Packages/DesignKit/Tests/DesignKitTests/ColorSystemTests.swift`; `Packages/DesignKit/Tests/DesignKitTests/ContrastTests.swift` |
| Files NOT to touch | Packages/AIDashUI/**; Packages/AIDashCore/**; Theme seed generation; semantic success/warning/danger tokens |
| Interface / contract | `contracts/card-payload.md`: `teamAudit` classification uses light `#FF2D55`, dark `#FF375F`; product layout/copy remains in AIDashUI |
| Functional acceptance | Enum/tint golden values are locked; badge contrast is measured on supported neutral tiers; no second palette, feature layout, or raw color outside the token source is introduced |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected DesignKit Swift build/test gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | None; parallel visual-token foundation for US1/US2 |

- [ ] **T007 [US1]** Map the overview bundle to bounded `teamAudit` cards in `aidata/L5_apps/digest/team_audit.py` and `aidata/L5_apps/digest/aidash.py`.

| Metadata | T007 |
|---|---|
| Owning layer / context | **AidataL5** — CONTEXT.md → aidata/CONTEXT.md → aidata/L5_apps/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/L5_apps/digest/team_audit.py`; `aidata/L5_apps/digest/sources.py`; `aidata/L5_apps/digest/app.py`; `aidata/L5_apps/digest/aidash.py`; `aidata/tests/test_aidash_payload.py`; `aidata/tests/test_digest_golden.py`; neutral fixtures under `aidata/tests/fixtures/team_audit/**` |
| Files NOT to touch | aidata/adapters/**; aidata/schema/**; aidata/L4_serve/**; aidata/scripts/**; Swift/CLI files |
| Interface / contract | Fetch T004 immutable required inputs; pack the US1 overview plus every mandatory P0/P1 finding and generic/team/P0/P1 artifact; compute final `PublicationCoverage`/full-report state in L5 after packing, including independent `requiredP0P1FindingCount` / `publishedP0P1FindingCount`; emit snapshot+sidecar provenance and deterministic IDs |
| Functional acceptance | US1 publishes overview and all mandatory findings/artifacts independently; L5—not L4—computes published/omitted/externalized counts after final packing; P0/P1-finding and every mandatory-link required/published pair match independently; boundary/golden fixtures cover zero/one/multiple mandatory findings and reject a missing or oversized finding without letting its chain satisfy the finding count; mandatory invalid URLs/oversize reject; optional invalid links are not part of mandatory counts; finding identity, collision parent, sidecar ID/hash, axes/limitations survive; payloads ≤262,144; golden freezes seams; default digest invokes no audit |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL5 pytest/ruff gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T004, T005; US1 publication |

- [ ] **T008 [US1]** Render the Team Audit overview in `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`.

| Metadata | T008 |
|---|---|
| Owning layer / context | **AIDashUI** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashUI/CONTEXT.md; Packages/AIDashUI/tech-context.md |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift`; `Packages/AIDashUI/Sources/AIDashUI/DesignTokens.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/CardRouterTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/DesignTokensComplianceTests.swift` |
| Files NOT to touch | Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift (T014); existing card renderers; Packages/AIDashCore/**; Packages/DesignKit/**; Apps/** |
| Interface / contract | Render the US1 `overview`, mandatory P0/P1 `findings`, and mandatory `artifacts` sections read-only; sidecar/snapshot provenance and optional URLs use Core policy; symbol/tokens remain in DesignKit/AIDashUI; no persistence |
| Functional acceptance | Scope/cohort-or-cursors/axes/limitations and L5-computed coverage render, including independently matched P0/P1-finding and mandatory-link count pairs; mandatory findings show explicit subject/responsibility; mandatory artifacts are direct validated links with sidecar identity/hash; collision summary retains parent; invalid mandatory entries never reach a published card; size/style orthogonality, localization, accessibility, and ≥2 previews cover baseline/incremental/rejected fallback |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashUI Swift build/test gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T005, T006; US1 renderer |

- [ ] **T009 [P] [US1]** Advertise the `teamAudit` schema in `Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift`.

| Metadata | T009 |
|---|---|
| Owning layer / context | **AIDashApp** — CONTEXT.md → Apps/CONTEXT.md → Apps/AIDashApp/CONTEXT.md; constitution §II/Testing |
| Files in scope | `Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift`; `Apps/AIDashApp/Tests/XPCHandlersContainerCardTests.swift`; `Apps/AIDashApp/Tests/XPCHandlersBriefingTests.swift` |
| Files NOT to touch | CLI/aidash/**; project.yml; Apps/AIDashApp/Sources/Sync/UserEventWriter.swift (T015); CloudKit container/migration files |
| Interface / contract | Existing generic `aidash schema list`/card put paths receive one schema entry matching Core's `teamAudit`; no new CLI command or CloudKit authority |
| Functional acceptance | Schema list exposes the locked section/enums and required fields; valid overview payload is accepted through XPC and invalid payload returns the existing structured schema error; existing card types remain unchanged |
| Exact verification | Normal `git commit` and `git push` with configured hooks; no local App heavy gate. Required CI gates are App `macos-build` and `ios-build` exactly as declared in `Apps/AIDashApp/CONTEXT.md`. |
| Dependencies / slice | T005; parallel with T007/T008; US1 schema publication |

**US1 checkpoint**: T007 + T008 + T009 complete after their foundations. A
baseline or incremental overview plus every mandatory P0/P1 finding and
generic/team/P0/P1 artifact is independently publishable and readable.

## Phase 2: User Story 2 — Inspect findings and evidence (P2)

**Goal**: Add all lifecycle states, redacted timelines, full feedback lineage,
complete per-role repeat metrics, collision observations, individual metrics,
and optional safe Archify/grill/full-report relationships without changing the
US1 mandatory overview/P0/P1 publication.

**Independent test**: A neutral detail fixture renders all eight section kinds,
all six finding states, complete lineage/repeat fields, collision observations,
the already-published mandatory P0/P1 links plus optional size/externalization
behavior, and safe/unsafe optional links.

- [ ] **T010 [US2]** Add typed optional-detail queries under `aidata/L4_serve/queries/team-audit/`.

| Metadata | T010 |
|---|---|
| Owning layer / context | **AidataL4** — CONTEXT.md → aidata/CONTEXT.md → aidata/L4_serve/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/L4_serve/queries/team-audit/optional-findings.sql`; `aidata/L4_serve/queries/team-audit/case-timeline.sql`; `aidata/L4_serve/queries/team-audit/individual-metrics.sql`; `aidata/L4_serve/queries/team-audit/feedback-lineage.sql`; `aidata/L4_serve/queries/team-audit/agent-repeat-metrics.sql`; `aidata/L4_serve/queries/team-audit/import-collision-observations.sql`; `aidata/L4_serve/queries/team-audit/optional-artifacts.sql`; `aidata/L4_serve/queries/team-audit/grill-links.sql`; `aidata/tests/test_query_tiers.py` |
| Files NOT to touch | T004 mandatory/overview query files; aidata/schema/**; aidata/merge.py; aidata/L5_apps/** |
| Interface / contract | Read-only optional-detail bundles for P2/info findings/artifacts, cases, metrics, lineage, repeats, parented collision observations, and grill strings; required entity inputs remain T004-owned and no query computes publication results |
| Functional acceptance | Stable snapshot+sidecar IDs/hashes survive; optional findings preserve subject/responsibility; lineage/repeats and collision parent/accepted/rejected hashes round-trip; optional unsafe artifact/grill URLs remain data; no `published*`/omitted/externalized columns; empty optional details return empty bundles with limitations intact |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL4 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T004; US2 detail query seam |

- [ ] **T011 [US2]** Partition detail query bundles into `teamAudit` card parts in `aidata/L5_apps/digest/team_audit.py`.

| Metadata | T011 |
|---|---|
| Owning layer / context | **AidataL5** — CONTEXT.md → aidata/CONTEXT.md → aidata/L5_apps/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/L5_apps/digest/team_audit.py`; `aidata/L5_apps/digest/sources.py`; `aidata/L5_apps/digest/aidash.py`; `aidata/tests/test_aidash_payload.py`; `aidata/tests/test_digest_golden.py`; neutral fixtures under `aidata/tests/fixtures/team_audit/**` |
| Files NOT to touch | aidata/adapters/**; aidata/schema/**; aidata/L4_serve/**; aidata/scripts/**; Swift/CLI files |
| Interface / contract | `contracts/card-payload.md`: add optional P2/info findings/artifacts, timelines, metrics, lineage, repeats, parented collisions, and grill links after T007's mandatory publication; stable two-pass packing, 262,144-byte limit, and typed optional externalization |
| Functional acceptance | Optional details map without invented values and preserve finding identity, collision parent, and sidecar provenance; no entity splits/truncates; T007's mandatory cards/counts remain unchanged; oversized optional detail externalizes only with a valid full report and otherwise rejects; 262,144/262,145 plus with/without-report fixtures pass; unsafe optional URLs remain raw for UI policy; fetch seams are frozen |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL5 pytest/ruff gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T007, T010; US2 detail publication |

- [ ] **T012 [P] [US2]** Render all non-overview audit sections in `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`.

| Metadata | T012 |
|---|---|
| Owning layer / context | **AIDashUI** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashUI/CONTEXT.md; Packages/AIDashUI/tech-context.md |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/SnapshotRenderTests.swift` |
| Files NOT to touch | CardRouter.swift/DesignTokens.swift owned by T008; AuditActionEnvironment.swift and decision controls owned by T014; Core/DesignKit/App files |
| Interface / contract | Render optional P2/info findings/artifacts, case timelines, individual metrics, feedback lineage, per-role repeats, parented collisions, grill links, and externalized references; every optional URL crosses `AIDashCore.URLPolicy`; no WebView/file/custom scheme |
| Functional acceptance | Optional findings show subject/responsibility; lineage and per-role repeat evidence remain complete; collisions show parent snapshot ID/hash plus entity hashes; sidecar ID/hash is visible provenance; invalid optional artifact/grill URLs are non-tappable text; externalized/full-report links are typed; T008 mandatory rendering is unchanged; accessibility/wrapping comply |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashUI Swift build/test gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T008; parallel with T010/T011 after Core contract; US2 detail renderer |

**US2 checkpoint**: T011 + T012 complete. Findings and evidence are
independently inspectable with no Owner write capability yet.

## Phase 3: User Story 3 — Record safe Owner decisions (P3)

**Goal**: Append and display acknowledgement/approval receipts through the
existing event seam without mutating the snapshot or executing work.

**Independent test**: Intent spies and an in-memory event store prove exact
fingerprint targeting, local idempotency, no-op/failure degradation, immutable
snapshot bytes, preserved normalization, and zero dispatch/remediation calls.

- [ ] **T013 [P] [US3]** Add audit decision actions and factories in `Packages/AIDashCore/Sources/AIDashCore/Models/UserEventAction.swift` and `UserEvent.swift`.

| Metadata | T013 |
|---|---|
| Owning layer / context | **AIDashCore** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashCore/CONTEXT.md; Packages/AIDashCore/tech-context.md |
| Files in scope | `Packages/AIDashCore/Sources/AIDashCore/Models/UserEventAction.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/UserEvent.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CodableStructRoundTripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/UserEventModelTests.swift`; `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift` |
| Files NOT to touch | TeamAuditPayload.swift/CardType.swift owned by T005; storage schema; UI/App/aidata files |
| Interface / contract | `contracts/owner-decision-events.md`: raw actions `auditFindingAcknowledged` and `auditFindingRemediationApproved`; factories set `itemRef=fingerprint`, `cardType=teamAudit` |
| Functional acceptance | Both raw values and factories round-trip; fingerprint/card/type/action are exact; existing done/undone/star behavior is unchanged; empty fingerprint is rejected through a documented graceful error contract; no remediation interface exists |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashCore Swift build/test gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T005; US3 event contract |

- [ ] **T014 [US3]** Add audit decision intents and receipt rendering in `Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift`.

| Metadata | T014 |
|---|---|
| Owning layer / context | **AIDashUI** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashUI/CONTEXT.md; Packages/AIDashUI/tech-context.md |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift`; `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/AuditActionEnvironmentTests.swift` |
| Files NOT to touch | StarActionEnvironment.swift; other card views; Core/DesignKit/App files |
| Interface / contract | Optional acknowledge/approve closures take `(cardId, findingFingerprint)`; acknowledged/approved fingerprint sets drive receipt copy; defaults nil/empty |
| Functional acceptance | Buttons exist only for finding sections and carry exact stable fingerprint; approval copy says separate remediation; receipt sets never replace canonical state; nil environments are no-op; spy tests prove calls and zero extra side effects; HTTPS grill links only open Link destinations; hit targets/localization/accessibility comply |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashUI Swift build/test gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T012, T013; US3 UI intent seam |

- [ ] **T015 [US3]** Persist and inject audit receipts in `Apps/AIDashApp/Sources/Sync/UserEventWriter.swift` and `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`.

| Metadata | T015 |
|---|---|
| Owning layer / context | **AIDashApp** — CONTEXT.md → Apps/CONTEXT.md → Apps/AIDashApp/CONTEXT.md; constitution §I/II/Testing |
| Files in scope | `Apps/AIDashApp/Sources/Sync/UserEventWriter.swift`; `Apps/AIDashApp/Sources/Scenes/AuditFeedbackActions.swift`; `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`; `Apps/AIDashApp/Tests/UserEventWriterTests.swift`; `Apps/AIDashApp/Tests/AuditFeedbackWiringTests.swift`; `Apps/AIDashApp/Tests/BriefingWindowSceneLocalizationTests.swift` |
| Files NOT to touch | CloudKit container/migration files; XPC schema files owned by T009; CLI/project wiring; Core/UI/aidata files |
| Interface / contract | App adapter for `contracts/owner-decision-events.md`: append one row per local `(cardId,fingerprint,action)`, inject closures and derived receipt sets, swallow persistence failure without confirmation |
| Functional acceptance | In-memory store proves acknowledgement/approval append-only idempotency; existing rows are never updated/deleted; receipt derivation collapses cross-device duplicates by fingerprint/action; scene injects both intents/sets; snapshot payload bytes remain unchanged; spies show only UserEventWriter is called and no issue/run/agent/remediation interface exists |
| Exact verification | Normal `git commit` and `git push` with configured hooks; no proactive local App test. Required CI gates are App `macos-build` and `ios-build`; a hostless focused rerun is diagnostic only after a concrete App-layer failure. |
| Dependencies / slice | T009, T014; US3 persistence/wiring |

- [ ] **T016 [P] [US3]** Preserve audit decision actions in `aidata/adapters/aidash_events.py`.

| Metadata | T016 |
|---|---|
| Owning layer / context | **AidataL1L2** — CONTEXT.md → aidata/CONTEXT.md → aidata/adapters/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/adapters/aidash_events.py`; `aidata/tests/test_aidash_events_adapter.py` |
| Files NOT to touch | `team_audit_snapshot.py` owned by T026 and T022–T024 contract modules; warehouse/query/L5 files; aidata scripts/cron; Swift/App files |
| Interface / contract | Event normalizer preserves both locked action strings, finding fingerprint in `item_ref`, and `teamAudit` in `card_type`; existing done/undone/star behavior is unchanged |
| Functional acceptance | New events never normalize action to null/unknown; old events without card type remain compatible; redaction and no-config degradation persist; adapter only reads `aidash events pull` output and does not invoke an audit or remediation |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL1L2 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T026, T013; parallel with T014/T015 where files do not conflict; US3 feedback lineage |

- [ ] **T017 [P] [US3]** Extend audit-action filtering in `CLI/aidash/Sources/Commands/EventsPullCommand.swift`.

| Metadata | T017 |
|---|---|
| Owning layer / context | **aidashCLI** — CONTEXT.md → CLI/CONTEXT.md → CLI/aidash/CONTEXT.md; root tech-context.md |
| Files in scope | `CLI/aidash/Sources/Commands/EventsPullCommand.swift`; `CLI/aidash/Tests/EventsPullCommandTests.swift` |
| Files NOT to touch | Packages/AIDashCore/** (T013); Apps/**; Packages/AIDashUI/**; project.yml; any CLI command other than events pull |
| Interface / contract | `--action` help/filter accepts `done`, `undone`, `star`, `auditFindingAcknowledged`, and `auditFindingRemediationApproved`; canonical values come from `UserEventAction.rawValue` |
| Functional acceptance | Parsing compares case-insensitively without lowercasing before raw-value construction; unknown-action `allowed` derives exactly from `UserEventAction.allCases`; JSONL preserves canonical camel-case audit actions; success and validation-failure tests cover both new values and existing actions |
| Exact verification | Normal `git commit` and `git push` with configured hooks; aidashCLI's heavy macOS build gate runs only in CI as declared in `CLI/aidash/CONTEXT.md`. |
| Dependencies / slice | T013; parallel with T014–T016 after the Core event contract; US3 CLI consumer |

**US3 checkpoint**: T015 + T016 + T017 complete. The Owner can record and see
safe decision receipts, and agents can filter the canonical actions; snapshot
state and execution systems remain untouched.

## Phase 4: Assembled contract verification

**Purpose**: Make the repository's cross-language checker revision-local and
run it through the normal hook-selected RepoInfra gate only after every product
adapter is assembled.

- [ ] **T018 [US3]** Correct and gate the assembled checker in `.claude/skills/aidash-content/scripts/contract_check.sh`.

| Metadata | T018 |
|---|---|
| Owning layer / context | **RepoInfra integration-only** — CONTEXT.md → scripts/CONTEXT.md; root tech-context.md |
| Files in scope | `.claude/skills/aidash-content/scripts/contract_check.sh`; `.claude/skills/aidash-content/references/anchors.md`; `scripts/CONTEXT.md`; `scripts/context/tests/test_contract_check.py` |
| Files NOT to touch | Packages/**; Apps/**; CLI/**; aidata/**; scripts/hooks/**; any product contract or implementation file |
| Interface / contract | Internal checker resolves the current Git worktree, checks Core `CardType`, App `XPCPayloadSchemas.swift`, UI `CardRouter`, and AidataL5 `team_audit.py`/`aidash.py`, and is registered as a RepoInfra lint gate |
| Functional acceptance | No `$HOME/Development/AIDash` or other fixed checkout; schema anchor is `Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift`; mapper coverage includes the new audit module; tests prove cwd independence, correct anchors, and a failing drift case; the normal hook-selected RepoInfra gate runs the checker against the assembled revision exactly once |
| Exact verification | Normal `git commit` and `git push` with configured hooks after all dependencies; the updated RepoInfra local gate, including the registered contract checker and regression tests, must exit 0. No proactive standalone checker/test invocation. |
| Dependencies / slice | T007, T008, T009, T011, T012, T015, T016, T017; final US1–US3 integration-only verification |

## Dependency and Scheduling Summary

```text
Recovery gates: T020 → T021 → T019 → T005
US1 compatibility: T019 → T005
US1 data: T001 → T022 → T023 → T024 → T025 → T026 → T003 → T004 → T007
US1 app:  T005 ─┬→ T007
                ├→ T008 ← T006
                └→ T009
US1 done: T007 + T008 + T009

US2 data: T004 → T010 → T011 (also waits for T007)
US2 UI:   T008 → T012
US2 done: T011 + T012

US3 core: T005 → T013
US3 CLI:  T013 → T017
US3 UI:   T012 + T013 → T014
US3 App:  T009 + T014 → T015
US3 data: T026 + T013 → T016
US3 done: T015 + T016 + T017

Assembled gate:
T007 + T008 + T009 + T011 + T012 + T015 + T016 + T017 → T018

```

Parallel tasks marked `[P]` have non-conflicting files. T012 may run in
parallel with T010/T011 after T008 because both consume the locked Core
contract. T016 and T017 may run in parallel with UI/App work after T013.
T020 changes no product behavior but must land first because a fresh macOS
RepoInfra hook run on current main reproduces the leader-exits-zero status
failure before T021 can publish normally. Its exact base is `2c75188c...` and
its implementation candidate must be published and non-empty as defined above.
T019 is the merge-first expand step that keeps T005 AIDashCore-only and
repository-buildable.

## Acceptance Coverage

| Spec requirement / criterion | Slice / tasks |
|---|---|
| Constitution amendment publication contract and migration note | Recovery gate: T021 |
| Future CardType consumer compatibility before Core expansion | US1: T019 → T005 |
| FR-001 manual-only source | US1: T001, T026 |
| FR-002 immutable/redacted/provenanced snapshot + sidecar L1–L5 records | US1: T022–T026, T003–T005, T007–T008 |
| FR-003 baseline cohort vs incremental cursors | US1: T022, T025–T026, T003–T005, T007–T008 |
| FR-004 restart-safe replay/collision/overlap dedupe with accepted parent snapshot | US1: T023–T026, T003–T005, T007–T008; US2: T010–T012 |
| FR-005 scope/mode/version/coverage/limitations display | US1: T004, T007–T008 |
| FR-006 three independent core axes + separate Task Effectiveness | US1: T022, T025–T026, T003–T005, T007–T008 |
| FR-007 reconciled axis/effectiveness counts | US1: T022, T025–T026, T003–T005, T007–T008 |
| FR-008 fingerprints and all six states | US2: T022, T025–T026, T003, T005, T010–T012 |
| FR-009 explicit finding subject/responsibility plus evidence/remediation owner | US1: T022, T025–T026, T003–T005, T007–T008; US2: T010–T012 |
| FR-010 timelines, full feedback lineage, and complete per-role repeat metrics | US2: T022, T025–T026, T003, T005, T010–T012 |
| FR-011 every mandatory generic/team/P0/P1 direct link | US1: T022, T025–T026, T003–T005, T007–T009; assembled T018 |
| FR-012 mandatory invalid-link rejection; optional full-report/externalization/degradation | US1: T022, T025–T026, T003–T005, T007–T008; US2: T010–T012 |
| FR-013 append acknowledgement/approval receipt | US3: T013–T015 |
| FR-014 decision idempotency | US3: T013–T015 |
| FR-015 no canonical snapshot mutation | US3: T014–T015 |
| FR-016 approval grants no remediation/dispatch authority | US3: T014–T017 |
| FR-017 typed sidecar identity/hash and HTTPS-only grill entry points | US1: T022–T026, T003–T005, T007–T008; US2: T010–T012; US3: T014 |
| FR-018 exact size, mandatory rejection, optional externalization, and graceful invalid/future behavior | US1: T005, T007–T008; US2: T011–T012; US3: T014–T015 |
| FR-019 automated contract/boundary coverage | US1: T001, T022–T026, T003–T009; US2: T010–T012; US3: T013–T017; assembled T018 |
| SC-001/SC-003 complete fixture render and enum round-trip | US1: T005, T007–T009; US2: T010–T012 |
| SC-002 one record per identity across restarts, zero overwrites, parented collision observation | US1: T023–T026, T003–T005, T007–T008; US2: T010–T012 |
| SC-004 one receipt per decision kind, immutable source bytes | US3: T013–T015 |
| SC-005 zero invocation/mutation/dispatch/remediation | US1: T001, T022–T026; US3: T014–T017 |
| SC-006 mandatory invalid-link rejection and optional artifact/grill URL policy | US1: T022, T025–T026, T003–T005, T007–T008; US2: T010–T012; US3: T014 |
| SC-007 262,144/262,145 boundary and exact mandatory P0/P1-finding/link counts | US1: T022, T025–T026, T003–T008; US2: T010–T012 |
| Watchdog exit/tree/pipe cleanup without product scope; unblock normal planning hooks | Recovery prerequisite: T020 → T021 |

## Definition of Done

- Every task stays inside its listed files plus only the tests already listed.
- Normal commit/push hooks select the affected layer gates and report success;
  no suite or resolver gate is run proactively.
- The hooks' routing audit reports zero findings after routing changes.
- T018's registered RepoInfra hook gate runs the revision-local checker and
  confirms the assembled Core/App/UI/aidata card seam.
- The implementation PR's required CI App/CLI/aidata/review checks pass.
- No host-based AIDashApp test is run locally.
- Exact implementation SHA matches local HEAD, pushed branch, and PR head
  before independent implementation review.
- T002 itself is coordination-only. T022–T026 run serially, each through normal
  AidataL1L2 hooks; no implementation run may touch the final collector before
  the contract, reader, persisted index, and acceptance-matrix predecessors
  have merged.
- T021's PR title is `constitution: authorize team audit decision receipts`,
  its body contains the in-flight migration note, and its exact surface is
  planning/constitution-only.
- T019 is merged before provisioning T005; T005 then changes only its original
  nine AIDashCore files and satisfies every row of
  `contracts/t005-acceptance-matrix.md`.
- T020 uses its own issue, persisted workspace, published task branch, PR, and
  RepoInfra evidence. Its head differs from exact base `2c75188c...`, its
  three-dot surface is limited to the two authorized files and includes
  `review-common.sh`, and local/remote/PR heads match before a PASS review. PR
  #202 and its workspace remain untouched evidence.
