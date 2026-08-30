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
| Exact verification | `scripts/context/run AidataFoundation --mode local`; `scripts/context/audit` |
| Dependencies / slice | None; US1 foundation |

- [ ] T002 [US1] Implement immutable bundle collection and normalization in `aidata/adapters/team_audit_snapshot.py`.

| Metadata | T002 |
|---|---|
| Owning layer / context | **AidataL1L2** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/adapters/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/adapters/team_audit_snapshot.py`; `aidata/adapters/CONTEXT.md`; `aidata/CONTEXT.md`; `aidata/tests/test_team_audit_adapter.py`; neutral fixtures under `aidata/tests/fixtures/team_audit/**` |
| Files NOT to touch | `aidata/scripts/**`; `aidata/cli.py`; `aidata/config.py`; `aidata/merge.py`; `aidata/schema/**`; external audit sources; generated raw/clean data |
| Interface / contract | `contracts/manual-import.md` and `data-model.md`: read-only bundle adapter, append-only redacted raw records, normalized stable identities/hashes, optional hosted artifact sidecar |
| Functional acceptance | Valid baseline/incremental fixtures preserve cohort/cursors, instruction hashes, four independent axes, events/attempts/findings/metrics/lineage/limitations; same identity+hash replays once; same identity+different hash never overwrites; overlap event IDs dedupe; path escape/redaction/missing-config cases degrade safely; spies observe zero dispatch/invocation/mutation calls |
| Exact verification | `scripts/context/run AidataL1L2 --mode local`; `scripts/context/audit` |
| Dependencies / slice | T001; US1 import seam (also supplies US2 evidence facts) |

- [ ] T003 [US1] Add immutable Team Audit warehouse facts in `aidata/schema/warehouse.sql` and `aidata/merge.py`.

| Metadata | T003 |
|---|---|
| Owning layer / context | **AidataL3** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/schema/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/schema/warehouse.sql`; `aidata/merge.py`; `aidata/tests/test_warehouse_integrity.py`; `aidata/tests/test_warehouse_quality.py` |
| Files NOT to touch | `aidata/adapters/**`; `aidata/L4_serve/**`; `aidata/L5_apps/**`; generated databases |
| Interface / contract | `data-model.md` warehouse grains: snapshot, axis, case, event, attempt, finding, individual metric, feedback lineage, and artifact facts keyed by snapshot hash and stable child identity |
| Functional acceptance | Merge from normalized fixture produces exactly one row per declared grain; rebuild is idempotent; hash collision cannot update accepted rows; foreign identities and mode/axis reconciliation violations fail that source without fabricating facts; generated DB stays untracked |
| Exact verification | `scripts/context/run AidataL3 --mode local` |
| Dependencies / slice | T002; US1 immutable warehouse |

- [ ] T004 [US1] Add overview queries in `aidata/L4_serve/queries/team-audit/latest-snapshot.sql`, `axis-summary.sql`, and `task-effectiveness.sql`.

| Metadata | T004 |
|---|---|
| Owning layer / context | **AidataL4** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L4_serve/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/L4_serve/queries/team-audit/latest-snapshot.sql`; `aidata/L4_serve/queries/team-audit/axis-summary.sql`; `aidata/L4_serve/queries/team-audit/task-effectiveness.sql`; `aidata/tests/test_query_tiers.py` |
| Files NOT to touch | `aidata/schema/**`; `aidata/merge.py`; `aidata/L5_apps/**`; any write path |
| Interface / contract | Named read-only bundles expose latest accepted snapshot, baseline cohort or incremental cursors, instruction/provenance/coverage/limitations, exactly three core summaries, and separate Task Effectiveness |
| Functional acceptance | Query grain is explicit; deterministic latest ordering uses captured time plus stable snapshot ID; core counts reconcile independently; Task Effectiveness never appears as a core verdict; empty warehouse returns an empty/degraded bundle without mutation |
| Exact verification | `scripts/context/run AidataL4 --mode local` |
| Dependencies / slice | T003; US1 query seam |

- [ ] T005 [P] [US1] Define and validate `teamAudit` in `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`.

| Metadata | T005 |
|---|---|
| Owning layer / context | **AIDashCore** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashCore/CONTEXT.md`; `Packages/AIDashCore/tech-context.md` |
| Files in scope | `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/TeamAuditPayload.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`; `Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift`; `Packages/AIDashCore/Tests/AIDashCoreTests/TeamAuditPayloadInvariantTests.swift`; `Packages/AIDashCore/Tests/AIDashCorePublicAPITests/PublicInitTests.swift` |
| Files NOT to touch | `Packages/AIDashCore/Sources/AIDashCore/Models/UserEvent*.swift` (T013); `Packages/AIDashUI/**`; `Apps/**`; `CLI/**` |
| Interface / contract | `contracts/card-payload.md` and `data-model.md`: one `teamAudit` type, five bounded section variants, locked enums/invariants, no content-derived size downgrade |
| Functional acceptance | Public initializers and ISO-8601 round trips cover every section; baseline/cursor exclusivity, part bounds, exactly-three core axes, separate effectiveness, finite/reconciled counts, all six finding states, fingerprint/hash/text invariants, and 256 KB producer expectation are tested; unknown enums fail to the existing fallback path |
| Exact verification | `scripts/context/run AIDashCore --mode local` |
| Dependencies / slice | None; parallel contract foundation for US1/US2 |

- [ ] T006 [P] [US1] Add `Classification.teamAudit` in `Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift`.

| Metadata | T006 |
|---|---|
| Owning layer / context | **DesignKit** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/DesignKit/CONTEXT.md`; `Packages/DesignKit/tech-context.md` |
| Files in scope | `Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift`; `Packages/DesignKit/Tests/DesignKitTests/ColorSystemTests.swift`; `Packages/DesignKit/Tests/DesignKitTests/ContrastTests.swift` |
| Files NOT to touch | `Packages/AIDashUI/**`; `Packages/AIDashCore/**`; `Theme` seed generation; semantic success/warning/danger tokens |
| Interface / contract | `contracts/card-payload.md`: `teamAudit` classification uses light `#FF2D55`, dark `#FF375F`; product layout/copy remains in AIDashUI |
| Functional acceptance | Enum/tint golden values are locked; badge contrast is measured on supported neutral tiers; no second palette, feature layout, or raw color outside the token source is introduced |
| Exact verification | `scripts/context/run DesignKit --mode local` |
| Dependencies / slice | None; parallel visual-token foundation for US1/US2 |

- [ ] T007 [US1] Map the overview bundle to bounded `teamAudit` cards in `aidata/L5_apps/digest/team_audit.py` and `aidata/L5_apps/digest/aidash.py`.

| Metadata | T007 |
|---|---|
| Owning layer / context | **AidataL5** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L5_apps/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/L5_apps/digest/team_audit.py`; `aidata/L5_apps/digest/sources.py`; `aidata/L5_apps/digest/app.py`; `aidata/L5_apps/digest/aidash.py`; `aidata/tests/test_aidash_payload.py`; `aidata/tests/test_digest_golden.py`; neutral Team Audit fixtures under `aidata/tests/fixtures/**` |
| Files NOT to touch | `aidata/adapters/**`; `aidata/schema/**`; `aidata/L4_serve/**`; `aidata/scripts/**`; Swift/CLI files |
| Interface / contract | Fetch T004 named bundles; emit deterministic overview card/container IDs and `contracts/card-payload.md` JSON; missing/degraded source emits no audit container |
| Functional acceptance | Baseline and incremental overview payloads preserve real L4 values; each payload ≤256 KB; three core axes and Task Effectiveness remain distinct; limitations are never dropped; golden freezes the new fetch seam; default digest does not invoke/import the audit |
| Exact verification | `scripts/context/run AidataL5 --mode local`; `.claude/skills/aidash-content/scripts/contract_check.sh` |
| Dependencies / slice | T004, T005; US1 publication |

- [ ] T008 [US1] Render the Team Audit overview in `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`.

| Metadata | T008 |
|---|---|
| Owning layer / context | **AIDashUI** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashUI/CONTEXT.md`; `Packages/AIDashUI/tech-context.md` |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift`; `Packages/AIDashUI/Sources/AIDashUI/DesignTokens.swift`; `Packages/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/CardRouterTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/DesignTokensComplianceTests.swift` |
| Files NOT to touch | `Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift` (T014); existing card renderers; `Packages/AIDashCore/**`; `Packages/DesignKit/**`; `Apps/**` |
| Interface / contract | Render only the `overview` section per `contracts/card-payload.md`; symbol `checkmark.shield.fill`; colors/tokens from DesignKit/AIDashUI; no persistence |
| Functional acceptance | Scope/mode/cohort-or-cursors/provenance/coverage/limitations render; three core axes are independent and Task Effectiveness has a separate group; size changes geometry/density only; style remains stripe-only; localized, accessible rows and ≥2 previews/tests cover baseline/incremental and fallback |
| Exact verification | `scripts/context/run AIDashUI --mode local`; `.claude/skills/aidash-content/scripts/contract_check.sh` |
| Dependencies / slice | T005, T006; US1 renderer |

- [ ] T009 [P] [US1] Advertise the `teamAudit` schema in `Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift`.

| Metadata | T009 |
|---|---|
| Owning layer / context | **AIDashApp** — `CONTEXT.md` → `Apps/CONTEXT.md` → `Apps/AIDashApp/CONTEXT.md`; constitution §II/Testing |
| Files in scope | `Apps/AIDashApp/Sources/XPCService/XPCPayloadSchemas.swift`; `Apps/AIDashApp/Tests/XPCHandlersContainerCardTests.swift`; `Apps/AIDashApp/Tests/XPCHandlersBriefingTests.swift` |
| Files NOT to touch | `CLI/aidash/**`; `project.yml`; `Apps/AIDashApp/Sources/Sync/UserEventWriter.swift` (T015); CloudKit container/migration files |
| Interface / contract | Existing generic `aidash schema list`/card put paths receive one schema entry matching Core's `teamAudit`; no new CLI command or CloudKit authority |
| Functional acceptance | Schema list exposes the locked section/enums and required fields; valid overview payload is accepted through XPC and invalid payload returns the existing structured schema error; existing card types remain unchanged |
| Exact verification | Local heavy gate: none by repository contract; normal commit/push hooks. Required CI: `xcodebuild -scheme AIDashApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build` and `xcodebuild -scheme AIDashApp -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build` |
| Dependencies / slice | T005; parallel with T007/T008; US1 schema publication |

**US1 checkpoint**: T007 + T008 + T009 complete after their foundations. A
baseline or incremental overview is independently publishable and readable.

## Phase 2: User Story 2 — Inspect findings and evidence (P2)

**Goal**: Add all lifecycle states, redacted timelines, individual metrics,
and safe Archify/full-report relationships without changing the US1 envelope.

**Independent test**: A neutral detail fixture renders all five section kinds,
all six finding states, P0/P1 event-chain evidence, and safe/unsafe links.

- [ ] T010 [US2] Add detail queries in `aidata/L4_serve/queries/team-audit/findings.sql`, `case-timeline.sql`, `individual-metrics.sql`, and `artifacts.sql`.

| Metadata | T010 |
|---|---|
| Owning layer / context | **AidataL4** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L4_serve/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/L4_serve/queries/team-audit/findings.sql`; `aidata/L4_serve/queries/team-audit/case-timeline.sql`; `aidata/L4_serve/queries/team-audit/individual-metrics.sql`; `aidata/L4_serve/queries/team-audit/artifacts.sql`; `aidata/tests/test_query_tiers.py` |
| Files NOT to touch | T004 overview query files; `aidata/schema/**`; `aidata/merge.py`; `aidata/L5_apps/**` |
| Interface / contract | Read-only, explicit-grain bundles for findings, ordered cases/events/attempts, descriptive metrics, artifact/evidence relationships, and URL strings |
| Functional acceptance | Stable IDs and source hashes remain present; all six states survive; P0/P1 artifacts join by fingerprint/event IDs/revision evidence; unsafe URLs are returned as data, never executed; empty optional details return empty bundles with limitations intact |
| Exact verification | `scripts/context/run AidataL4 --mode local` |
| Dependencies / slice | T004; US2 detail query seam |

- [ ] T011 [US2] Partition detail query bundles into `teamAudit` card parts in `aidata/L5_apps/digest/team_audit.py`.

| Metadata | T011 |
|---|---|
| Owning layer / context | **AidataL5** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L5_apps/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/L5_apps/digest/team_audit.py`; `aidata/L5_apps/digest/sources.py`; `aidata/L5_apps/digest/aidash.py`; `aidata/tests/test_aidash_payload.py`; `aidata/tests/test_digest_golden.py`; neutral Team Audit fixtures under `aidata/tests/fixtures/**` |
| Files NOT to touch | `aidata/adapters/**`; `aidata/schema/**`; `aidata/L4_serve/**`; `aidata/scripts/**`; Swift/CLI files |
| Interface / contract | `contracts/card-payload.md` bounded parts: whole-entity chunking, deterministic card IDs, overview first, P0/P1 findings/event chains before lower priority, explicit omission limitation/full-report link |
| Functional acceptance | Findings/timelines/metrics/artifacts map without invented values; no entity is split/truncated; each payload ≤256 KB; part indices/counts reconcile; unsafe/local URLs remain raw non-actionable values for UI policy; all new fetch seams are frozen in golden tests |
| Exact verification | `scripts/context/run AidataL5 --mode local`; `.claude/skills/aidash-content/scripts/contract_check.sh` |
| Dependencies / slice | T007, T010; US2 detail publication |

- [ ] T012 [P] [US2] Render finding, case-timeline, individual-metric, and artifact sections in `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`.

| Metadata | T012 |
|---|---|
| Owning layer / context | **AIDashUI** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashUI/CONTEXT.md`; `Packages/AIDashUI/tech-context.md` |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/SnapshotRenderTests.swift` |
| Files NOT to touch | `CardRouter.swift`/`DesignTokens.swift` owned by T008; `AuditActionEnvironment.swift` and decision controls owned by T014; Core/DesignKit/App files |
| Interface / contract | Render four detail variants; all URLs cross `AIDashCore.URLPolicy`; labels remain visible as text when invalid; no WebView/file/custom scheme |
| Functional acceptance | All six states and four axes have localized textual labels plus tokenized content signals; fingerprints/evidence IDs/revisions stay associated; event order/roles and metric denominators/limitations render; P0/P1 artifact relationship is visible; invalid links are not tappable; row accessibility and wide/hero wrapping comply |
| Exact verification | `scripts/context/run AIDashUI --mode local`; `.claude/skills/aidash-content/scripts/contract_check.sh` |
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
| Exact verification | `scripts/context/run AIDashCore --mode local` |
| Dependencies / slice | T005; US3 event contract |

- [ ] T014 [US3] Add audit decision intents and receipt rendering in `Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift`.

| Metadata | T014 |
|---|---|
| Owning layer / context | **AIDashUI** — `CONTEXT.md` → `Packages/CONTEXT.md` → `Packages/AIDashUI/CONTEXT.md`; `Packages/AIDashUI/tech-context.md` |
| Files in scope | `Packages/AIDashUI/Sources/AIDashUI/CardView/AuditActionEnvironment.swift`; `Packages/AIDashUI/Sources/AIDashUI/CardView/TeamAuditCardView.swift`; `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`; `Packages/AIDashUI/Tests/AIDashUITests/TeamAuditCardViewTests.swift`; `Packages/AIDashUI/Tests/AIDashUITests/AuditActionEnvironmentTests.swift` |
| Files NOT to touch | `StarActionEnvironment.swift`; other card views; Core/DesignKit/App files |
| Interface / contract | Optional acknowledge/approve closures take `(cardId, findingFingerprint)`; acknowledged/approved fingerprint sets drive receipt copy; defaults nil/empty |
| Functional acceptance | Buttons exist only for finding sections and carry exact stable fingerprint; approval copy says separate remediation; receipt sets never replace canonical state; nil environments are no-op; spy tests prove calls and zero extra side effects; HTTPS grill links only open Link destinations; hit targets/localization/accessibility comply |
| Exact verification | `scripts/context/run AIDashUI --mode local` |
| Dependencies / slice | T012, T013; US3 UI intent seam |

- [ ] T015 [US3] Persist and inject audit receipts in `Apps/AIDashApp/Sources/Sync/UserEventWriter.swift` and `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`.

| Metadata | T015 |
|---|---|
| Owning layer / context | **AIDashApp** — `CONTEXT.md` → `Apps/CONTEXT.md` → `Apps/AIDashApp/CONTEXT.md`; constitution §I/II/Testing |
| Files in scope | `Apps/AIDashApp/Sources/Sync/UserEventWriter.swift`; `Apps/AIDashApp/Sources/Scenes/AuditFeedbackActions.swift`; `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`; `Apps/AIDashApp/Tests/UserEventWriterTests.swift`; `Apps/AIDashApp/Tests/AuditFeedbackWiringTests.swift`; `Apps/AIDashApp/Tests/BriefingWindowSceneLocalizationTests.swift` |
| Files NOT to touch | CloudKit container/migration files; XPC schema files owned by T009; CLI/project wiring; Core/UI/aidata files |
| Interface / contract | App adapter for `contracts/owner-decision-events.md`: append one row per local `(cardId,fingerprint,action)`, inject closures and derived receipt sets, swallow persistence failure without confirmation |
| Functional acceptance | In-memory store proves acknowledgement/approval append-only idempotency; existing rows are never updated/deleted; receipt derivation collapses cross-device duplicates by fingerprint/action; scene injects both intents/sets; snapshot payload bytes remain unchanged; spies show only UserEventWriter is called and no issue/run/agent/remediation interface exists |
| Exact verification | Local heavy gate: none by repository contract; optional focused feedback only: `xcodebuild -scheme AIDashAppLogicTests -destination 'platform=macOS' test`. Required CI: App macOS/iOS build gates from `Apps/AIDashApp/CONTEXT.md` |
| Dependencies / slice | T009, T014; US3 persistence/wiring |

- [ ] T016 [P] [US3] Preserve audit decision actions in `aidata/adapters/aidash_events.py`.

| Metadata | T016 |
|---|---|
| Owning layer / context | **AidataL1L2** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/adapters/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/adapters/aidash_events.py`; `aidata/tests/test_aidash_events_adapter.py` |
| Files NOT to touch | `team_audit_snapshot.py` owned by T002; warehouse/query/L5 files; aidata scripts/cron; Swift/App files |
| Interface / contract | Event normalizer preserves both locked action strings, finding fingerprint in `item_ref`, and `teamAudit` in `card_type`; existing done/undone/star behavior is unchanged |
| Functional acceptance | New events never normalize action to null/unknown; old events without card type remain compatible; redaction and no-config degradation persist; adapter only reads `aidash events pull` output and does not invoke an audit or remediation |
| Exact verification | `scripts/context/run AidataL1L2 --mode local` |
| Dependencies / slice | T002, T013; parallel with T014/T015 where files do not conflict; US3 feedback lineage |

**US3 checkpoint**: T015 + T016 complete. The Owner can record and see safe
decision receipts; canonical snapshot state and execution systems are untouched.

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
US3 UI:   T012 + T013 → T014
US3 App:  T009 + T014 → T015
US3 data: T002 + T013 → T016
US3 done: T015 + T016
```

Parallel tasks marked `[P]` have non-conflicting files. T012 may run in
parallel with T010/T011 after T008 because both consume the locked Core
contract. T016 may run in parallel with UI/App work after T013.

## Acceptance Coverage

| Spec requirement / criterion | Slice / tasks |
|---|---|
| FR-001 manual-only source | US1: T001–T002 |
| FR-002 immutable/redacted/provenanced L1–L5 records | US1: T002–T004, T007 |
| FR-003 baseline cohort vs incremental cursors | US1: T002–T005, T007–T008 |
| FR-004 replay/collision/overlap dedupe | US1: T002–T003 |
| FR-005 scope/mode/version/coverage/limitations display | US1: T004, T007–T008 |
| FR-006 three independent core axes + separate Task Effectiveness | US1: T002–T005, T007–T008 |
| FR-007 reconciled axis/effectiveness counts | US1: T002–T005, T007–T008 |
| FR-008 fingerprints and all six states | US2: T002–T003, T005, T010–T012 |
| FR-009 finding evidence and remediation owner | US2: T002–T003, T010–T012 |
| FR-010 timelines and individual metrics | US2: T002–T003, T010–T012 |
| FR-011 generic/team/P0/P1 artifact links | US2: T002–T003, T010–T012 |
| FR-012 artifact evidence relationship + invalid-link degradation | US2: T002, T010–T012 |
| FR-013 append acknowledgement/approval receipt | US3: T013–T015 |
| FR-014 decision idempotency | US3: T013–T015 |
| FR-015 no canonical snapshot mutation | US3: T014–T015 |
| FR-016 approval grants no remediation/dispatch authority | US3: T014–T016 |
| FR-017 HTTPS-only grill entry points | US2: T011–T012; US3: T014 |
| FR-018 graceful invalid/incomplete/future payload behavior | US1: T005, T008; US2: T012; US3: T014–T015 |
| FR-019 automated contract/boundary coverage | US1: T001–T009; US2: T010–T012; US3: T013–T016 |
| SC-001/SC-003 complete fixture render and enum round-trip | US1: T005, T007–T009; US2: T010–T012 |
| SC-002 one record per stable identity, zero overwrites | US1: T002–T003 |
| SC-004 one receipt per decision kind, immutable source bytes | US3: T013–T015 |
| SC-005 zero invocation/mutation/dispatch/remediation | US1: T001–T002; US3: T014–T016 |
| SC-006 URL policy for artifact/grill links | US2: T010–T012; US3: T014 |

## Definition of Done

- Every task stays inside its listed files plus only the tests already listed.
- Each layer's exact resolver gate passes through normal hook-driven workflow.
- `scripts/context/audit` reports zero findings after routing changes.
- `.claude/skills/aidash-content/scripts/contract_check.sh` confirms the
  Core/App/UI/aidata card seam after assembled changes.
- The implementation PR's required CI App/CLI/aidata/review checks pass.
- No host-based AIDashApp test is run locally.
- Exact implementation SHA matches local HEAD, pushed branch, and PR head
  before independent implementation review.
