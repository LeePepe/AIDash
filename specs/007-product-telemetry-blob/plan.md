# Implementation Plan: Manual Product Blob Batch Landing

**Feature**: `007-product-telemetry-blob`
**Base**: `eb292dc041dab6c5722e270f0f138ecd35949509`
**Status**: Planning gate

## Summary

Preserve the merged explicit-consent AIDash producer and replace only the
unshipped product Blob reader plan. A later authorized human runs one bounded
Azure CLI `download-batch`; after successful nonempty download, aidata publishes
the entire opaque gzip tree as one immutable L1 completion directory. The sole
behavioral authority is
`contracts/manual-batch-collector.md`.

There is no Python Azure dependency, token parser, per-Blob registration,
custom cap, resume/checkpoint/deduplication, generic source activation,
unattended operation, scheduler, or L2-L5 product path.

## Existing behavior, compatibility, and removed planned behavior

### Existing behavior retained

- Live-main producer/consent behavior remains governed by Constitution 1.14.0,
  ADR-004, `contracts/aidash-events.md`, and the producer/lifecycle portions of
  `contracts/blob-wire.md`; none is an implementation target here.
- Generic `collect`, existing source registries, runner, cron behavior, all
  existing tests, CloudKit/UserEvent behavior, and the rest of aidata L1-L5
  remain unchanged.
- Empty tracked configuration and an absent local override remain hermetic
  no-op behavior. Real endpoint/prefix and identity state remain local and
  private.

### Compatibility

- The new command is additive and unregistered. It cannot be reached through
  generic `collect`, a source registry, runner, cron, or scheduler.
- Completion batches live under the existing ignored `RAW_DIR`; no database,
  state-file, schema, query, or migration compatibility is introduced.
- Existing producer object bytes and paths are not changed. The reader stores
  them as an opaque relative file tree.

### Removed planned behavior

The unshipped Python `DefaultAzureCredential`/stdlib LIST+GET reader,
`azure-identity` lock/CI installation, page/object cursors, per-event raw IDs,
8 MiB/64 MiB custom caps, NDJSON parsing, L2-L4 product rows/query, registry
activation, Ops runner/scheduler, and cross-run resume/deduplication are
superseded by MB-020. No live-main production behavior or existing test is
deleted or weakened.

## Technical context

**Language**: Python 3.14 for the manual command
**External runtime**: pinned Azure CLI `2.91.0`; GNU `gtimeout` is an operator boundary
**Repository dependencies**: none added
**Storage**: private same-filesystem staging plus immutable L1 completion directories under `RAW_DIR`
**Verification**: normal layer-owned commit/push hook receipts, required aidata CI, context audit, and one executable fake `az`
**Privacy**: no endpoint, account/container/prefix, identity, token, actual Blob name, absolute local path, or payload in public output/evidence
**Scope**: RepoInfra authority, then AidataFoundation → AidataL1L2 implementation; no other layer

## Constitution check

| Gate | Result |
|---|---|
| §Principles I-II / merged producer | PASS — producer, consent, CloudKit, and UserEvent authority are unchanged |
| §A Scope Discipline | PASS — each future task has one owning layer, exact paths, exclusions, contract, and dependency |
| §B CLI Surface | PASS — MB-014 and MB-015 use the Constitution success/error envelopes; the failure message is fixed and neutral |
| §D Error Handling | PASS — all config/process/filesystem failures degrade without crash or private interpolation |
| §G Test Coverage | PASS — the dedicated command has real success and validation/failure evidence through its public seam |
| §Dependencies | PASS — external Azure CLI/GNU timeout add no repository or Swift dependency |
| §Testing / Quality Gates | PASS — hooks/CI own tests; the Planner runs only documented static planning checks |
| §No Identity in Version Control | PASS — both selectors are empty when tracked; fixtures and evidence are neutral/hermetic |
| Layer direction | PASS — RepoInfra authority precedes separate AidataFoundation and AidataL1L2 commits |

No Constitution or gate change is planned.

## Canonical artifacts

```text
docs/adr/005-azure-cli-reader-identity.md       # superseded pointer
specs/007-product-telemetry-blob/
├── spec.md
├── plan.md
├── tasks.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
└── contracts/
    ├── manual-batch-collector.md               # sole reader authority
    ├── reader-auth.md                          # superseded pointer
    ├── blob-wire.md                            # producer retained; reader pointer
    ├── e2e-evidence.md                         # T7 batch/Blob-scoped proof
    └── aidash-events.md                        # unchanged producer authority
```

All planning paths resolve to `RepoInfra`. ADR-004 and
`contracts/aidash-events.md` remain byte-identical.

## Module and seam design

The deep module interface is one dedicated `product-blob` CLI command. Callers
know only disabled/empty/completed/failure outcomes; configuration validation,
Azure preflight/argv/privacy, tempfile staging, fsync, and atomic publication
stay behind that interface.

