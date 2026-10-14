# Tasks: On-Demand Team Workflow Audit

**Input**: Design documents in `specs/006-team-workflow-audit/`

**Organization**: Each user-story phase is a vertical product slice. Every
executable row owns one resolver layer; cross-layer behavior is locked by the
contracts and blocking edges below. Constitution §Cross-Cutting Quality Bars
applies to every task.

## Phase 0: Completed recovery publication and compatibility history

**Status**: Complete in the recovery parent. PR #204 delivered T020, PR #210
delivered T021, and PR #215 delivered T019. These rows are historical evidence,
not schedulable dependencies for the current T005 recovery.

- [x] **T020 [POLISH]** Repair timeout process supervision in `scripts/ci/review_process_supervisor.py`.

| Metadata | T020 |
|---|---|
| Owning layer / context | **RepoInfra** — CONTEXT.md → scripts/CONTEXT.md; root tech-context.md |
| Files in scope | `scripts/ci/review-common.sh`; `scripts/ci/review_process_supervisor.py`; `scripts/ci/tests/test_review_shell.py` |
| Files NOT to touch | Other `scripts/ci/**`, including reviewer callers and `review_context.py`; `.specify/**`; `specs/**`; `AGENTS.md`; `Packages/**`; `Apps/**`; `CLI/**`; `aidata/**`; `.github/workflows/**`; rulesets; context routing; reviewer trust/verdict semantics; timeout budget |
| Historical delivered surface | PR #204 merged the reviewed successor from exact base `8716846ac42b48bfd89b9a09d5dd05fc4819025d`. Rejected head `b4aa5e51bdf381d71a6ab77fa2342349a6a5dedb` remains evidence only. The delivered three-dot surface was limited to the three Files in scope. |
| Interface / contract | `contracts/t020-process-supervisor.md`: keep `run_with_timeout <seconds> <command...>` unchanged while a target-only capability, stable process identity, one absolute deadline, output relays, and Darwin/Linux adapters terminate the complete invocation descendant tree and close inherited pipes without global orphan discovery; internal supervision/cleanup-proof failure is reserved status 125 |
| Baseline failure evidence | Exact review of `b4aa5e51...` found a destructive P0: `PPID=1` plus broad executable-name matching could import unrelated system orphans into TERM/KILL. Removing it leaves a startup gap because the recorder starts after launch and sampled Bash/`ps` ancestry cannot deterministically retain a fast out-of-PGID child through reparenting. No implementation or review of that unchanged SHA is authorized. |
| Functional acceptance | Fast success and ordinary failure return their real status only after proven cleanup; an absolute deadline returns 124 and TERM-trapping leaders cannot hide it; the target is not released before root identity/tracking readiness; zero-sleep leader-exits-zero plus PID-confirmed `setsid` descendant cleanup returns 0 on macOS and Linux; TERM→KILL removes `env → bash → child`, TERM-resistant, and cleanup-spawned descendants; stable `(pid,birthMarker)` identities survive reparenting and reject PID reuse; unrelated simultaneous orphan-shaped shell/Python/Node/sleep processes remain untouched; tracking or cleanup uncertainty returns 125; no PID or stdout/stderr pipe leaks; existing caller, sticky-comment, security/trust, no-heredoc, and 900-second semantics are unchanged |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected RepoInfra syntax plus `/usr/bin/python3 -m pytest scripts/ci/tests scripts/context/tests -q` must exit 0; CI `review-gate (pytest)` must pass; local HEAD, remote task ref, and PR `headRefOid` must be equal; exact-SHA implementation review must PASS before merge |
| Dependencies / slice | Completed historical prerequisite; merged through PR #204 and already present in `fdace13d…`. No dispatch remains. |

- [x] **T021 [POLISH]** Publish the exact reviewed planning and constitution amendment.

