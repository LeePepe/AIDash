# Implementation Plan: Product Telemetry Blob Pipeline

**Feature**: `007-product-telemetry-blob`
**Base**: `bdf1435fe7d3d9c4da43ed4297cbc24482447b46`
**Accepted input**: MY-1816 planning v6, SHA-256 `97dc0822f4ade9f6e70a5c070e9860c6eeb57076e0744f1cdd7744750e8c55f2`

## Summary

Adopt the accepted central telemetry scope into AIDash's native Spec Kit. Later implementation adds a GUI-only LokiKit producer and a single-mode read-only `aidata` Blob source through L4/operations. This plan records OA-002 as Azure CLI-only `DefaultAzureCredential`, splits every implementation packet at repository layer boundaries, and keeps E2E-05 as external evidence rather than repository product code.

## Technical context

**Languages**: Swift 6; Python 3
**Project generation**: XcodeGen through `project.yml`
**Swift dependency**: LokiKit/shared-telemetry at an immutable REL-001-approved identity
**Python dependency**: `azure-identity` with a fully exact audited lock; stdlib HTTP/gzip/JSON for Blob data
**Storage**: LokiKit-isolated durable queue/sidecars; append-only aidata raw; SQLite source-clean/warehouse
**Testing**: XcodeWorkspace generation; hostless `AIDashAppLogicTests`; focused pytest/Ruff; context resolver/audit; CI macOS+iOS builds
**Platforms**: existing AIDash macOS/iOS targets only; headless/CLI/test-host telemetry disabled
**Privacy**: public repository; no real endpoint, personal principal metadata, token, SAS, account key, or raw free text
**Scope**: AIDash producer plus aidata L1–L4/Ops; no L5, fixed-install entitlement change, Azure mutation, VitalStride edit, or VoxPocket/T3

## Constitution check

| Gate | Planning result |
|---|---|
| Append-only / durable state | PASS — writer retry state is immutable/retained; aidata raw is append-only; L3 rerun is idempotent |
| CLI writes / app reads boundary | PASS — telemetry is app-local delivery and does not reuse or mutate briefing/UserEvent interfaces |
| Dependency ADR | PASS — ADR-004 covers LokiKit; ADR-005 covers `azure-identity` |
| Layer direction | PASS — RepoInfra, XcodeWorkspace, AIDashApp, and each aidata leaf have separate tasks |
| Swift concurrency | PASS — no unsafe escape is authorized; app coordinator owns structured lifecycle |
| URL/config validation | PASS — producer and reader validate before identity/store/network work |
| Test ownership | PASS — hostless app logic only; every new aidata test is added to parent/leaf routing |
| Public-repository privacy | PASS — tracked selectors are empty/neutral; actual endpoint and identity metadata remain external/ignored |
| Fresh clone | PASS by contract — empty config and absent local identity produce no-op; dependency install is explicit in CI |
| Fixed install | PASS — ADR-003 remains unchanged; no telemetry claim is made for its current no-network entitlement |

