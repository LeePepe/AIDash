# Implementation Plan: Product Telemetry Blob Pipeline

**Feature**: `007-product-telemetry-blob`
**Base**: `bdf1435fe7d3d9c4da43ed4297cbc24482447b46`
**Accepted input**: MY-1816 planning v6, SHA-256 `97dc0822f4ade9f6e70a5c070e9860c6eeb57076e0744f1cdd7744750e8c55f2`

## Summary

Adopt the accepted central telemetry scope into AIDash's native Spec Kit and constitution 1.14.0 amendment. Later implementation adds an explicit-consent GUI-only LokiKit producer and a single-mode read-only `aidata` Blob source through L4/operations. This plan records OA-002 as Azure CLI-only `DefaultAzureCredential`, fixes the AIDash event/consent and reader-bound contracts, activates the source only after all prerequisites are ready, splits every implementation packet at repository layer boundaries, and keeps E2E-05 as external evidence rather than repository product code.

## Technical context

**Languages**: Swift 6; Python 3
**Project generation**: XcodeGen through `project.yml`
**Swift dependency**: LokiKit/shared-telemetry at an immutable REL-001-approved identity
**Python dependency**: `azure-identity` with a fully exact audited lock; stdlib HTTP/gzip/JSON for Blob data
**Storage**: LokiKit-isolated durable queue/sidecars; append-only aidata raw; SQLite source-clean/warehouse
**Verification**: resolver-selected pre-commit/pre-push hook receipts; hostless `AIDashAppLogicTests` and focused pytest/Ruff owned by hooks/CI; context audit; CI macOS+iOS builds
**Platforms**: existing AIDash macOS/iOS targets only; headless/CLI/test-host telemetry disabled
**Privacy**: public repository; no real endpoint, personal principal metadata, token, SAS, account key, or raw free text
**Scope**: AIDash producer plus aidata L1–L4/Ops; no L5, fixed-install entitlement change, Azure mutation, VitalStride edit, or VoxPocket/T3

## Constitution check

| Gate | Planning result |
|---|---|
| §Principle I + §GUI Product Telemetry | PASS after amendment merge — telemetry is default-off, explicit-consent, GUI-only, typed, and not a briefing authoring channel |
| §Principle II + §Persistence | PASS after amendment merge — isolated telemetry queue/Blob is the sole narrow third-party exception; briefing/UserEvent CloudKit and SwiftData rules are unchanged |
| Append-only / durable state | PASS — writer retry state and the lifetime-stable install ID are retained across disable/re-enable; aidata raw is append-only; L3 rerun is idempotent |
| Dependency ADR | PASS — ADR-004 covers LokiKit; ADR-005 covers `azure-identity` |
| Layer direction | PASS — RepoInfra, XcodeWorkspace, AIDashApp, and each aidata leaf have separate tasks |
| Swift concurrency | PASS — no unsafe escape is authorized; app coordinator owns structured lifecycle |
| URL/config validation | PASS — first opt-in may persist consent/UUID, but producer config validates before telemetry service/store/uploader/timer/network work; reader validates before credential/network work |
| §Testing → Who runs tests | PASS — tasks require hook/CI-owned acceptance and receipt inspection, never direct suite execution; every new test is routed |
| Public-repository privacy | PASS — tracked selectors are empty/neutral; actual endpoint and identity metadata remain external/ignored |
| Fresh clone | PASS by contract — empty config and absent local identity produce no-op; dependency install is explicit in CI |
| Fixed install | PASS — ADR-003 remains unchanged; no telemetry claim is made for its current no-network entitlement |

The constitution amendment is part of this planning change and must be
published and merged through `constitution: authorize explicit-consent GUI
telemetry` before any T001–T010 implementation. Its migration note records: no
Briefing/UserEvent/CloudKit migration; existing installs start off; no install
ID/store/network before first opt-in; spec 007 adopts the consent and hook-owned
verification contracts.

## Project structure

### Planning artifacts

```text
.specify/feature.json
specs/007-product-telemetry-blob/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
├── checklists/requirements.md
└── contracts/
    ├── aidash-events.md
    ├── blob-wire.md
    ├── e2e-evidence.md
    └── reader-auth.md
docs/adr/
├── 004-gui-scoped-lokikit-telemetry.md
└── 005-azure-cli-reader-identity.md
```

### Planned implementation paths

