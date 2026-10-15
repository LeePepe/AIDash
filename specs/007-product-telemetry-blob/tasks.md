# Tasks: Product Telemetry Blob Pipeline

## Execution contract

These are implementation tasks for later delivery, not authority to implement during `SL-AID-PLAN`. Every `Txxx` has one owning layer. Routing/context files listed with a task are the minimum metadata needed to register that same layer's new manifest or tests; they do not transfer ownership of product code across layers.

Tasks within `SL-AID-PRODUCER` assemble one candidate tree before publication because dependency, release plumbing, and app logic are not independently useful. Tasks within `SL-DATA` follow the stated forward edges. E2E-05 is an external evidence milestone, not a repository implementation task.

## Phase 1: Foundation and dependency plumbing

- [ ] **T001 [DATA-FOUND]** Add the single-mode reader configuration, exact Azure Identity lock, and source registration.

| Metadata | T001 |
|---|---|
| Owning layer / context | **AidataFoundation** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/CONTEXT.foundation.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/requirements.lock` (new, every direct/transitive version exact); `aidata/config.py`; `aidata/config_local.example.py`; `aidata/tests/test_config_m3.py`; `aidata/CONTEXT.md`; `aidata/CONTEXT.foundation.md` |
| Files NOT to touch | `.github/**` (T002); `aidata/adapters/**` (T006); merge/schema/query/scripts/L5; Swift/App/Configs/fastlane |
| Interface / contract | `contracts/reader-auth.md`; one empty `PRODUCT_BLOB_CONTAINER_URL`; no credential/auth-mode fields; `product_blob` in exact `SOURCES` and `MERGE_SOURCES`; routed exact dependency lock |
| Functional acceptance | Empty or query/userinfo/fragment-bearing selector is disabled; tracked example is empty/neutral; no token/SAS/account/principal value exists; lock contains exactly audited compatible `azure-identity` and transitive versions; fresh-clone config imports without local override; source registries assert exact equality |
| Verification | `/usr/bin/python3 -m pytest aidata/tests/test_config_m3.py -q`; `scripts/context/run AidataFoundation --mode local`; `scripts/context/audit`; dependency/license/vulnerability evidence for exact lock |
| Dependencies / slice | Exact planning PASS and OA-002 `aad-owner-local`; opens `SL-DATA` |

- [ ] **T002 [AID-DEP]** Install and gate the exact aidata dependency lock in CI.

| Metadata | T002 |
|---|---|
| Owning layer / context | **RepoInfra** — `CONTEXT.md` → `scripts/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `.github/workflows/build.yml`; `scripts/ci/tests/test_aidata_dependency_install.py` (new) |
| Files NOT to touch | `aidata/**` (T001/T006–T009); `.github/workflows/testflight.yml` (T004); product/Swift/Configs/fastlane |
| Interface / contract | CI installs only `aidata/requirements.lock` before aidata pytest/Ruff and fails closed on missing/unpinned entries; no credentials or indexes beyond the configured package source |
| Functional acceptance | Workflow no longer claims stdlib-only; structural test proves exact lock install occurs before pytest/Ruff, uses no floating upgrade flag, and retains existing Python/ruff gates |
| Verification | `/usr/bin/python3 -m pytest scripts/ci/tests/test_aidata_dependency_install.py -q`; `scripts/context/run RepoInfra --mode local`; required aidata CI |
| Dependencies / slice | T001 manifest; required before T006 imports Azure Identity |

## Phase 2: AIDash GUI producer

- [ ] **T003 [AID-XCODE]** Wire immutable LokiKit, empty host configuration, hostless test product, and Fastlane path-only xcconfig consumption.

| Metadata | T003 |
|---|---|
| Owning layer / context | **XcodeWorkspace** — `CONTEXT.md` → `Configs/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `project.yml`; `Configs/Identity.xcconfig`; `Configs/Identity.local.xcconfig.example`; `fastlane/Fastfile` |
| Files NOT to touch | generated `AIDash.xcodeproj`; `.github/**`/`scripts/ci/**` (T004); `Apps/**` (T005); Packages/Core/UI/CLI; aidata |
| Interface / contract | ADR-004 and `contracts/blob-wire.md`; exact REL-001-approved LokiKit product on AIDashApp and AIDashAppLogicTests only; both host keys expand from empty build settings; Fastlane accepts only an xcconfig path and deletes it in `ensure` |
| Functional acceptance | No floating dependency; no AIDashCore/AIDashUI/CLI target link; generated project shows intended app/logic-test wiring only; values never enter `xcargs`, argv, logs, tracked files, or diagnostics; dependency rollback follows AID-APP quiesce/retention |
| Verification | `scripts/context/run XcodeWorkspace --mode ci`; clean XcodeGen diff inspection; required macOS/iOS CI after assembled T005; exact tag/revision-to-SHA evidence |
| Dependencies / slice | Exact planning PASS + REL-001; atomic `SL-AID-PRODUCER` candidate with T004/T005 |

- [ ] **T004 [AID-RELEASE]** Implement protected TestFlight temp-xcconfig injection and deterministic leak/cleanup gates.

| Metadata | T004 |
|---|---|
| Owning layer / context | **RepoInfra** — `CONTEXT.md` → `scripts/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `.github/workflows/testflight.yml`; `scripts/ci/telemetry_xcconfig.sh` (new); `scripts/ci/tests/test_telemetry_release_injection.py` (new); `scripts/ci/tests/test_testflight_manual_only.py` |
| Files NOT to touch | `fastlane/Fastfile`/Configs/project.yml (T003); Apps/Packages/CLI/aidata; any real secret or local config |
| Interface / contract | Existing protected names only; run-owned runner-temp file under `umask 077`, verified `0600`; workflow passes only file path; `if: always()` cleanup complements Fastlane `ensure`; helper is testable with synthetic sentinels |
| Functional acceptance | Synthetic Release-path test captures stdout/stderr and finds neither raw nor shell-escaped sentinel; verifies path-only `-xcconfig`, mode 0600, deletion after success and forced failure; workflow remains manual-only; no echo/readback/artifact of values |
| Verification | `/usr/bin/python3 -m pytest scripts/ci/tests/test_telemetry_release_injection.py scripts/ci/tests/test_testflight_manual_only.py -q`; `scripts/context/run RepoInfra --mode local`; shell syntax gate; required TestFlight workflow review without live secret read |
| Dependencies / slice | T003 path contract; OA-004 gates live values only; atomic `SL-AID-PRODUCER` candidate |

- [ ] **T005 [AID-APP]** Add GUI-only direct telemetry composition, two product signals, retained rollback, and hostless gate.

| Metadata | T005 |
|---|---|
| Owning layer / context | **AIDashApp** — `CONTEXT.md` → `Apps/CONTEXT.md` → `Apps/AIDashApp/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `Apps/AIDashApp/CONTEXT.md`; `Apps/AIDashApp/Info.plist`; `Apps/AIDashApp/Sources/AIDashApp.swift`; `Apps/AIDashApp/Sources/RunMode.swift`; `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`; new `Apps/AIDashApp/Sources/Telemetry/AIDashTelemetryFactory.swift`; new `Apps/AIDashApp/Sources/Telemetry/AIDashTelemetryCoordinator.swift`; new `Apps/AIDashApp/Tests/AIDashTelemetryFactoryTests.swift`; new `Apps/AIDashApp/Tests/AIDashTelemetryCoordinatorTests.swift` |
| Files NOT to touch | AIDashCore/AIDashUI/CLI; XPC protocol/schema/store/migration; project/Configs/fastlane/workflows; fixed-install scripts/entitlements/ADR-003; aidata |
| Interface / contract | ADR-004 and `contracts/blob-wire.md`; manual host-key read; direct initializer; `heartbeatVersion: nil`; app-local allowlist/UUID/store; exactly one GUI lifecycle action + ready-scene PLT; injected fakes/no-op |
| Functional acceptance | Hostless tests prove empty/unexpanded/unsafe config and no consent return before identity/store/network; valid direct construction; invalid URL/SAS/app/build/disk rejected content-free; bundle initializer absent; GUI once-only; headless/test-host no-op; no timer/heartbeat; disable awaits work and retains pending files/identity epochs |
| Verification | Add an `AIDashAppLogicTests` test gate to leaf context; run `scripts/context/run AIDashApp --mode local` only through that hostless gate; `scripts/context/run AIDashApp --mode ci`; never run host-based `AIDashAppTests` locally; required macOS/iOS CI |
| Dependencies / slice | T003; assembled with T004; closes `SL-AID-PRODUCER` after exact-revision implementation review |

## Phase 3: aidata L1–L4 and operations

- [ ] **T006 [DATA-L12]** Add the GET-only Blob collector/normalizer with CLI-only DAC and complete-unit state.

| Metadata | T006 |
|---|---|
| Owning layer / context | **AidataL1L2** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/adapters/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | new `aidata/adapters/product_blob.py`; new `aidata/tests/test_product_blob_adapter.py`; `aidata/CONTEXT.md`; `aidata/adapters/CONTEXT.md` |
| Files NOT to touch | config/lock (T001); workflow (T002); merge/schema/query/scripts/L5; Swift/App |
| Interface / contract | `contracts/reader-auth.md`, `contracts/blob-wire.md`, `data-model.md`; `collect()` + `normalize()`; exact container-origin/path GET list/read; deterministic path+line key; redacted append-only raw; complete-unit checkpoint |
| Functional acceptance | Fakes prove bounded pagination, path validation, gzip/NDJSON parsing, exact product/build/time/provenance, rerun idempotency, malformed/partial/token/network no-advance, CLI-only DAC exclusions/no fallback, redirect refusal, GET-only requests, and zero token/endpoint/identity leakage in records/state/errors/logs |
| Verification | `/usr/bin/python3 -m pytest aidata/tests/test_product_blob_adapter.py -q`; `scripts/context/run AidataL1L2 --mode local`; CI pytest+Ruff; `scripts/context/audit` after test-path routing |
| Dependencies / slice | T001 + T002; OA-004 only for later live evidence |

- [ ] **T007 [DATA-L3]** Add the honest idempotent `fact_product_event` warehouse grain.

| Metadata | T007 |
|---|---|
| Owning layer / context | **AidataL3** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/schema/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/schema/warehouse.sql`; `aidata/merge.py`; new `aidata/tests/test_product_event_merge.py`; `aidata/CONTEXT.md`; `aidata/schema/CONTEXT.md` |
| Files NOT to touch | adapters/config; L4/L5/scripts; Swift/App; real `warehouse.db` |
| Interface / contract | `data-model.md`; one fact per deterministic source-event key; preserve event name/time/properties and sanitized object provenance; no product formula |
| Functional acceptance | Temporary-DB fixture proves expected grain/count, nullability/provenance, incremental rebuild/rerun without duplicate, and no reliance on live tests that skip without a warehouse |
| Verification | `/usr/bin/python3 -m pytest aidata/tests/test_product_event_merge.py -q`; `scripts/context/run AidataL3 --mode local`; CI pytest+Ruff; context audit |
| Dependencies / slice | T006 |

- [ ] **T008 [DATA-L4]** Add the bounded read-only exploratory product-event query.

| Metadata | T008 |
|---|---|
| Owning layer / context | **AidataL4** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L4_serve/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | new `aidata/L4_serve/queries/product/events.sql`; new `aidata/tests/test_product_events_query.py`; `aidata/CONTEXT.md`; `aidata/L4_serve/CONTEXT.md` |
| Files NOT to touch | L5 cards/digest; adapters/config/merge/schema/scripts; Swift/App |
| Interface / contract | Query begins `-- aidata-tier: explore`, reads only `fact_product_event`, has explicit product/event/UTC bounds, stable row columns and empty-result behavior; no source attach/mutation |
| Functional acceptance | Hermetic DB returns one neutral synthetic row; each filter bounds results; empty input is empty; rerun is stable; query does not attach or mutate source DB and is not promoted to L5 |
| Verification | `/usr/bin/python3 -m pytest aidata/tests/test_product_events_query.py aidata/tests/test_query_tiers.py -q`; `scripts/context/run AidataL4 --mode local`; CI pytest+Ruff; context audit |
| Dependencies / slice | T007 |

- [ ] **T009 [DATA-OPS]** Register `product_blob` in the exact scheduled source order with degraded-source behavior.

| Metadata | T009 |
|---|---|
| Owning layer / context | **AidataOps** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/scripts/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/scripts/aidata_digest_run.sh`; `aidata/tests/test_runner_sources.py` |
| Files NOT to touch | host-installed runner/cron copy; config/adapters/merge/query/L5; Swift/App |
| Interface / contract | Add `product_blob` once to the explicit ordered source list; preserve per-source timeout, failure observability, and continue/degrade behavior |
| Functional acceptance | Test compares exact ordered equality with registered scheduled sources and proves a failing/unconfigured product source does not prevent later sources while never reporting false success for that source |
| Verification | `/usr/bin/python3 -m pytest aidata/tests/test_runner_sources.py -q`; `scripts/context/run AidataOps --mode local`; CI pytest+Ruff |
| Dependencies / slice | T001; may run parallel to T006–T008; authorized operator syncs host copy only after merge |

## Phase 4: external acceptance milestone

**E2E-05 (no T-number; no repository implementation owner)**: Team Lead collects and an independent reviewer verifies `contracts/e2e-evidence.md` only after exact merged `SL-VITAL`, `SL-AID-PRODUCER`, and `SL-DATA` revisions plus REL-001/OA-003/OA-004 evidence exist. It authorizes no source edit, credential read, role change, or cross-repository takeover.

## Dependency graph

```text
planning PASS
  + REL-001 --> T003 AID-XCODE --> T005 AID-APP ------+--> SL-AID-PRODUCER
  |                       `--> T004 AID-RELEASE ------'
  |
  `--> T001 DATA-FOUND --> T002 AID-DEP --> T006 DATA-L12 --> T007 DATA-L3 --> T008 DATA-L4
             `---------------------------------------------------------------> T009 DATA-OPS

T006 + T007 + T008 + T009 --> SL-DATA
external SL-VITAL + SL-AID-PRODUCER + SL-DATA + REL/OA gates --> E2E-05
```

T003/T004/T005 form one atomic candidate-tree barrier even though contract dependency order is shown. T009 can proceed in parallel after T001. Reverse rollback order is compensation, not a cycle.

## Acceptance coverage

| Requirement / scenario | Owning closure |
|---|---|
| FR-001 product-local action/performance | T005 + external VitalStride + E2E-05 |
| FR-002 producer validation/durability/rollback | T003–T005 + external VitalStride + E2E-05 |
| FR-003 VitalStride compatibility | External `SL-VITAL`; explicitly no AIDash task |
| FR-004 AIDash GUI-only producer | T003–T005 + E2E-05 |
| FR-005 aidata L1–L4/Ops | T001–T002 + T006–T009 |
| FR-006 bounded two-product correlation | E2E-05 only |
| FR-007 least privilege/dependency/release evidence | T001–T006 + E2E-05 + external REL/OA evidence |
| US1/AC1–AC4 fail-closed GUI, exact events, mode no-op, retained rollback | T003–T005 |
| US2/AC1–AC4 no-op auth, complete collection, no partial advance, idempotent query | T001–T002 + T006–T009 |
| US3/AC1–AC4 correlation, rerun, unsafe rejection, sanitized authorization | E2E-05 with T005–T008 evidence |
| SC-001 | T005 |
| SC-002 | T001/T002/T006 |
| SC-003 | T007/T008 |
| SC-004 | E2E-05 |
| SC-005 | Every task's changed-file scan + independent reviews |
| SC-006 | Per-task resolver/CI gates + exact-revision reviews |

## Definition of done

- Every implementation task stays within its exact files and owning layer; generated project output remains untracked.
- Every new test/manifest path is present in matching parent and leaf context routing, and `scripts/context/audit` reports zero findings.
- AIDashApp has a declared hostless logic-test gate; no host-based app test is run locally.
- The exact Azure Identity lock and CI install are present before the adapter imports it.
- The producer candidate passes XcodeWorkspace, RepoInfra release-injection, AIDashApp hostless, required app build, no-secret, and exact dependency gates.
- The data candidate passes every leaf gate, full aidata pytest/Ruff, no-secret/identity scan, and deterministic rerun tests.
- Exact local, pushed branch, and PR revisions match before implementation review/publication.
- E2E-05 remains evidence-only, starts only after merged slice and external authorization evidence, and contains no credential or personal identity metadata.