No constitutional exception is requested.

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
├── Sources/Telemetry/**
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

`AIDashApp.init` already fixes run mode once. GUI composition reads consent and the two expanded plist keys, validates them, then creates the direct LokiKit Blob service. Headless agent and test-host paths receive a no-op. An app-local coordinator owns exactly-once lifecycle emission, ready-scene timing, service lifetime, and orderly disable/flush retention.

The two release-input names remain `TELEMETRY_BLOB_ENDPOINT` and `TELEMETRY_BLOB_SAS`; their values are never read by agents. XcodeWorkspace owns empty build settings, dependency wiring, and Fastlane path-only xcconfig consumption. RepoInfra owns protected workflow injection, permissions/cleanup, sentinel leak tests, and workflow assertions.

### Reader

AidataFoundation owns the only selector, empty tracked default, source registration, exact Azure Identity lock, and routing metadata. RepoInfra installs the exact lock in aidata CI. AidataL1L2 builds a CLI-only DAC and stdlib GET-only transport, lists with bounded pagination, downloads complete gzip NDJSON objects, emits append-only redacted raw/source-clean records, and advances state only after a complete unit.

AidataL3 adds one `fact_product_event` row per deterministic object-path/line-ordinal key. AidataL4 exposes an `explore` query with product/event/time filters. AidataOps adds the source to the exact ordered runner list while preserving per-source timeout/degradation. No L5 code changes.

### Data and rollback

Writer rollback first disables the producer, awaits active flush exit, and proves pending files/identities remain. Only then may dependency/build/release plumbing be removed. Reader rollback removes scheduled registration/config/adapter/fact/query as a coordinated change but never deletes append-only raw or accepted warehouse evidence.

## Layer-owned packets

| Packet | Owning layer | Outcome | Depends on |
|---|---|---|---|
| `AID-DEP` | RepoInfra | Install exact `aidata` dependency lock in CI and gate it | AID-PLAN, DATA-FOUND manifest |
| `AID-XCODE` | XcodeWorkspace | Immutable LokiKit wiring, empty host keys, logic-test target, Fastlane path-only xcconfig lifecycle | AID-PLAN, REL-001 |
| `AID-RELEASE` | RepoInfra | TestFlight secret-to-temp-xcconfig injection, 0600/path-only/ensure+always cleanup and sentinel gates | AID-XCODE, OA-004 for live values only |
| `AID-APP` | AIDashApp | GUI-only direct producer, consent/mode/no-op, two events, retention, hostless gate | AID-XCODE |
| `DATA-FOUND` | AidataFoundation | Exact Azure Identity lock, one endpoint selector, source registration, routing | AID-PLAN/OA-002 fixed |
| `DATA-L12` | AidataL1L2 | GET-only CLI-DAC Blob adapter, complete-unit state and provenance | DATA-FOUND, AID-DEP |
| `DATA-L3` | AidataL3 | Honest idempotent product-event fact | DATA-L12 |
| `DATA-L4` | AidataL4 | Bounded read-only exploratory query | DATA-L3 |
| `DATA-OPS` | AidataOps | Exact scheduled-source order and degraded-source behavior | DATA-FOUND |
| `E2E-05` | Team Lead external gate | Sanitized two-product/two-event correlation | merged producer/data/VitalStride, REL-001, OA-003/OA-004 |

## Dependency graph

```text
accepted central plan + native planning PASS
  + REL-001 --> AID-XCODE --> AID-APP --------+--> SL-AID-PRODUCER
  |                   `--> AID-RELEASE -------'
  |
  `--> DATA-FOUND --> AID-DEP --> DATA-L12 --> DATA-L3 --> DATA-L4 --> SL-DATA
           `-----------------------------------------------> DATA-OPS --'

external SL-VITAL + SL-AID-PRODUCER + SL-DATA
  + REL-001 + OA-001/OA-002/OA-003/OA-004 --> E2E-05
```

Rollback ordering is compensation, not a reverse dependency edge.

## Verification strategy

- Planning: Spec Kit prerequisites/freshness, requirements checklist, FR/AC-to-task coverage, `scripts/context/run RepoInfra --mode local`, and `scripts/context/audit`.
- Producer implementation: `scripts/context/run XcodeWorkspace --mode ci`; `scripts/context/run AIDashApp --mode ci`; generated-project diff; required macOS/iOS CI; no host-based local app tests.
- Reader implementation: each Aidata leaf's local resolver gate, new hermetic focused tests, full aidata pytest/Ruff CI, and repository context audit after every routing change.
- Release plumbing: synthetic raw-plus-shell-escaped sentinel exercises actual Release path and proves 0600, path-only invocation, and both success/failure cleanup without using real values.
- Security: changed-file scan rejects actual endpoints, identity metadata, tokens, SAS/account keys, credential-bearing URLs, and fixtures/logs containing sentinels.
- Final: exact local/pushed/PR revisions for implemented slices, then independent E2E-05 evidence review. CI status is not substituted for local gate evidence.

## Risks

- `azure-identity` changes aidata's stdlib-only baseline. Exact lock, separate ADR, routed manifest, CI install, and dependency audit contain this risk.
- Release injection spans XcodeWorkspace and RepoInfra; split tasks prevent cross-layer ownership drift.
- `AIDashApp` currently lacks a hostless resolver test gate; AID-APP must add it before claiming hermetic producer acceptance.
- The LokiKit release identity remains unresolved; REL-001 blocks only AID-XCODE and live proof.
- The future sandboxed fixed install has no network entitlement; this plan neither edits nor works around ADR-003.
- Local Azure identity availability is operational state. No-op is correct; implementation must never prompt or choose a substitute principal.

## Planning completion gate

The native planning slice is complete only when all listed artifacts and both ADRs are present, task freshness/coverage has no ERROR or CRITICAL finding, RepoInfra local/audit gates pass, no sensitive identifier is tracked, and AI Reviewer returns PASS for one exact planning revision.