```text
.github/workflows/build.yml
.github/workflows/testflight.yml
scripts/ci/**
project.yml
Configs/Identity.xcconfig
Configs/Identity.local.xcconfig.example
fastlane/Fastfile
Apps/AIDashApp/
├── CONTEXT.md
├── Info.plist
├── Sources/AIDashApp.swift
├── Sources/RunMode.swift
├── Sources/Scenes/BriefingWindowScene.swift
├── Sources/Settings/**
├── Sources/Telemetry/**
├── Resources/**
└── Tests/*Telemetry*Tests.swift
aidata/
├── CONTEXT.md
├── CONTEXT.foundation.md
├── requirements.lock
├── config.py
├── config_local.example.py
├── adapters/product_blob.py
├── adapters/CONTEXT.md
├── merge.py
├── schema/{CONTEXT.md,warehouse.sql}
├── L4_serve/{CONTEXT.md,queries/product/events.sql}
├── scripts/aidata_digest_run.sh
└── tests/
    ├── test_config_m3.py
    ├── test_product_blob_adapter.py
    ├── test_product_event_merge.py
    ├── test_product_events_query.py
    └── test_runner_sources.py
```

`AIDash.xcodeproj` remains generated and untracked.

## Design

### Producer

`AIDashApp.init` already fixes run mode once. GUI composition reads the
`UserDefaults.standard` key `telemetry.sendUsageData` (missing is false) and exposes
the cross-platform Settings toggle **Send usage data**. First opt-in creates and
persists one random `telemetry.installID`; later launches and consent cycles
reuse it for the app's lifetime, and no device-derived identifier is used. A
missing/malformed established ID fails closed rather than rotating. With
persisted consent, GUI mode, and valid expanded plist values, the app creates
the direct LokiKit Blob service. CLI, headless/XPC, and test-host production
paths receive a no-op.

The app-local preferences/coordinator owns service lifetime, consent
transitions, the lifetime-stable install ID, and the exact contract in
`contracts/aidash-events.md`. It captures a `ContinuousClock` start at entry to
the GUI-production app-init branch, before consent/configuration reads and
bootstrap/service construction, and discards it if eligibility fails. It emits
`aidash.action(action_name=briefing_viewed)` and
`aidash.performance.ready_scene(duration_ms)` at the first interactive
`.ready(container)` appearance, unsampled and at most once. Mid-lifecycle
opt-in is not retrospective. Disable persists false, closes admission,
disables/cancels delivery before awaiting quiescence, and retains any
ambiguous/pending work without continued upload. Re-enable resumes eligible
retained work under the same install UUID. Version 1 exposes no Reset/rotation;
it adds no shared-telemetry reset API and performs no private catalog parsing.

The two release-input names remain `TELEMETRY_BLOB_ENDPOINT` and `TELEMETRY_BLOB_SAS`; their values are never read by agents. XcodeWorkspace owns empty build settings, dependency wiring, and Fastlane path-only xcconfig consumption. RepoInfra owns protected workflow injection, permissions/cleanup, sentinel leak tests, and workflow assertions.

### Reader

AidataFoundation owns the only selector, empty tracked default, exact Azure
Identity lock, canonical `SCHEDULED_SOURCES` declaration, later atomic source
activation, and routing metadata. RepoInfra installs the exact lock in aidata
CI. AidataL1L2 builds a CLI-only DAC and stdlib GET-only transport. It enforces
30 seconds per request, a 240-second run budget, 100 results/page, 10 pages,
1,000 references/GETs, and streaming 8 MiB compressed / 64 MiB decompressed
object limits. It emits append-only redacted raw/source-clean records and
advances a page marker only after the complete page and every listed reference
are successful/already complete; an invalid path blocks the marker before GET.

AidataL3 adds one `fact_product_event` row per deterministic object-path/line-ordinal key. AidataL4 exposes an `explore` query with product/event/time filters. AidataOps first changes the runner to consume canonical `SCHEDULED_SOURCES` without changing effective sources; only then does an AidataFoundation activation task atomically add `product_blob` once to `SOURCES`, `MERGE_SOURCES`, and `SCHEDULED_SOURCES`. No delivery boundary contains a registered missing adapter or mismatched runner; no L5 code changes.

### Data and rollback

Writer rollback first persists consent off, closes admission,
disables/cancels delivery without starting or continuing queued upload, awaits
quiescence, and proves any ambiguous in-flight batch plus all pending
files and the lifetime-stable install ID remain. Only then may
dependency/build/release plumbing be removed. Reader rollback removes scheduled
registration/config/adapter/fact/query as a coordinated change but never
deletes append-only raw or accepted warehouse evidence.

## Layer-owned packets