| Metadata | T021 |
|---|---|
| Owning layer / context | **RepoInfra planning-only** — CONTEXT.md → scripts/CONTEXT.md; .specify/memory/constitution.md Governance |
| Files in scope | `.specify/feature.json`; `.specify/memory/constitution.md`; `AGENTS.md` (managed Spec Kit marker only); `specs/006-team-workflow-audit/spec.md`; `specs/006-team-workflow-audit/plan.md`; `specs/006-team-workflow-audit/research.md`; `specs/006-team-workflow-audit/data-model.md`; `specs/006-team-workflow-audit/quickstart.md`; `specs/006-team-workflow-audit/tasks.md`; `specs/006-team-workflow-audit/checklists/requirements.md`; `specs/006-team-workflow-audit/contracts/card-payload.md`; `specs/006-team-workflow-audit/contracts/manual-import.md`; `specs/006-team-workflow-audit/contracts/owner-decision-events.md`; `specs/006-team-workflow-audit/contracts/t005-acceptance-matrix.md`; `specs/006-team-workflow-audit/contracts/t020-process-supervisor.md` |
| Files NOT to touch | Packages/**; Apps/**; CLI/**; aidata/**; `scripts/ci/review-common.sh`; `scripts/ci/review_process_supervisor.py`; `scripts/ci/tests/test_review_shell.py`; any PR #204 branch/workspace file |
| Interface / contract | Planning/constitution-only PR from Team Lead's approved main lineage; title exactly `constitution: authorize team audit decision receipts`; PR body repeats the 1.13.0 in-flight migration note |
| Functional acceptance | PR surface is exactly the reviewed planning artifact set; constitution is 1.13.0; body states existing events remain valid, new actions are additive, unknown consumers preserve or visibly ignore them, and audit invocation/remediation remain outside AIDash; local/remote/PR SHA pin is exact; no product/watchdog implementation appears |
| Exact verification | Normal `git commit` and `git push` with configured hooks; Spec Kit prerequisites, routing/frontmatter/task-freshness checks selected by RepoInfra must exit 0; constitution PR metadata is part of acceptance |
| Dependencies / slice | Completed historical prerequisite; merged through PR #210 and already present in `fdace13d…`. It is not the current revised-planning publication gate. |

- [x] **T019 [US1]** Prepare AIDashUI CardType switches for a future Core enum case.

| Metadata | T019 |
|---|---|
| Owning layer / context | **AIDashUI** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashUI/CONTEXT.md; Packages/AIDashUI/tech-context.md |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/DesignTokens.swift`; `Packages/AIDashUI/Tests/AIDashUITests/CardRouterTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/DesignTokensComplianceTests.swift` |
| Files NOT to touch | Packages/AIDashCore/**; Packages/DesignKit/**; Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift; TeamAuditCardView.swift; Apps/**; CLI/**; aidata/** |
| Interface / contract | Existing imported `CardType` switches have an explicit future-case fallback that preserves current mappings and generic-card behavior; this task does not add or render `teamAudit` |
| Functional acceptance | All ten current CardType symbol/classification/payload-name mappings remain exact; a future imported enum case compiles through the documented fallback until T008 adds the explicit renderer; tests/helpers do not reintroduce exhaustive future-case failure; no visual token or current renderer behavior changes |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashUI Swift build/test gates must exit 0; required repository-wide CI build remains green |
| Dependencies / slice | Completed historical prerequisite; merged through PR #215 as `fdace13d…`. No dispatch remains. |

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

- [ ] **T002 [US1]** Implement immutable bundle collection and normalization in `aidata/adapters/team_audit_snapshot.py`.

| Metadata | T002 |
|---|---|
| Owning layer / context | **AidataL1L2** — CONTEXT.md → aidata/CONTEXT.md → aidata/adapters/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/adapters/team_audit_snapshot.py`; `aidata/adapters/CONTEXT.md`; `aidata/CONTEXT.md`; `aidata/tests/test_team_audit_adapter.py`; neutral fixtures under `aidata/adapters/fixtures/team_audit/**` |
| Files NOT to touch | aidata/tests/fixtures/** (AidataL5-owned); aidata/scripts/**; aidata/cli.py; aidata/config.py; aidata/merge.py; aidata/schema/**; external audit sources; generated raw/clean data |
| Interface / contract | `contracts/manual-import.md` and `data-model.md`: read-only bundle adapter, append-only redacted raw records, explicit finding subject/responsibility/priority, exact feedback-lineage/agent-repeat fields, source case/event/evidence/subject/revision identity sets, artifact kind/ID/hash/raw-URL/sidecar bindings, stable sidecar ID/exact byte hash, and independently keyed collision observations with accepted parent snapshot ID/hash |
| Functional acceptance | Fixtures preserve cohort/cursors, instruction hashes, axes, explicit finding identity/priority, catalog source identities, artifact/full-report binding fields, limitations, artifacts/grill fields, and importer-computed sidecar ID/hash; lineage ID equals the canonical U+001F tuple SHA-256 and any merge revision is a lowercase 40-hex Git SHA-1 OID; repeat subject/event identities are non-empty and unique; same identity+hash replays; snapshot/child/sidecar identity+different hash appends a parented collision observation and never overwrites/stores rejected content; overlap IDs dedupe; path/redaction/missing-config cases degrade safely; spies observe zero dispatch/invocation/mutation calls |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL1L2 tests and the routing audit must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T001; US1 import seam (also supplies US2 evidence facts) |

- [ ] **T003 [US1]** Add immutable Team Audit warehouse facts in `aidata/schema/warehouse.sql` and `aidata/merge.py`.

| Metadata | T003 |
|---|---|
| Owning layer / context | **AidataL3** — CONTEXT.md → aidata/CONTEXT.md → aidata/schema/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/schema/warehouse.sql`; `aidata/merge.py`; `aidata/tests/test_warehouse_integrity.py`; `aidata/tests/test_warehouse_quality.py` |
| Files NOT to touch | aidata/adapters/**; aidata/L4_serve/**; aidata/L5_apps/**; generated databases |
| Interface / contract | `data-model.md` grains/bridges: snapshot, axis, case/event/attempt/finding with explicit subject/responsibility/priority, metrics/lineage/repeats, all reference-catalog source identities, sidecar identity/hash, collision observations with parent snapshot ID/hash, artifacts/full-report kind/ID/hash/raw-URL/sidecar bindings, and grill links, all retaining immutable provenance |
| Functional acceptance | Merge produces one row per grain/bridge; accepted facts never update; parented collision IDs merge independently; finding/catalog identity fields, canonical lineage ID and 40-hex merge OID, complete repeats, exact sidecar hash, and sidecar foreign keys on artifact/grill rows round-trip; artifact references retain priority/kind/ID/hash/raw URL/sidecar without display-body duplication; same sidecar ID/different hash observes a collision; foreign/mode/axis violations fabricate nothing; generated DB stays untracked |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL3 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T002; US1 immutable warehouse |

- [ ] **T004 [US1]** Add overview and required-publication input queries under `aidata/L4_serve/queries/team-audit/`.

| Metadata | T004 |
|---|---|
| Owning layer / context | **AidataL4** — CONTEXT.md → aidata/CONTEXT.md → aidata/L4_serve/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/L4_serve/queries/team-audit/latest-snapshot.sql`; `aidata/L4_serve/queries/team-audit/axis-summary.sql`; `aidata/L4_serve/queries/team-audit/task-effectiveness.sql`; `aidata/L4_serve/queries/team-audit/required-publication-inputs.sql`; `aidata/L4_serve/queries/team-audit/mandatory-findings.sql`; `aidata/L4_serve/queries/team-audit/mandatory-artifacts.sql`; `aidata/L4_serve/queries/team-audit/import-collision-summary.sql`; `aidata/tests/test_query_tiers.py` |
| Files NOT to touch | aidata/schema/**; aidata/merge.py; aidata/L5_apps/**; any write path |
| Interface / contract | Named read-only bundles expose accepted snapshot/sidecar provenance, cohort/cursors, axes/effectiveness, collision summary, required entity/count inputs, and the complete US1 reference-catalog inputs: case/event/evidence/subject/revision IDs, finding fingerprint+priority, and artifact kind/ID/hash/raw-URL/sidecar bindings including the overview full report; L4 has no published/omitted/externalized result |
| Functional acceptance | Query grains are explicit; latest ordering is deterministic; finding subject/responsibility/priority and parented collisions survive; every mandatory reference-catalog field and sidecar ID/hash reaches L5; `requiredP0P1FindingCount` derives from immutable mandatory-finding facts independently of chain counts; overview full-report input has one exact catalog artifact binding; columns named `published*`, `omitted*`, or `externalized*` are absent; query fixtures cover zero/one/multiple required P0/P1 findings; empty warehouse returns an empty/degraded bundle |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL4 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T003; US1 query seam |

- [ ] **T005 [US1]** Define and validate `teamAudit` in `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`.

| Metadata | T005 |
|---|---|
| Owning layer / context | **AIDashCore** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashCore/CONTEXT.md; Packages/AIDashCore/tech-context.md |
| Files in scope | `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift`; `Packages/AIDashCore/Sources/AIDashCore/Validation/TeamAuditPayloadValidation.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadValidationTests.swift`; `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift` |
| Files NOT to touch | `Packages/AIDashCore/Sources/AIDashCore/Validation/SchemaValidator.swift`; `Packages/AIDashCore/Sources/AIDashCore/Validation/URLPolicy.swift`; Packages/AIDashCore/Sources/AIDashCore/Models/UserEvent*.swift (T013); every other AIDashCore source/test; Packages/AIDashUI/**; Apps/**; CLI/**; aidata/**; specs/**; .specify/** |
| Interface / contract | `contracts/card-payload.md`, `data-model.md`, and `contracts/t005-acceptance-matrix.md`: one `teamAudit` type, eight variants, typed reference catalog, complete public type surface, exact locked wire vocabulary, Types-owned structural/referential validation, and a Service-role `validateInvariants()` witness that applies unchanged central `URLPolicy` without Models→Validation dependency |
| Functional acceptance | FR-020–FR-025 and every Core-owned row of the T005 acceptance matrix pass: axis-context decoding including all three `insufficientEvidence` cases; unique/catalog-resolved finding/case/event/evidence/subject/revision/artifact references; canonical lineage hash and 40-hex Git SHA-1 merge OID; five-role primary-round, repeat, breakdown, and supporting-evidence reconciliation; unique priority-aware artifacts; exact kind/ID/hash/URL/sidecar full-report binding from overview or artifacts; optional-only typed externalization with P2/info chains preserved; exact equality for all eight variants; public initializers; structured Core unknown-enum error propagation; unsafe optional URL-string preservation; CardType 10→11; no size downgrade; exact received valid UTF-8 262,144 acceptance and mandatory 262,145 rejection |
| Architecture acceptance | `TeamAuditPayload.swift` contains no `URLPolicy` or other Validation-role reference. It exposes an internal structural helper; `Validation/TeamAuditPayloadValidation.swift` supplies the public protocol witness and internal URL traversal. Existing `CardType.validate`, `SchemaValidator.validateCardPut`, `SchemaValidator.swift`, and `URLPolicy.swift` behavior/interface remain unchanged. |
| Planning-base / recovery gate | The T005 implementation base is the exact published planning commit cited by the fresh AI Reviewer `PASS`; parent `fdace13d20ee0b28759c4853c82445fd4d913dcc` alone is not valid. Team Lead must pin that reviewed revision (or an approved descendant with byte-identical nine artifact blobs) in the handoff and delivery metadata before Fullstack starts. Preserve the registered delivery workspace and candidate `12577b03c866c73c53fa23d236d2005a68790358` as immutable review evidence until that recovery handoff; do not publish or re-review the stale candidate. |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashCore Swift build/test gates must exit 0. Diff surface must equal the eleven listed paths; focused architecture proof finds no Models→Validation reference; Service tests exercise `CardType.validate` and production `SchemaValidator` error fields. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | Only active edge: exact revised-plan publication/base pin → Team Lead recovery handoff → T005. Historical T020/T021/T019 are complete in the parent and are not schedulable dependencies; US1/US2 contract foundation. |

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
| Interface / contract | Fetch T004 immutable required inputs; build the complete typed reference catalog on every US1 part; pack the overview plus every mandatory P0/P1 finding and generic/team/P0/P1 artifact; compute final `PublicationCoverage`/full-report state in L5 after packing, including independent finding/chain counts; emit snapshot+sidecar provenance and deterministic IDs |
| Functional acceptance | US1 publishes overview and all mandatory findings/artifacts independently; every part contains unique required catalog IDs and finding/artifact entries; overview `fullReport` matches exactly one catalog `fullReport` by kind/ID/hash/raw URL/sidecar; P0/P1 chain metadata retains finding priority plus unique event/revision references; L5—not L4—computes published/omitted/externalized counts after final packing; required/published pairs match independently; boundary/golden fixtures reject missing/unresolved/oversized mandatory values; mandatory invalid URLs reject; optional invalid links are not mandatory counts; payloads ≤262,144; default digest invokes no audit |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL5 pytest/ruff gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T004, T005; US1 publication |

- [ ] **T008 [US1]** Render the Team Audit overview in `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`.

| Metadata | T008 |
|---|---|
| Owning layer / context | **AIDashUI** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashUI/CONTEXT.md; Packages/AIDashUI/tech-context.md |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift`; `Packages/AIDashUI/Sources/AIDashUI/DesignTokens.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/CardRouterTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/DesignTokensComplianceTests.swift` |
| Files NOT to touch | Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift (T014); existing card renderers; Packages/AIDashCore/**; Packages/DesignKit/**; Apps/** |
| Interface / contract | Render the US1 `overview`, mandatory P0/P1 `findings`, and mandatory `artifacts` sections read-only; sidecar/snapshot provenance and optional URLs use Core policy; symbol/tokens remain in DesignKit/AIDashUI; no persistence |
| Functional acceptance | Scope/cohort-or-cursors/axes/limitations and L5-computed coverage render, including independently matched P0/P1-finding and mandatory-link count pairs; mandatory findings show explicit subject/responsibility; mandatory artifacts are direct validated links with sidecar identity/hash; collision summary retains parent; a `teamAudit` payload containing an unknown locked enum produces the existing generic `CardRouter` fallback in `CardRouterTests`; invalid mandatory entries never reach a published card; size/style orthogonality, localization, accessibility, and ≥2 previews cover baseline/incremental/rejected fallback |
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
| Interface / contract | Read-only optional-detail bundles for P2/info findings/artifacts, cases, metrics, lineage, repeats, parented collision observations, and grill strings, plus complete detail reference-catalog inputs: case/event/evidence/subject/revision IDs, finding fingerprint+priority, and optional artifact kind/ID/hash/raw-URL/sidecar bindings; required entity inputs remain T004-owned and no query computes publication results |
| Functional acceptance | Stable snapshot+sidecar IDs/hashes survive; optional findings preserve subject/responsibility/priority; canonical lineage hash, 40-hex merge OID, repeat evidence IDs, collision hashes, and optional artifact catalog bindings round-trip; optional unsafe artifact/grill URLs remain raw data; no `published*`/omitted/externalized columns; empty optional details return empty bundles with limitations intact |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL4 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T004; US2 detail query seam |

- [ ] **T011 [US2]** Partition detail query bundles into `teamAudit` card parts in `aidata/L5_apps/digest/team_audit.py`.

| Metadata | T011 |
|---|---|
| Owning layer / context | **AidataL5** — CONTEXT.md → aidata/CONTEXT.md → aidata/L5_apps/CONTEXT.md; aidata/tech-context.md |
| Files in scope | `aidata/L5_apps/digest/team_audit.py`; `aidata/L5_apps/digest/sources.py`; `aidata/L5_apps/digest/aidash.py`; `aidata/tests/test_aidash_payload.py`; `aidata/tests/test_digest_golden.py`; neutral fixtures under `aidata/tests/fixtures/team_audit/**` |
| Files NOT to touch | aidata/adapters/**; aidata/schema/**; aidata/L4_serve/**; aidata/scripts/**; Swift/CLI files |
| Interface / contract | `contracts/card-payload.md`: add optional P2/info findings/artifacts, timelines, metrics, lineage, repeats, parented collisions, and grill links after T007; build a complete typed reference catalog for every detail part; stable two-pass packing, 262,144-byte limit, and typed optional-only externalization |
| Functional acceptance | Optional details map without invented values and preserve finding priority, canonical lineage/merge identities, repeat subject/event evidence, collision parent, and sidecar provenance; every local reference resolves once through the part catalog; P2/info chains remain optional with unique event/revision bindings; externalization uses only typed optional kinds and matches full report kind/ID/hash/raw URL/sidecar exactly; no entity splits/truncates; T007 mandatory cards/counts remain unchanged; exact boundary and with/without-report fixtures pass; unsafe optional URLs remain raw for UI policy; fetch seams are frozen |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL5 pytest/ruff gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T007, T010; US2 detail publication |

- [ ] **T012 [P] [US2]** Render all non-overview audit sections in `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`.

| Metadata | T012 |
|---|---|
| Owning layer / context | **AIDashUI** — CONTEXT.md → Packages/CONTEXT.md → Packages/AIDashUI/CONTEXT.md; Packages/AIDashUI/tech-context.md |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/SnapshotRenderTests.swift` |
| Files NOT to touch | CardRouter.swift/DesignTokens.swift owned by T008; AuditActionEnvironment.swift and decision controls owned by T014; Core/DesignKit/App files |
| Interface / contract | Render optional P2/info findings/artifacts, case timelines, individual metrics, feedback lineage, per-role repeats, parented collisions, grill links, and externalized references; every optional URL crosses `AIDashCore.URLPolicy`; no WebView/file/custom scheme |
| Functional acceptance | Optional findings show subject/responsibility/priority; lineage and per-role repeat evidence remain complete; collisions show parent snapshot ID/hash plus entity hashes; sidecar ID/hash is visible provenance; optional P2/info chains render without being promoted to mandatory; invalid optional artifact/grill URLs are non-tappable text; externalized/full-report links are typed; T008 mandatory rendering is unchanged; accessibility/wrapping comply |
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
| Files NOT to touch | team_audit_snapshot.py owned by T002; warehouse/query/L5 files; aidata scripts/cron; Swift/App files |
| Interface / contract | Event normalizer preserves both locked action strings, finding fingerprint in `item_ref`, and `teamAudit` in `card_type`; existing done/undone/star behavior is unchanged |
| Functional acceptance | New events never normalize action to null/unknown; old events without card type remain compatible; redaction and no-config degradation persist; adapter only reads `aidash events pull` output and does not invoke an audit or remediation |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL1L2 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T002, T013; parallel with T014/T015 where files do not conflict; US3 feedback lineage |

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
Completed history: T020 ✓ → T021 ✓ → T019 ✓ (all present in fdace13d…)
Active recovery: exact revised-plan PASS + published base pin → Team Lead handoff → T005
US1 data: T001 → T002 → T003 → T004 → T007
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
US3 data: T002 + T013 → T016
US3 done: T015 + T016 + T017

Assembled gate:
T007 + T008 + T009 + T011 + T012 + T015 + T016 + T017 → T018

```

Parallel tasks marked `[P]` have non-conflicting files. T012 may run in
parallel with T010/T011 after T008 because both consume the locked Core
contract. T016 and T017 may run in parallel with UI/App work after T013.
T020, T021, and T019 are completed history and MUST NOT be dispatched again.
Before T005, Team Lead pins the exact planning commit named by the fresh PASS
as the implementation base (or an approved descendant with byte-identical
artifact blobs) and reconciles the preserved delivery workspace under the
workspace recovery protocol.

## Acceptance Coverage

| Spec requirement / criterion | Slice / tasks |
|---|---|
| US1/AC1–US1/AC4 trustworthy baseline/incremental snapshot, insufficient evidence, mandatory coverage | US1: T002–T009 |
| US1/AC5 enclosing-axis insufficient-evidence round trip | US1 Core contract: T005 |
| US2/AC1–US2/AC2 findings, timelines, lineage, and repeat evidence | US2: T002–T005, T010–T012 |
| US2/AC3–US2/AC4 exact safe artifact binding and mandatory/optional URL behavior | US1/US2: T002–T005, T007–T012 |
| US2/AC5 parented immutable collision observation | US1/US2: T002–T005, T007–T008, T010–T012 |
| US2/AC6 mandatory content never truncates/externalizes | US1/US2: T005, T007–T012 |
| US3/AC1–US3/AC4 acknowledgement, approval, immutable history, open-only grill links | US3: T013–T017 |
| Constitution amendment publication contract and migration note | Completed history: T021 / PR #210 |
| Future CardType consumer compatibility before Core expansion | Completed history: T019 / PR #215 |
| FR-001 manual-only source | US1: T001–T002 |
| FR-002 immutable/redacted/provenanced snapshot + sidecar L1–L5 records | US1: T002–T005, T007–T008 |
| FR-003 baseline cohort vs incremental cursors | US1: T002–T005, T007–T008 |
| FR-004 replay/collision/overlap dedupe with accepted parent snapshot | US1: T002–T005, T007–T008; US2: T010–T012 |
| FR-005 scope/mode/version/coverage/limitations display | US1: T004, T007–T008 |
| FR-006 three independent core axes + separate Task Effectiveness | US1: T002–T005, T007–T008 |
| FR-007 reconciled axis/effectiveness counts | US1: T002–T005, T007–T008 |
| FR-008 fingerprints and all six states | US2: T002–T003, T005, T010–T012 |
| FR-009 explicit finding subject/responsibility plus evidence/remediation owner | US1: T002–T005, T007–T008; US2: T010–T012 |
| FR-010 timelines, full feedback lineage, and complete per-role repeat metrics | US2: T002–T003, T005, T010–T012 |
| FR-011 every mandatory generic/team/P0/P1 direct link | US1: T002–T005, T007–T009; assembled T018 |
| FR-012 mandatory invalid-link rejection; optional full-report/externalization/degradation | US1: T002–T005, T007–T008; US2: T010–T012 |
| FR-013 append acknowledgement/approval receipt | US3: T013–T015 |
| FR-014 decision idempotency | US3: T013–T015 |
| FR-015 no canonical snapshot mutation | US3: T014–T015 |
| FR-016 approval grants no remediation/dispatch authority | US3: T014–T017 |
| FR-017 typed sidecar identity/hash and HTTPS-only grill entry points | US1: T002–T005, T007–T008; US2: T010–T012; US3: T014 |
| FR-018 exact size, mandatory rejection, optional externalization, and graceful invalid/future behavior | US1: T005, T007–T008; US2: T011–T012; US3: T014–T015 |
| FR-019 automated contract/boundary coverage | US1: T001–T009; US2: T010–T012; US3: T013–T017; assembled T018 |
| FR-020 enclosing-axis verdict decode and three insufficient-evidence round trips | US1: T005 |
| FR-021 unique/catalog-resolved finding references | Validate: T005; source/preserve: T002–T003; query: T004/T010; pack: T007/T011; render: T008/T012 |
| FR-022 canonical lineage identity and 40-hex merge OID | Validate: T002/T005; preserve: T003/T010; pack/render: T011/T012 |
| FR-023 complete role-round/evidence reconciliation | Validate: T002/T005; preserve/query: T003/T010; pack/render: T011/T012 |
| FR-024 exact priority-aware artifact/report/externalization resolution | Validate: T005; source/preserve/query: T002–T004/T010; pack: T007/T011; render: T008/T012 |
| FR-025 exact eight-section/optional-string/byte Core proofs plus rendered fallback | Core: T005; AIDashUI generic fallback: T008 |
| SC-001/SC-003 complete fixture render and enum round-trip | US1: T005, T007–T009; US2: T010–T012 |
| SC-002 one record per identity, zero overwrites, parented collision observation | US1: T002–T005, T007–T008; US2: T010–T012 |
| SC-004 one receipt per decision kind, immutable source bytes | US3: T013–T015 |
| SC-005 zero invocation/mutation/dispatch/remediation | US1: T001–T002; US3: T014–T017 |
| SC-006 mandatory invalid-link rejection and optional artifact/grill URL policy | US1: T002–T005, T007–T008; US2: T010–T012; US3: T014 |
| SC-007 262,144/262,145 boundary and exact mandatory P0/P1-finding/link counts | US1: T002–T008; US2: T010–T012 |
| Watchdog exit/tree/pipe cleanup without product scope | Completed history: T020 / PR #204 |

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
- Historical T020/T021/T019 remain merged and are never redispatched.
- Team Lead's T005 handoff pins the exact planning commit named by AI Reviewer
  PASS as the implementation base, or an approved descendant with all nine
  planning artifact blobs byte-identical; `fdace13d…` alone is not valid.
- The stale nine-file T005 boundary is superseded: recovery changes exactly
  the eleven listed AIDashCore paths,
  keeps `SchemaValidator.swift`/`URLPolicy.swift` unchanged, contains no
  Models→Validation reference, and satisfies every Core-owned FR-020–FR-025
  proof plus every T005 row of `contracts/t005-acceptance-matrix.md`; T008 owns
  the rendered fallback proof.
- The registered MY-1522 delivery workspace and candidate
  `12577b03c866c73c53fa23d236d2005a68790358` remain preserved evidence until
  exact revised-planning PASS, planning-base pin, and fresh Team Lead handoff;
  this planning task neither mutates nor publishes that candidate.
