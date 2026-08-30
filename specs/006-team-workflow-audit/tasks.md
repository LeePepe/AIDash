# Tasks: On-Demand Team Workflow Audit

**Input**: Design documents in `specs/006-team-workflow-audit/`

**Organization**: Each user-story phase is a vertical product slice. Every
executable row owns one resolver layer; cross-layer behavior is locked by the
contracts and blocking edges below. Constitution §Cross-Cutting Quality Bars
applies to every task.

## Phase 1: User Story 1 — Read a trustworthy snapshot (P1 / MVP)

**Goal**: Explicitly import a baseline or incremental snapshot and display its
scope, provenance, limitations, three core axes, and separate Task
Effectiveness in today's briefing.

**Independent test**: Neutral baseline and incremental fixtures traverse the
manual import, immutable facts, named queries, bounded card mapping, and
overview renderer; default collection performs no audit import or invocation.

- [ ] T001 [US1] Add the manual-only source registry in `aidata/cli.py`, `aidata/config.py`, and `aidata/config_local.example.py`.

| Metadata | T001 |
|---|---|
| Owning layer / context | **AidataFoundation** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/CONTEXT.foundation.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/cli.py`; `aidata/config.py`; `aidata/config_local.example.py`; `aidata/CONTEXT.md`; `aidata/CONTEXT.foundation.md`; `aidata/tests/test_team_audit_manual_source.py` |
| Files NOT to touch | `aidata/scripts/**`; `aidata/adapters/**`; `aidata/schema/**`; any cron or machine-local config |
| Interface / contract | `contracts/manual-import.md`: `MANUAL_SOURCES` is selectable only with explicit `--source`; default source iteration excludes it; empty ignored-local import root returns zero |
| Functional acceptance | Parser accepts `team_audit_snapshot` explicitly for collect/normalize; default collect/normalize never selects it; neutral default contains no identity/path; no schedule, subprocess, network, or audit invocation is introduced; new test path is routed to AidataFoundation |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataFoundation tests and the routing audit must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | None; US1 foundation |

- [ ] T002 [US1] Implement immutable bundle collection and normalization in `aidata/adapters/team_audit_snapshot.py`.

| Metadata | T002 |
|---|---|
| Owning layer / context | **AidataL1L2** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/adapters/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/adapters/team_audit_snapshot.py`; `aidata/adapters/CONTEXT.md`; `aidata/CONTEXT.md`; `aidata/tests/test_team_audit_adapter.py`; neutral fixtures under `aidata/adapters/fixtures/team_audit/**` |
| Files NOT to touch | `aidata/tests/fixtures/**` (AidataL5-owned); `aidata/scripts/**`; `aidata/cli.py`; `aidata/config.py`; `aidata/merge.py`; `aidata/schema/**`; external audit sources; generated raw/clean data |
| Interface / contract | `contracts/manual-import.md` and `data-model.md`: read-only bundle adapter, append-only redacted raw records, explicit finding subject/responsibility, exact feedback-lineage/agent-repeat fields, stable sidecar ID/exact byte hash, and independently keyed collision observations with accepted parent snapshot ID/hash |
| Functional acceptance | Fixtures preserve cohort/cursors, instruction hashes, axes, explicit finding `subject_id`/`responsibility_layer`, lineage/repeat values, limitations, artifacts/grill fields, and importer-computed sidecar ID/hash; same identity+hash replays; snapshot/child/sidecar identity+different hash appends a parented collision observation and never overwrites/stores rejected content; overlap IDs dedupe; path/redaction/missing-config cases degrade safely; spies observe zero dispatch/invocation/mutation calls |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL1L2 tests and the routing audit must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T001; US1 import seam (also supplies US2 evidence facts) |

- [ ] T003 [US1] Add immutable Team Audit warehouse facts in `aidata/schema/warehouse.sql` and `aidata/merge.py`.

| Metadata | T003 |
|---|---|
| Owning layer / context | **AidataL3** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/schema/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/schema/warehouse.sql`; `aidata/merge.py`; `aidata/tests/test_warehouse_integrity.py`; `aidata/tests/test_warehouse_quality.py` |
| Files NOT to touch | `aidata/adapters/**`; `aidata/L4_serve/**`; `aidata/L5_apps/**`; generated databases |
| Interface / contract | `data-model.md` grains/bridges: snapshot, axis, case/event/attempt/finding with explicit subject/responsibility, metrics/lineage/repeats, sidecar identity/hash, collision observations with parent snapshot ID/hash, artifacts, and grill links, all retaining immutable provenance |
| Functional acceptance | Merge produces one row per grain/bridge; accepted facts never update; parented collision IDs merge independently; finding identity fields, full lineage/repeats, exact sidecar hash, and sidecar foreign keys on artifact/grill rows round-trip; same sidecar ID/different hash observes a collision; foreign/mode/axis violations fabricate nothing; generated DB stays untracked |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL3 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T002; US1 immutable warehouse |

- [ ] T004 [US1] Add overview and required-publication input queries under `aidata/L4_serve/queries/team-audit/`.

| Metadata | T004 |
|---|---|
| Owning layer / context | **AidataL4** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L4_serve/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/L4_serve/queries/team-audit/latest-snapshot.sql`; `aidata/L4_serve/queries/team-audit/axis-summary.sql`; `aidata/L4_serve/queries/team-audit/task-effectiveness.sql`; `aidata/L4_serve/queries/team-audit/required-publication-inputs.sql`; `aidata/L4_serve/queries/team-audit/mandatory-findings.sql`; `aidata/L4_serve/queries/team-audit/mandatory-artifacts.sql`; `aidata/L4_serve/queries/team-audit/import-collision-summary.sql`; `aidata/tests/test_query_tiers.py` |
| Files NOT to touch | `aidata/schema/**`; `aidata/merge.py`; `aidata/L5_apps/**`; any write path |
| Interface / contract | Named read-only bundles expose accepted snapshot/sidecar provenance, cohort/cursors, axes/effectiveness, collision summary, and required entity/count inputs including exact `requiredP0P1FindingCount` plus generic/team/P0/P1-artifact counts; L4 has no published/omitted/externalized result |
| Functional acceptance | Query grains are explicit; latest ordering is deterministic; finding subject/responsibility and parented collisions survive; sidecar ID/hash reaches every required input; `requiredP0P1FindingCount` derives from immutable mandatory-finding facts independently of chain counts; columns named `published*`, `omitted*`, or `externalized*` are absent; query fixtures cover zero/one/multiple required P0/P1 findings; empty warehouse returns an empty/degraded bundle |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL4 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T003; US1 query seam |

- [ ] T005 [P] [US1] Define and validate `teamAudit` in `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`.

| Metadata | T005 |
|---|---|
| Owning layer / context | **AIDashCore** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashCore/CONTEXT.md`; `Packages/AIDashCore/tech-context.md` |
| Files in scope | `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`; `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift` |
| Files NOT to touch | `Packages/AIDashCore/Sources/AIDashCore/Models/UserEvent*.swift` (T013); `Packages/AIDashUI/**`; `Apps/**`; `CLI/**` |
| Interface / contract | `contracts/card-payload.md` and `data-model.md`: one `teamAudit` type, eight variants, explicit finding identity, parented collisions, snapshot+sidecar provenance, L5-computed coverage including `requiredP0P1FindingCount` / `publishedP0P1FindingCount`, full-report/externalization types, locked enums/invariants, and no content-derived size downgrade |
| Functional acceptance | Round trips cover exact source fields; findings require subject/responsibility; collisions require parent snapshot ID/hash; every payload requires sidecar ID/hash; baseline/cursor, parts, axes/effectiveness, states, repeat union, independent P0/P1-finding/chain coverage reconciliation, untrusted URLs, and encoded size are tested; invariant fixtures reject unequal finding counts even when chain counts match; 262,144 accepts/262,145 mandatory rejects; CardType count 10→11; unknown enums use fallback |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashCore Swift build/test gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | None; parallel contract foundation for US1/US2 |

- [ ] T006 [P] [US1] Add the contrast-calibrated `Classification.teamAudit` in `Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift`.

| Metadata | T006 |
|---|---|
| Owning layer / context | **DesignKit** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/DesignKit/CONTEXT.md`; `Packages/DesignKit/tech-context.md` |
| Files in scope | `Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift`; `Packages/DesignKit/Tests/DesignKitTests/ColorSystemTests.swift`; `Packages/DesignKit/Tests/DesignKitTests/ContrastTests.swift` |
| Files NOT to touch | `Packages/AIDashUI/**`, including the shared `CardTypeBadge` 15%-fill recipe; `Packages/AIDashCore/**`; `Theme` seed generation; semantic success/warning/danger tokens |
| Interface / contract | `contracts/card-payload.md`: `teamAudit` classification uses light `#E6294D`, dark `#FF375F`; the glyph remains full tint over the same tint source-over composited at `0.15` alpha; product layout/copy remains in AIDashUI |
| Functional acceptance | Golden values lock the exact pair; a measured test asserts `ratio(tint, composite(tint, ground, 0.15)) >= 3.0` for `Neutral.allCases` × both schemes × `card`/`inner`/`bg`; no second palette, badge-recipe special case, feature layout, semantic-token change, or raw color outside the token source is introduced |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected DesignKit Swift build/test gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | None; parallel visual-token foundation for US1/US2 |

- [ ] T007 [US1] Map the overview bundle to bounded `teamAudit` cards in `aidata/L5_apps/digest/team_audit.py` and `aidata/L5_apps/digest/aidash.py`.

| Metadata | T007 |
|---|---|
| Owning layer / context | **AidataL5** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L5_apps/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/L5_apps/digest/team_audit.py`; `aidata/L5_apps/digest/sources.py`; `aidata/L5_apps/digest/app.py`; `aidata/L5_apps/digest/aidash.py`; `aidata/tests/test_aidash_payload.py`; `aidata/tests/test_digest_golden.py`; neutral fixtures under `aidata/tests/fixtures/team_audit/**` |
| Files NOT to touch | `aidata/adapters/**`; `aidata/schema/**`; `aidata/L4_serve/**`; `aidata/scripts/**`; Swift/CLI files |
| Interface / contract | Fetch T004 immutable required inputs; pack the US1 overview plus every mandatory P0/P1 finding and generic/team/P0/P1 artifact; compute final `PublicationCoverage`/full-report state in L5 after packing, including independent `requiredP0P1FindingCount` / `publishedP0P1FindingCount`; emit snapshot+sidecar provenance and deterministic IDs |
| Functional acceptance | US1 publishes overview and all mandatory findings/artifacts independently; L5—not L4—computes published/omitted/externalized counts after final packing; P0/P1-finding and every mandatory-link required/published pair match independently; boundary/golden fixtures cover zero/one/multiple mandatory findings and reject a missing or oversized finding without letting its chain satisfy the finding count; mandatory invalid URLs/oversize reject; optional invalid links are not part of mandatory counts; finding identity, collision parent, sidecar ID/hash, axes/limitations survive; payloads ≤262,144; golden freezes seams; default digest invokes no audit |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL5 pytest/ruff gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T004, T005; US1 publication |

- [ ] T008 [US1] Render the Team Audit overview in `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`.

| Metadata | T008 |
|---|---|
| Owning layer / context | **AIDashUI** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashUI/CONTEXT.md`; `Packages/AIDashUI/tech-context.md` |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift`; `Packages/AIDashUI/Sources/AIDashUI/DesignTokens.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/CardRouterTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/DesignTokensComplianceTests.swift` |
| Files NOT to touch | `Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift` (T014); existing card renderers; `Packages/AIDashCore/**`; `Packages/DesignKit/**`; `Apps/**` |
| Interface / contract | Render the US1 `overview`, mandatory P0/P1 `findings`, and mandatory `artifacts` sections read-only; sidecar/snapshot provenance and optional URLs use Core policy; symbol/tokens remain in DesignKit/AIDashUI; no persistence |
| Functional acceptance | Scope/cohort-or-cursors/axes/limitations and L5-computed coverage render, including independently matched P0/P1-finding and mandatory-link count pairs; mandatory findings show explicit subject/responsibility; mandatory artifacts are direct validated links with sidecar identity/hash; collision summary retains parent; invalid mandatory entries never reach a published card; size/style orthogonality, localization, accessibility, and ≥2 previews cover baseline/incremental/rejected fallback |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashUI Swift build/test gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T005, T006; US1 renderer |

- [ ] T009 [P] [US1] Advertise the `teamAudit` schema in `Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift`.

| Metadata | T009 |
|---|---|
| Owning layer / context | **AIDashApp** — `CONTEXT.md` → `Apps/CONTEXT.md` → `Apps/AIDashApp/CONTEXT.md`; constitution §II/Testing |
| Files in scope | `Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift`; `Apps/AIDashApp/Tests/XPCHandlersContainerCardTests.swift`; `Apps/AIDashApp/Tests/XPCHandlersBriefingTests.swift` |
| Files NOT to touch | `CLI/aidash/**`; `project.yml`; `Apps/AIDashApp/Sources/Sync/UserEventWriter.swift` (T015); CloudKit container/migration files |
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

- [ ] T010 [US2] Add typed optional-detail queries under `aidata/L4_serve/queries/team-audit/`.

| Metadata | T010 |
|---|---|
| Owning layer / context | **AidataL4** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L4_serve/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/L4_serve/queries/team-audit/optional-findings.sql`; `aidata/L4_serve/queries/team-audit/case-timeline.sql`; `aidata/L4_serve/queries/team-audit/individual-metrics.sql`; `aidata/L4_serve/queries/team-audit/feedback-lineage.sql`; `aidata/L4_serve/queries/team-audit/agent-repeat-metrics.sql`; `aidata/L4_serve/queries/team-audit/import-collision-observations.sql`; `aidata/L4_serve/queries/team-audit/optional-artifacts.sql`; `aidata/L4_serve/queries/team-audit/grill-links.sql`; `aidata/tests/test_query_tiers.py` |
| Files NOT to touch | T004 mandatory/overview query files; `aidata/schema/**`; `aidata/merge.py`; `aidata/L5_apps/**` |
| Interface / contract | Read-only optional-detail bundles for P2/info findings/artifacts, cases, metrics, lineage, repeats, parented collision observations, and grill strings; required entity inputs remain T004-owned and no query computes publication results |
| Functional acceptance | Stable snapshot+sidecar IDs/hashes survive; optional findings preserve subject/responsibility; lineage/repeats and collision parent/accepted/rejected hashes round-trip; optional unsafe artifact/grill URLs remain data; no `published*`/omitted/externalized columns; empty optional details return empty bundles with limitations intact |
| Exact verification | Normal `git commit` and `git push` with configured hooks; the hook-selected AidataL4 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T004; US2 detail query seam |

- [ ] T011 [US2] Partition detail query bundles into `teamAudit` card parts in `aidata/L5_apps/digest/team_audit.py`.

| Metadata | T011 |
|---|---|
| Owning layer / context | **AidataL5** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L5_apps/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/L5_apps/digest/team_audit.py`; `aidata/L5_apps/digest/sources.py`; `aidata/L5_apps/digest/aidash.py`; `aidata/tests/test_aidash_payload.py`; `aidata/tests/test_digest_golden.py`; neutral fixtures under `aidata/tests/fixtures/team_audit/**` |
| Files NOT to touch | `aidata/adapters/**`; `aidata/schema/**`; `aidata/L4_serve/**`; `aidata/scripts/**`; Swift/CLI files |
| Interface / contract | `contracts/card-payload.md`: add optional P2/info findings/artifacts, timelines, metrics, lineage, repeats, parented collisions, and grill links after T007's mandatory publication; stable two-pass packing, 262,144-byte limit, and typed optional externalization |
| Functional acceptance | Optional details map without invented values and preserve finding identity, collision parent, and sidecar provenance; no entity splits/truncates; T007's mandatory cards/counts remain unchanged; oversized optional detail externalizes only with a valid full report and otherwise rejects; 262,144/262,145 plus with/without-report fixtures pass; unsafe optional URLs remain raw for UI policy; fetch seams are frozen |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL5 pytest/ruff gates must exit 0. Cross-language contract verification is deferred to assembled T018. |
| Dependencies / slice | T007, T010; US2 detail publication |

- [ ] T012 [P] [US2] Render all non-overview audit sections in `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`.

| Metadata | T012 |
|---|---|
| Owning layer / context | **AIDashUI** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashUI/CONTEXT.md`; `Packages/AIDashUI/tech-context.md` |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/SnapshotRenderTests.swift` |
| Files NOT to touch | `CardRouter.swift`/`DesignTokens.swift` owned by T008; `AuditActionEnvironment.swift` and decision controls owned by T014; Core/DesignKit/App files |
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

- [ ] T013 [P] [US3] Add audit decision actions and factories in `Packages/AIDashCore/Sources/AIDashCore/Models/UserEventAction.swift` and `UserEvent.swift`.

| Metadata | T013 |
|---|---|
| Owning layer / context | **AIDashCore** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashCore/CONTEXT.md`; `Packages/AIDashCore/tech-context.md` |
| Files in scope | `Packages/AIDashCore/Sources/AIDashCore/Models/UserEventAction.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/UserEvent.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CodableStructRoundTripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/EnumRoundtripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/UserEventModelTests.swift`; `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift` |
| Files NOT to touch | `TeamAuditPayload.swift`/`CardType.swift` owned by T005; storage schema; UI/App/aidata files |
| Interface / contract | `contracts/owner-decision-events.md`: raw actions `auditFindingAcknowledged` and `auditFindingRemediationApproved`; factories set `itemRef=fingerprint`, `cardType=teamAudit` |
| Functional acceptance | Both raw values and factories round-trip; fingerprint/card/type/action are exact; existing done/undone/star behavior is unchanged; empty fingerprint is rejected through a documented graceful error contract; no remediation interface exists |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashCore Swift build/test gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T005; US3 event contract |

- [ ] T014 [US3] Add audit decision intents and receipt rendering in `Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift`.

| Metadata | T014 |
|---|---|
| Owning layer / context | **AIDashUI** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashUI/CONTEXT.md`; `Packages/AIDashUI/tech-context.md` |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift`; `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/AuditActionEnvironmentTests.swift` |
| Files NOT to touch | `StarActionEnvironment.swift`; other card views; Core/DesignKit/App files |
| Interface / contract | Optional acknowledge/approve closures take `(cardId, findingFingerprint)`; acknowledged/approved fingerprint sets drive receipt copy; defaults nil/empty |
| Functional acceptance | Buttons exist only for finding sections and carry exact stable fingerprint; approval copy says separate remediation; receipt sets never replace canonical state; nil environments are no-op; spy tests prove calls and zero extra side effects; HTTPS grill links only open Link destinations; hit targets/localization/accessibility comply |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AIDashUI Swift build/test gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T012, T013; US3 UI intent seam |

- [ ] T015 [US3] Persist and inject audit receipts in `Apps/AIDashApp/Sources/Sync/UserEventWriter.swift` and `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`.

| Metadata | T015 |
|---|---|
| Owning layer / context | **AIDashApp** — `CONTEXT.md` → `Apps/CONTEXT.md` → `Apps/AIDashApp/CONTEXT.md`; constitution §I/II/Testing |
| Files in scope | `Apps/AIDashApp/Sources/Sync/UserEventWriter.swift`; `Apps/AIDashApp/Sources/Scenes/AuditFeedbackActions.swift`; `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`; `Apps/AIDashApp/Tests/UserEventWriterTests.swift`; `Apps/AIDashApp/Tests/AuditFeedbackWiringTests.swift`; `Apps/AIDashApp/Tests/BriefingWindowSceneLocalizationTests.swift` |
| Files NOT to touch | CloudKit container/migration files; XPC schema files owned by T009; CLI/project wiring; Core/UI/aidata files |
| Interface / contract | App adapter for `contracts/owner-decision-events.md`: append one row per local `(cardId,fingerprint,action)`, inject closures and derived receipt sets, swallow persistence failure without confirmation |
| Functional acceptance | In-memory store proves acknowledgement/approval append-only idempotency; existing rows are never updated/deleted; receipt derivation collapses cross-device duplicates by fingerprint/action; scene injects both intents/sets; snapshot payload bytes remain unchanged; spies show only UserEventWriter is called and no issue/run/agent/remediation interface exists |
| Exact verification | Normal `git commit` and `git push` with configured hooks; no proactive local App test. Required CI gates are App `macos-build` and `ios-build`; a hostless focused rerun is diagnostic only after a concrete App-layer failure. |
| Dependencies / slice | T009, T014; US3 persistence/wiring |

- [ ] T016 [P] [US3] Preserve audit decision actions in `aidata/adapters/aidash_events.py`.

| Metadata | T016 |
|---|---|
| Owning layer / context | **AidataL1L2** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/adapters/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/adapters/aidash_events.py`; `aidata/tests/test_aidash_events_adapter.py` |
| Files NOT to touch | `team_audit_snapshot.py` owned by T002; warehouse/query/L5 files; aidata scripts/cron; Swift/App files |
| Interface / contract | Event normalizer preserves both locked action strings, finding fingerprint in `item_ref`, and `teamAudit` in `card_type`; existing done/undone/star behavior is unchanged |
| Functional acceptance | New events never normalize action to null/unknown; old events without card type remain compatible; redaction and no-config degradation persist; adapter only reads `aidash events pull` output and does not invoke an audit or remediation |
| Exact verification | Normal `git commit` and `git push` with configured hooks; hook-selected AidataL1L2 pytest/ruff gates must exit 0. A focused resolver rerun is diagnostic only after an emitted hook failure. |
| Dependencies / slice | T002, T013; parallel with T014/T015 where files do not conflict; US3 feedback lineage |

- [ ] T017 [P] [US3] Extend audit-action filtering in `CLI/aidash/Sources/Commands/EventsPullCommand.swift`.

| Metadata | T017 |
|---|---|
| Owning layer / context | **aidashCLI** — `CONTEXT.md` → `CLI/CONTEXT.md` → `CLI/aidash/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `CLI/aidash/Sources/Commands/EventsPullCommand.swift`; `CLI/aidash/Tests/EventsPullCommandTests.swift` |
| Files NOT to touch | `Packages/AIDashCore/**` (T013); `Apps/**`; `Packages/AIDashUI/**`; `project.yml`; any CLI command other than events pull |
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

- [ ] T018 [US3] Correct and gate the assembled checker in `.claude/skills/aidash-content/scripts/contract_check.sh`.

| Metadata | T018 |
|---|---|
| Owning layer / context | **RepoInfra integration-only** — `CONTEXT.md` → `scripts/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `.claude/skills/aidash-content/scripts/contract_check.sh`; `.claude/skills/aidash-content/references/anchors.md`; `scripts/CONTEXT.md`; `scripts/context/tests/test_contract_check.py` |
| Files NOT to touch | `Packages/**`; `Apps/**`; `CLI/**`; `aidata/**`; `scripts/hooks/**`; any product contract or implementation file |
| Interface / contract | Internal checker resolves the current Git worktree, checks Core `CardType`, App `XPCPayloadSchemas.swift`, UI `CardRouter`, and AidataL5 `team_audit.py`/`aidash.py`, and is registered as a RepoInfra lint gate |
| Functional acceptance | No `$HOME/Development/AIDash` or other fixed checkout; schema anchor is `Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift`; mapper coverage includes the new audit module; tests prove cwd independence, correct anchors, and a failing drift case; the normal hook-selected RepoInfra gate runs the checker against the assembled revision exactly once |
| Exact verification | Normal `git commit` and `git push` with configured hooks after all dependencies; the updated RepoInfra local gate, including the registered contract checker and regression tests, must exit 0. No proactive standalone checker/test invocation. |
| Dependencies / slice | T007, T008, T009, T011, T012, T015, T016, T017; final US1–US3 integration-only verification |

## Dependency and Scheduling Summary

```text
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

## Acceptance Coverage

| Spec requirement / criterion | Slice / tasks |
|---|---|
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
| SC-001/SC-003 complete fixture render and enum round-trip | US1: T005, T007–T009; US2: T010–T012 |
| SC-002 one record per identity, zero overwrites, parented collision observation | US1: T002–T005, T007–T008; US2: T010–T012 |
| SC-004 one receipt per decision kind, immutable source bytes | US3: T013–T015 |
| SC-005 zero invocation/mutation/dispatch/remediation | US1: T001–T002; US3: T014–T017 |
| SC-006 mandatory invalid-link rejection and optional artifact/grill URL policy | US1: T002–T005, T007–T008; US2: T010–T012; US3: T014 |
| SC-007 262,144/262,145 boundary and exact mandatory P0/P1-finding/link counts | US1: T002–T008; US2: T010–T012 |

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