| Packet | Owning layer | Outcome | Depends on |
|---|---|---|---|
| `AID-DEP` | RepoInfra | Install exact `aidata` dependency lock in CI and gate it | AID-PLAN, DATA-FOUND manifest |
| `AID-XCODE` | XcodeWorkspace | Immutable LokiKit wiring, empty host keys, logic-test target, Fastlane path-only xcconfig lifecycle | AID-PLAN, REL-001 |
| `AID-RELEASE` | RepoInfra | TestFlight secret-to-temp-xcconfig injection, 0600/path-only/ensure+always cleanup and sentinel gates | AID-XCODE, OA-004 for live values only |
| `AID-APP` | AIDashApp | GUI-only direct producer, Settings consent/lifetime install ID, exact two events, retained disable/re-enable, hostless gate | constitution amendment merged, AID-XCODE |
| `DATA-FOUND` | AidataFoundation | Exact Azure Identity lock, endpoint selector, current-effective scheduled-source declaration, routing; no `product_blob` activation | AID-PLAN, constitution amendment merged, OA-002 fixed |
| `DATA-L12` | AidataL1L2 | GET-only CLI-DAC Blob adapter, complete-unit state and provenance | DATA-FOUND, AID-DEP |
| `DATA-L3` | AidataL3 | Honest idempotent product-event fact | DATA-L12 |
| `DATA-L4` | AidataL4 | Bounded read-only exploratory query | DATA-L3 |
| `DATA-OPS` | AidataOps | Runner consumes canonical current-effective `SCHEDULED_SOURCES`; degraded-source behavior | DATA-FOUND |
| `DATA-ACTIVATE` | AidataFoundation | Atomically add importable/mergeable/scheduled `product_blob` after all reader paths are ready | DATA-L4, DATA-OPS |
| `E2E-05` | Team Lead external gate | Sanitized two-product/two-event correlation | merged producer/data/VitalStride, REL-001, OA-003/OA-004 |

## Dependency graph

```text
accepted central plan + native planning PASS
  + constitution 1.14 merge + REL-001 --> AID-XCODE --> AID-APP ----+--> SL-AID-PRODUCER
  |                                      `--> AID-RELEASE ----------'
  |
  `--> DATA-FOUND --> AID-DEP --> DATA-L12 --> DATA-L3 --> DATA-L4 --+
           `-----------------------------> DATA-OPS ------------------+--> DATA-ACTIVATE --> SL-DATA

external SL-VITAL + SL-AID-PRODUCER + SL-DATA
  + REL-001 + OA-001/OA-002/OA-003/OA-004 --> E2E-05
```

Rollback ordering is compensation, not a reverse dependency edge.

## Verification strategy

- Planning: static Spec Kit prerequisite/freshness checks, requirements
  checklist, FR/AC-to-task coverage, and context audit; normal commit supplies
  the resolver-selected RepoInfra pre-commit receipt.
- Producer implementation: normal commits/pushes supply resolver-selected
  hook receipts; required CI owns XcodeWorkspace/AIDashApp builds and tests;
  generated-project diff is inspected; host-based local app tests are forbidden.
- Reader implementation: normal commits/pushes supply each changed Aidata
  leaf's hook receipt; CI owns focused/full pytest/Ruff; context audit follows
  routing changes.
- Release plumbing: synthetic raw-plus-shell-escaped sentinel exercises actual Release path and proves 0600, path-only invocation, and both success/failure cleanup without using real values.
- Security: changed-file scan rejects actual endpoints, identity metadata, tokens, SAS/account keys, credential-bearing URLs, and fixtures/logs containing sentinels.
- Final: inspect the normal-commit/pre-push hook receipts and required CI at the
  exact local/pushed/PR revisions, then independent E2E-05 evidence review.

## Risks

- `azure-identity` changes aidata's stdlib-only baseline. Exact lock, separate ADR, routed manifest, CI install, and dependency audit contain this risk.
- Release injection spans XcodeWorkspace and RepoInfra; split tasks prevent cross-layer ownership drift.
- `AIDashApp` currently lacks a hostless resolver test gate; AID-APP must add it before claiming hermetic producer acceptance, including same-ID relaunch and disable/re-enable evidence plus absence of a Reset/rotation surface.
- Install-ID Reset is deliberately outside version 1. A future need requires a separately authorized LokiKit SDK feature; this plan adds neither shared API nor private-storage parsing.
- The LokiKit release identity remains unresolved; REL-001 blocks only AID-XCODE and live proof.
- The future sandboxed fixed install has no network entitlement; this plan neither edits nor works around ADR-003.
- Local Azure identity availability is operational state. No-op is correct; implementation must never prompt or choose a substitute principal.
- Lower-authority README/root tech-context wording remains CloudKit-only at the
  fixed base; the constitution PR migration must align it before implementation
  publication without weakening the narrow exception.

## Planning completion gate

The native planning slice is complete only when all listed artifacts and both
ADRs are present, task freshness/coverage and context audit have no ERROR or
CRITICAL finding, the normal commit records its RepoInfra hook receipt, no
sensitive identifier is tracked, and AI Reviewer returns PASS for one exact
planning revision. This planning PASS does not waive the separate constitution
amendment publication/merge gate for implementation.
