# Tasks: Product Telemetry Blob Pipeline

## Execution contract

These are later implementation tasks, not authority to implement during
`SL-AID-PLAN`. Every `Txxx` has one owning layer. Routing/context files listed
with a task are the minimum metadata needed to register that layer's new
manifests or tests; they do not transfer product-code ownership.

Tasks within `SL-AID-PRODUCER` assemble one candidate tree before publication.
`SL-DATA` preserves a green delivery boundary at every commit: configuration,
adapter, schema/query, and runner canonicalization land while `product_blob`
remains inactive; T010 performs the only registry/schedule activation after all
prerequisites. E2E-05 is external evidence, not a repository implementation
task. No T001–T010 implementation starts before the constitution 1.14.0
amendment is published and merged. Humans/agents never run suites directly:
normal commit/push hooks and CI own tests and builds; implementers inspect their
receipts.

## Phase 1: Foundation and dependency plumbing

- [ ] **T001 [DATA-FOUND]** Add reader configuration, exact Azure Identity lock, and a non-activating canonical schedule declaration.

| Metadata | T001 |
|---|---|
| Owning layer / context | **AidataFoundation** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/CONTEXT.foundation.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/requirements.lock` (new, every direct/transitive version exact); `aidata/config.py`; `aidata/config_local.example.py`; `aidata/tests/test_config_m3.py`; `aidata/CONTEXT.md`; `aidata/CONTEXT.foundation.md` |
| Files NOT to touch | `.github/**` (T002); `aidata/adapters/**` (T006); merge/schema/query/scripts/L5; Swift/App/Configs/fastlane |
| Interface / contract | `contracts/reader-auth.md`; one empty `PRODUCT_BLOB_CONTAINER_URL`; no credential/auth-mode fields; introduce `SCHEDULED_SOURCES` equal to the current effective runner order; do **not** add `product_blob` to `SOURCES`, `MERGE_SOURCES`, or `SCHEDULED_SOURCES`; routed exact lock |
| Functional acceptance | Empty or query/userinfo/fragment-bearing selector is disabled; tracked example is empty/neutral; no token/SAS/account/principal value exists; lock is fully exact and audited; fresh-clone config imports without local override; declared schedule has exact current ordered/unique equality; no missing adapter can be imported through a registry |
| Verification | Normal commit must produce the resolver-selected **AidataFoundation** pre-commit receipt; normal push must produce its pre-push receipt; inspect static dependency/license/vulnerability evidence, task freshness, and `scripts/context/audit`; required aidata CI owns config tests and Ruff |
| Constitution refs (1.14.0) | §A. Scope Discipline; §Dependencies; §Error Handling; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | Exact planning PASS + merged constitution 1.14.0 amendment + OA-002 `aad-owner-local`; opens `SL-DATA` without activating the source |

- [ ] **T002 [AID-DEP]** Install and gate the exact aidata dependency lock in CI.

| Metadata | T002 |
|---|---|
| Owning layer / context | **RepoInfra** — `CONTEXT.md` → `scripts/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `.github/workflows/build.yml`; `scripts/ci/tests/test_aidata_dependency_install.py` (new) |
| Files NOT to touch | `aidata/**` (T001/T006–T010); `.github/workflows/testflight.yml` (T004); product/Swift/Configs/fastlane |
| Interface / contract | CI installs only `aidata/requirements.lock` before aidata pytest/Ruff and fails closed on missing/unpinned entries; no credentials or package indexes beyond the configured source |
| Functional acceptance | Workflow no longer claims stdlib-only; structural test proves exact-lock install precedes pytest/Ruff, uses no floating upgrade flag, and retains existing Python/Ruff/degrade-not-crash gates |
| Verification | Normal commit/push must produce **RepoInfra** hook receipts; inspect workflow ordering and static lock assertions; required aidata CI owns the structural test and existing gates |
| Constitution refs (1.14.0) | §A. Scope Discipline; §Dependencies; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | T001 manifest; required before T006 imports Azure Identity |

## Phase 2: AIDash GUI producer

- [ ] **T003 [AID-XCODE]** Wire immutable LokiKit, empty host configuration, hostless test product, and Fastlane path-only xcconfig consumption.

| Metadata | T003 |
|---|---|
| Owning layer / context | **XcodeWorkspace** — `CONTEXT.md` → `Configs/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `project.yml`; `Configs/Identity.xcconfig`; `Configs/Identity.local.xcconfig.example`; `fastlane/Fastfile` |
| Files NOT to touch | generated `AIDash.xcodeproj`; `.github/**`/`scripts/ci/**` (T004); `Apps/**` (T005); Packages/Core/UI/CLI; aidata |
| Interface / contract | ADR-004 and `contracts/blob-wire.md`; exact REL-001-approved LokiKit product on AIDashApp and AIDashAppLogicTests only; both host keys expand from empty settings; Fastlane accepts only an xcconfig path and deletes it in `ensure` |
| Functional acceptance | No floating dependency; no AIDashCore/AIDashUI/CLI target link; generated-project diff shows app/logic-test wiring only; values never enter `xcargs`, argv, logs, tracked files, or diagnostics; rollback follows AID-APP quiesce/retention |
| Verification | Normal commit/push must produce **XcodeWorkspace** hook receipts; inspect clean XcodeGen diff and exact tag/revision-to-SHA evidence; required macOS/iOS CI owns workspace generation/build after the assembled producer candidate |
| Constitution refs (1.14.0) | §A. Scope Discipline; §Module Architecture; §GUI Product Telemetry; §Dependencies; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | Exact planning PASS + merged constitution 1.14.0 amendment + REL-001; atomic `SL-AID-PRODUCER` candidate with T004/T005 |

- [ ] **T004 [AID-RELEASE]** Implement protected TestFlight temp-xcconfig injection and deterministic leak/cleanup gates.

| Metadata | T004 |
|---|---|
| Owning layer / context | **RepoInfra** — `CONTEXT.md` → `scripts/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `.github/workflows/testflight.yml`; `scripts/ci/telemetry_xcconfig.sh` (new); `scripts/ci/tests/test_telemetry_release_injection.py` (new); `scripts/ci/tests/test_testflight_manual_only.py` |
| Files NOT to touch | `fastlane/Fastfile`/Configs/project.yml (T003); Apps/Packages/CLI/aidata; any real secret or local config |
| Interface / contract | Existing protected names only; run-owned runner-temp file under `umask 077`, verified `0600`; workflow passes only its path; `if: always()` cleanup complements Fastlane `ensure`; helper is testable with neutral synthetic sentinels |
| Functional acceptance | Synthetic Release-path evidence captures stdout/stderr and finds neither raw nor shell-escaped sentinel; proves path-only `-xcconfig`, mode 0600, deletion after success/forced failure; workflow remains manual-only; no echo/readback/artifact of values |
| Verification | Normal commit/push must produce **RepoInfra** hook receipts; inspect shell syntax and workflow diff; required CI owns sentinel/cleanup and manual-only structural tests without live secret read |
| Constitution refs (1.14.0) | §A. Scope Discipline; §GUI Product Telemetry; §Dependencies; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | T003 path contract; OA-004 gates live values only; atomic `SL-AID-PRODUCER` candidate |

- [ ] **T005 [AID-APP]** Add default-off GUI consent, lifetime install ID, exact events, retained disable/re-enable, and hostless gate.

| Metadata | T005 |
|---|---|
| Owning layer / context | **AIDashApp** — `CONTEXT.md` → `Apps/CONTEXT.md` → `Apps/AIDashApp/CONTEXT.md`; root `tech-context.md` |
| Files in scope | `Apps/AIDashApp/CONTEXT.md`; `Apps/AIDashApp/Info.plist`; `Apps/AIDashApp/Sources/AIDashApp.swift`; `Apps/AIDashApp/Sources/RunMode.swift`; `Apps/AIDashApp/Sources/Scenes/BriefingWindowScene.swift`; new `Apps/AIDashApp/Sources/Settings/AIDashTelemetrySettingsView.swift`; new `Apps/AIDashApp/Sources/Telemetry/AIDashTelemetryPreferences.swift`; new `Apps/AIDashApp/Sources/Telemetry/AIDashTelemetryFactory.swift`; new `Apps/AIDashApp/Sources/Telemetry/AIDashTelemetryCoordinator.swift`; `Apps/AIDashApp/Resources/Localizable.xcstrings`; new hostless `Apps/AIDashApp/Tests/AIDashTelemetryPreferencesTests.swift`, `AIDashTelemetryFactoryTests.swift`, and `AIDashTelemetryCoordinatorTests.swift` |
| Files NOT to touch | AIDashCore/AIDashUI/CLI; XPC protocol/schema/store/migration; project/Configs/fastlane/workflows; fixed-install scripts/entitlements/ADR-003; aidata |
| Interface / contract | ADR-004; `contracts/aidash-events.md`; `contracts/blob-wire.md`; production `UserDefaults.standard` keys `telemetry.sendUsageData`, `telemetry.installID`, and monotonic non-identity `telemetry.identityEstablished`; explicit `neverOpted`, `establishedDisabled`, `establishedEnabled`, and `establishedInvalid` preference states; isolated injected defaults in hostless tests; cross-platform Settings toggle with no Reset/rotation action; no shared reset API or private catalog parsing; manual host-key read; direct initializer; `heartbeatVersion: nil`; injected clock/UUID generator/fakes |
| Functional acceptance | Missing/malformed consent is off. Only the exact never-opted state (marker and UUID absent) may generate one random UUID; first opt-in persists UUID, then marker `true`, before consent becomes active. Relaunch/off-on cycles retain the marker and same UUID for the app's lifetime and re-enable never calls UUID generation. A true/malformed marker with missing/malformed UUID, any UUID without a true marker, or consent true without complete established identity enters `establishedInvalid`, keeps consent inactive, constructs nothing, and never generates/replaces an ID. Invalid config may leave valid first-opt-in preferences but no service/store/uploader/timer/network; app-init GUI-branch clock starts before consent/config reads and is discarded if ineligible; exact first-ready events/properties/formula emit unsampled at most once; mid-lifecycle opt-in is not retrospective; off persists false, closes admission, disables/cancels delivery, retains marker/ID plus ambiguous/pending state, and permits no upload; re-enable resumes with the same ID; Settings and composition expose no Reset/rotation surface; CLI/headless/test-host production composition is no-op; bundle initializer/device identifier/heartbeat absent |
| Verification | Normal commit/push must produce **AIDashApp** hook receipts whose declared local test product is hostless; inspect receipts rather than invoking suites. Hostless cases must prove pristine state generates exactly once; persisted marker and UUID survive relaunch and repeated disable/re-enable; established-disabled re-enable reuses the same UUID without invoking the UUID generator; every missing/malformed/inconsistent post-opt-in preference combination fails closed with zero service/store/uploader/timer/network construction and zero replacement generation; no Reset/rotation/shared-reset/private-catalog path exists; frozen work is retained; and exact events satisfy the contract. Required macOS/iOS CI owns app logic tests/builds; host-based `AIDashAppTests` are never run locally |
| Constitution refs (1.14.0) | §Principle I; §Principle II; §A. Scope Discipline; §E. Accessibility; §F. Internationalization; §GUI Product Telemetry; §Persistence; §Dependencies; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | T003 + merged constitution amendment; assembled with T004; closes `SL-AID-PRODUCER` after exact-revision implementation review |

## Phase 3: aidata L1–L4 and operations

- [ ] **T006 [DATA-L12]** Add an unregistered GET-only Blob collector/normalizer with CLI-only DAC and exact bounded checkpoints.

| Metadata | T006 |
|---|---|
| Owning layer / context | **AidataL1L2** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/adapters/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | new `aidata/adapters/product_blob.py`; new `aidata/tests/test_product_blob_adapter.py`; `aidata/CONTEXT.md`; `aidata/adapters/CONTEXT.md` |
| Files NOT to touch | config/lock/registries (T001/T010); workflow (T002); merge/schema/query/scripts/L5; Swift/App |
| Interface / contract | `contracts/reader-auth.md`, `contracts/blob-wire.md`, `data-model.md`; `collect()` + `normalize()`; exact container-origin/path GET list/read; deterministic path+line key; redacted append-only raw; object/page checkpoint model |
| Functional acceptance | Fakes prove 30s request timeout, 240s run budget, 100 results/page, 10 pages, 1,000 references/GETs, 8,388,608 compressed and 67,108,864 decompressed byte caps, streaming/missing-or-lying Content-Length behavior, every listed reference selected, invalid path blocks page advance before GET, exact after-page/within-page marker semantics, completed-object reuse, pre-list auth failure zero/no-state versus mid-run auth/network preservation of prior records/checkpoints, path/gzip/NDJSON validation, stable provenance, rerun idempotency, CLI-only DAC/no fallback, redirect refusal, GET-only operations, and zero partial/sensitive record/state/error/log material |
| Verification | Normal commit/push must produce **AidataL1L2** hook receipts; inspect task freshness and `scripts/context/audit` after routing; required aidata CI owns adapter boundary tests and Ruff |
| Constitution refs (1.14.0) | §A. Scope Discipline; §Dependencies; §Error Handling; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | T001 + T002; adapter remains unregistered until T010; OA-004 only gates later live evidence |

- [ ] **T007 [DATA-L3]** Add the honest idempotent `fact_product_event` warehouse grain while the source remains inactive.

| Metadata | T007 |
|---|---|
| Owning layer / context | **AidataL3** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/schema/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/schema/warehouse.sql`; `aidata/merge.py`; new `aidata/tests/test_product_event_merge.py`; `aidata/CONTEXT.md`; `aidata/schema/CONTEXT.md` |
| Files NOT to touch | adapters/config/registries; L4/L5/scripts; Swift/App; real `warehouse.db` |
| Interface / contract | `data-model.md`; one fact per deterministic source-event key; preserve event name/time/properties and sanitized object provenance; no product formula |
| Functional acceptance | Hermetic temporary-DB evidence proves expected grain/count, nullability/provenance, incremental rebuild/rerun without duplicate, immutable-conflict handling, and no reliance on a live warehouse |
| Verification | Normal commit/push must produce **AidataL3** hook receipts; inspect context audit after routing; required aidata CI owns merge tests and Ruff |
| Constitution refs (1.14.0) | §A. Scope Discipline; §Persistence; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | T006; source remains inactive until T010 |

- [ ] **T008 [DATA-L4]** Add the bounded read-only exploratory product-event query while the source remains inactive.

| Metadata | T008 |
|---|---|
| Owning layer / context | **AidataL4** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/L4_serve/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | new `aidata/L4_serve/queries/product/events.sql`; new `aidata/tests/test_product_events_query.py`; `aidata/CONTEXT.md`; `aidata/L4_serve/CONTEXT.md` |
| Files NOT to touch | L5 cards/digest; adapters/config/registries/merge/schema/scripts; Swift/App |
| Interface / contract | Query begins `-- aidata-tier: explore`, reads only `fact_product_event`, has explicit product/event/UTC bounds, stable row columns and empty-result behavior; no source attach/mutation |
| Functional acceptance | Hermetic DB returns one neutral synthetic row; each filter bounds results; empty input is empty; rerun is stable; query does not attach/mutate a source DB and is not promoted to L5 |
| Verification | Normal commit/push must produce **AidataL4** hook receipts; inspect context audit after routing; required aidata CI owns query/tier tests and Ruff |
| Constitution refs (1.14.0) | §A. Scope Discipline; §Persistence; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | T007; source remains inactive until T010 |

- [ ] **T009 [DATA-OPS]** Canonicalize the scheduled runner without activating `product_blob`.

| Metadata | T009 |
|---|---|
| Owning layer / context | **AidataOps** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/scripts/CONTEXT.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/scripts/aidata_digest_run.sh`; `aidata/tests/test_runner_sources.py` |
| Files NOT to touch | host-installed runner/cron copy; config/registries (T001/T010); adapters/merge/query/L5; Swift/App |
| Interface / contract | Runner consumes ordered `config.SCHEDULED_SOURCES`; preserve the current effective source list, per-source timeout, failure observability, and continue/degrade behavior; no `product_blob` entry yet |
| Functional acceptance | Exact ordered/unique equality evidence compares runner consumption with `SCHEDULED_SOURCES`; current sources/behavior are unchanged; a failing/unconfigured scheduled source does not prevent later sources and never reports false success |
| Verification | Normal commit/push must produce **AidataOps** hook receipts; inspect the runner diff and task freshness; required aidata CI owns exact runner/config equality and degradation tests |
| Constitution refs (1.14.0) | §A. Scope Discipline; §Error Handling; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | T001; may proceed in parallel with T002/T006–T008; operator syncs a host copy only after merge |

- [ ] **T010 [DATA-ACTIVATE]** Atomically activate the now-ready `product_blob` source.

| Metadata | T010 |
|---|---|
| Owning layer / context | **AidataFoundation** — `CONTEXT.md` → `aidata/CONTEXT.md` → `aidata/CONTEXT.foundation.md`; `aidata/tech-context.md` |
| Files in scope | `aidata/config.py`; `aidata/tests/test_config_m3.py`; `aidata/CONTEXT.md`; `aidata/CONTEXT.foundation.md` |
| Files NOT to touch | adapter/schema/merge/query/runner/test files delivered by T006–T009; workflows; L5; Swift/App |
| Interface / contract | Add `product_blob` exactly once and in the reviewed order to `SOURCES`, `MERGE_SOURCES`, and `SCHEDULED_SOURCES` in one delivery boundary; every entry is unique/importable; merge and schedule registries remain subsets of registered sources |
| Functional acceptance | Config evidence proves exact ordered/unique registries, importable adapter, merge/schedule subset invariants, and empty/unavailable source no-op; existing T009 equality gate remains green at the activation revision; no delivery revision has a missing adapter or stale runner order |
| Verification | Normal commit/push must produce **AidataFoundation** hook receipts; inspect task freshness/context audit; required full aidata CI owns config, adapter, merge/query, exact runner-order, degradation, and Ruff gates at the activated revision |
| Constitution refs (1.14.0) | §A. Scope Discipline; §Dependencies; §Error Handling; §Testing → Who runs tests; §Development Workflow → Quality Gates; §No Identity in Version Control |
| Dependencies / slice | T002 + T006 + T007 + T008 + T009; closes `SL-DATA` after exact-revision implementation review |

## Phase 4: external acceptance milestone

**E2E-05 (no T-number; no repository implementation owner)**: Team Lead
collects and an independent reviewer verifies `contracts/e2e-evidence.md` only
after exact merged `SL-VITAL`, `SL-AID-PRODUCER`, and `SL-DATA` revisions plus
REL-001/OA-003/OA-004 evidence exist. It authorizes no source edit, credential
read, role change, or cross-repository takeover.

## Dependency graph

```text
planning PASS + constitution 1.14.0 merged
  + REL-001 --> T003 AID-XCODE --> T005 AID-APP ------+--> SL-AID-PRODUCER
  |                       `--> T004 AID-RELEASE ------'
  |
  `--> T001 DATA-FOUND --> T002 AID-DEP --> T006 DATA-L12 --> T007 DATA-L3 --> T008 DATA-L4 --+
             `---------------------------------------------> T009 DATA-OPS ---------------------+--> T010 DATA-ACTIVATE --> SL-DATA

external SL-VITAL + SL-AID-PRODUCER + SL-DATA + REL/OA gates --> E2E-05
```

T003/T004/T005 form one atomic candidate-tree barrier. T001/T002/T006/T007/T008
and T009 remain green with `product_blob` inactive; only T010 activates it.
Reverse rollback ordering is compensation, not a dependency cycle.

## Acceptance coverage

| Requirement / scenario | Owning closure |
|---|---|
| FR-001 exact product-local event contracts | T005 + external VitalStride + E2E-05 |
| FR-002 consent/identity/durability/rollback | T003–T005 + external VitalStride + E2E-05 |
| FR-003 VitalStride compatibility | External `SL-VITAL`; no AIDash task |
| FR-004 AIDash GUI-only producer | T003–T005 + E2E-05 |
| FR-005 bounded aidata L1–L4/Ops + atomic activation | T001–T002 + T006–T010 |
| FR-006 bounded two-product correlation | E2E-05 only |
| FR-007 least privilege/dependency/release evidence | T001–T006 + T010 + E2E-05 + external REL/OA evidence |
| US1 default-off, distinguishable never-opted/established/corrupt identity states, lifetime first-opt-in ID, exact events, mode no-op, disable/re-enable with same ID, no Reset | T003–T005 |
| US2 no-op auth, exact bounds/checkpoints, idempotent query/activation | T001–T002 + T006–T010 |
| US3 correlation, rerun, unsafe rejection, sanitized authorization | E2E-05 with T005–T008 evidence |
| SC-001 | T005 |
| SC-002 | T001/T002/T006 |
| SC-003 | T007/T008 |
| SC-004 | E2E-05 |
| SC-005 | Every task's changed-file scan + independent reviews |
| SC-006 | Hook/CI receipts + exact-revision reviews |

## Definition of done

- Every task stays within its one owning layer and exact file scope; generated
  project output remains untracked.
- Every new test/manifest path is in matching parent/leaf routing, and the
  static context audit reports zero findings.
- Normal commit/push receipts prove the resolver selected every changed leaf;
  no agent/human directly invokes a test suite, and no host-based app test runs
  locally.
- Required CI owns heavy app/workspace builds and full/focused pytest/Ruff at
  the exact pushed head.
- The exact Azure Identity lock/CI install precede adapter import; source
  activation occurs only in T010 after adapter/schema/query/runner readiness.
- Producer evidence covers exact Settings consent/monotonic established marker/
  lifetime install ID/events, same-ID relaunch and disable/re-enable,
  fail-closed corrupt/inconsistent state without replacement generation,
  absence of Reset/rotation, and
  no-secret/dependency gates; data evidence covers every reader bound,
  checkpoint, rerun, registry, query, and no-secret gate.
- Exact local, pushed branch, and PR revisions match before implementation
  review/publication.
- E2E-05 stays evidence-only, begins only after merged slices/external
  authorization, and contains no credential or personal identity metadata.