The external Azure seam has two concrete adapters: the installed Azure CLI in
production and one scenario-driven executable fake `az` in tests. Tests call
the same real CLI/adapter/filesystem path and observe invoked argv plus final
filesystem state; they do not expose internal helper choreography or fabricate
completion.

The completion-directory rename is the commit point. A kill before it leaves
no completion; after it, the whole batch is complete even if the caller loses
the success response. This is atomic completion, not partial recovery state.

## Future implementation paths and commits

### Commit 1 — `MANUAL-FOUND` / AidataFoundation

Exact owned paths:

- `aidata/config.py`
- `aidata/config_local.example.py`
- `aidata/cli.py`
- `aidata/tech-context.md`
- `aidata/CONTEXT.foundation.md`
- matching Foundation test-routing hunk in `aidata/CONTEXT.md`
- `aidata/tests/test_config_m3.py`
- `aidata/tests/test_product_blob_cli.py` (new)

Outcome: two empty selectors, additive unregistered command, Constitution JSON
success/error envelopes, fixed neutral failure message, config/import/return validation, and
Foundation routing. It does not add an adapter, registry entry, dependency,
runner, schedule, or generic-collect behavior.

### Commit 2 — `MANUAL-L12` / AidataL1L2

Exact owned paths:

- `aidata/adapters/product_blob.py` (new)
- `aidata/adapters/CONTEXT.md`
- matching L1/L2 test-routing hunk in `aidata/CONTEXT.md`
- `aidata/tests/test_product_blob.py` (new)

Outcome: the complete MB-001–MB-020 adapter behind the command, one executable
fake `az`, and direct argv/privacy/filesystem acceptance. It does not use
`rawio.py`, normalize, merge, schema, query, L5, scripts, registries, or state.

`MANUAL-L12` depends on `MANUAL-FOUND`, matching
`AidataL1L2 → AidataFoundation`. Each commit is independently hook-verifiable;
final review binds the descendant chain's exact head.

## Task and dependency graph

```text
reviewed + merged RepoInfra authority
  -> T101 MANUAL-FOUND (AidataFoundation)
  -> T102 MANUAL-L12 (AidataL1L2)
  -> exact-head implementation review/publication
  -> separately authorized post-merge T7 evidence
```

There is no AidataOps, registry, scheduler, dependency-lock, L3, L4, L5, or
activation task. The task metadata is in `tasks.md`.

## Verification strategy

- Planning: Spec Kit prerequisites, task freshness, context audit, acceptance
  coverage, privacy scan, and `git diff --check`; a normal commit supplies the
  resolver-selected RepoInfra hook receipt.
- Foundation: normal commit/push receipts plus required aidata CI prove config
  hermeticity, the additive CLI boundary, success envelope, and neutral failure.
- L1/L2: one fake executable drives exact preflight/batch argv and child
  environment through the real interface. Tests assert real stage/completion
  outcomes, byte equality, fsync/rename calls, no private output, no completion
  on empty/nonzero/pre-commit interruption, abandoned-stage ignore, and
  independent later completion.
- Existing tests remain present and unweakened; additive assertions within an
  owning task are allowed. Any deletion, skip, weakening, Constitution change,
  or gate waiver requires separate Owner approval on the future published final
  PR head.

## Post-merge T7 milestone

After separate live authorization, the operator uses the exact MB-016 command.
The private evidence file associates the real TestFlight build and actual Blob
name with one completion batch. A real read-only query is explicitly scoped to
that batch and Blob and records its filtered result/count. Generic `collect`,
if separately requested, is labelled independently and is not ingestion
evidence. No plan or test template is represented as a live query result.

## Historical evidence boundary

Unpublished implementation evidence `499b40cb84e8c95b3958139c255713aa77d01a5f`,
the planning chain `a7807696` → `e8b60e9` → `00e01d8` → `4d0738b`, and their
failed verdict/claim-source history remain preserved external evidence. They
are not an implementation base for this version. A later implementation, if
separately dispatched, starts from the exact merged live-main descendant that
contains this reviewed plan.

## Risks and stop conditions

- A retained/live-main production or test defect discovered during future
  implementation returns to Team Lead with exact evidence. It is not silently
  repaired by widening T101/T102.
- A requested production/test deletion, skip, weakening, Constitution edit, or
  gate change requires separate Owner approval on the future published final
  PR head.
- Actual selectors, Blob names, identity information, credentials, Azure
  access, TestFlight operations, and live query execution remain outside this
  planning revision.

## Planning completion gate

The plan is ready for implementation decision only after all canonical
artifacts agree, every changed path resolves to RepoInfra, static planning
checks and the normal commit hook pass, the worktree is clean, and an
independent Reviewer returns Standards + Spec PASS for one exact planning SHA.
That PASS authorizes no implementation or live operation.
