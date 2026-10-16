# Research: Product Telemetry Blob Pipeline

## Authority reviewed

- Accepted MY-1816 planning v6, SHA-256 `97dc0822f4ade9f6e70a5c070e9860c6eeb57076e0744f1cdd7744750e8c55f2`.
- AIDash constitution 1.14.0 amendment, repository context routers, `aidata/adapters/CONTEXT.md`, ADR-003, and the existing manual-import contract.
- Owner decision `aad-owner-local`, effective 2026-10-15. The external authority record carries the actual operator/resource metadata; this public repository intentionally does not.
- Lead replacement decision `no-reset-v1`, effective 2026-10-15 on the Owner's behalf: authorize constitution 1.14.0, default-off Settings consent, one lifetime-stable first-opt-in random install UUID, no Reset/rotation in version 1, GUI-only composition, and Planner-owned minimal AIDash event vocabulary.

## Decision D-01: keep product semantics outside shared telemetry

**Decision**: AIDash owns its action/performance names, allowed fields, sampling, and formulas. LokiKit supplies generic transport, timing, validation, persistence, and diagnostics only.

**Rationale**: A shared product taxonomy would couple unrelated applications and contradict the accepted central plan. Product-local semantics also let hostless tests prove the exact two AIDash canary kinds without changing shared code.

**Alternatives rejected**:

- Put AIDash and VitalStride event enums in shared telemetry: shared transport must not own product vocabulary.
- Reuse CloudKit `UserEvent`: telemetry delivery, consent, retention, and Blob durability are different contracts.
- Add an SDK heartbeat: AIDash is explicitly timer-free and passes `heartbeatVersion: nil`.

## Decision D-03: explicit consent, random install identity, and minimal AIDash events

**Decision**: The GUI Settings toggle **Send usage data** is the sole consent
authority. It defaults off in app-scoped `UserDefaults`. First opt-in creates a
random persisted UUID, then persists a monotonic non-identity
`telemetry.identityEstablished` marker before consent becomes active. The exact
never-opted state has neither marker nor UUID and is the only state allowed to
generate one. Later launches and consent cycles retain the marker and reuse the
UUID for the app's lifetime. A marker/UUID/consent mismatch or a
missing/malformed post-opt-in UUID fails closed without replacement. Turning
consent off first persists false, closes admission, disables/cancels delivery,
and awaits quiescence while retaining ambiguous/pending work, the marker, and
identity history. No queued work uploads while off. Re-enable is fresh consent
and resumes under the same UUID. Version 1 exposes no install-ID Reset/rotation. AIDash adds no shared
reset API and never parses private telemetry storage for identity. CLI,
headless/XPC, and test-host production composition never constructs the
service.

AIDash defines exactly the two events in `contracts/aidash-events.md`:
`aidash.action` with closed `action_name=briefing_viewed`, and
`aidash.performance.ready_scene` with a monotonic integer `duration_ms` from
entry to the GUI-production app-init branch—before consent/configuration
reads—to first interactive `.ready(container)` appearance. The captured start
is discarded when the lifecycle is ineligible. Both events are unsampled and at
most once in an eligible GUI lifecycle.

**Rationale**: Default-off, product-owned consent prevents accidental telemetry
construction; a random opt-in identity avoids hardware/account-derived identity.
The monotonic non-identity marker distinguishes never-opted from a disabled or
corrupt post-opt-in state, so re-enable cannot silently reinterpret corruption
as permission to create a new lifetime identity.
The single first-ready callback makes action and performance evidence
deterministic without expanding shared telemetry vocabulary.

**Alternatives rejected**:

- Reuse `AIDashCore.DeviceIdentifier`: it can expose device/hardware identity
  and exists independently of telemetry consent.
- Enable by endpoint presence: producer configuration is not consent.
- Create an ID at install/launch: identity must not precede first opt-in.
- Infer never-opted from consent plus UUID absence alone: after opt-out that
  would make a corrupt retained identity look pristine and permit silent
  rotation; the monotonic established marker makes the states explicit.
- Delete pending state on disable: this contradicts the SDK retention contract
  and would rewrite or orphan frozen immutable batches.
- Add Reset/rotation in version 1: the replacement decision finds no current
  product need; adding shared-SDK surface or parsing private catalog storage is
  unjustified. Revisit only as a separately authorized SDK feature.
- Silently replace a missing/malformed established ID: that is unrequested
  rotation; fail closed instead.
- Emit after a mid-lifecycle opt-in: a retrospective ready event lacks the
  required launch-to-ready boundary.

## Decision D-02: retain the writer and replace only the reader contract

**Decision**: Preserve the producer request, host configuration, immutable
retry, consent, and rollback rules in `contracts/blob-wire.md`. Replace only
the unshipped reader interpretation with the single normative contract in
`contracts/manual-batch-collector.md`.

**Rationale**: Producer durability and privacy are already merged behavior.
The selected human-operated reader needs only one opaque, immutable L1 batch
directory; event parsing, per-object provenance/state, and L2-L4 materialization
would add machinery the accepted T7 outcome does not require.

**Alternatives rejected**:

- Treat `flush()` as receipt: it proves only local control flow.
- Drop on any 403/409: only one exact ambiguous-retry response proves immutable prior creation.
- Parse or publish individual events while landing the batch: rejected because
  the selected L1 unit is the complete opaque directory.

## Decision OA-002: direct Azure CLI manual batch

**Decision**: `PRODUCT_BLOB_CONTAINER_URL` plus one
`PRODUCT_BLOB_PREFIX` are the only reader selectors. The repository invokes the
installed Azure CLI directly for one manual
`storage blob download-batch --auth-mode login --overwrite false` and never
parses a token. Configuration, preflight, argv, environment/privacy, staging,
publication, CLI output, timeout, tests, and T7 evidence are defined only by
`contracts/manual-batch-collector.md`.

**Rationale**: This retains the Owner-selected existing read-only Azure AD
identity while delegating listing/downloading to the already installed CLI.
The direct batch removes the first non-stdlib Python dependency, hand-built
pagination/GET/token handling, custom caps, checkpoints, and cross-run recovery.
The batch and real selectors remain private local operational state.

**Dependency consequence**: none. Azure CLI is an external operator/runtime
tool with a real operator-machine installation, runtime, subprocess/preflight,
and disk cost. It adds zero repository/product binary bytes, build-system work,
Swift-concurrency surface, or Python-lock cost. Accepted ADR-005 records the
architecture, alternatives, and cost; the contract pins the mechanics and
accepted CLI version/cloud preflight.

**Alternatives rejected**:

- Dedicated service/workload principal: superseded by the Owner decision for this version.
- Read/list SAS or the existing `local-read` policy: explicitly inactive.
- Raw `az account get-access-token` subprocess parsing: unnecessary and adds
  token/output handling.
- Python `DefaultAzureCredential` plus stdlib LIST/GET: superseded because the
  direct batch supplies the accepted outcome with materially less code/state.
- Azure Storage SDK: unnecessary dependency surface for one manual batch.

## GUI-only dependency placement

LokiKit is wired only into `AIDashApp` and `AIDashAppLogicTests` through `project.yml` and app-local composition. It does not enter AIDashCore, AIDashUI, CLI, headless XPC composition, or host-based local tests. The factory manually reads the two expanded plist values and calls the direct initializer rather than a bundle convenience initializer.

The dependency costs and fixed-install caveat are recorded in ADR-004. This
manual-reader decision neither changes nor reopens the merged producer
dependency and consent implementation.

## Reader completion boundary

One invocation has one private `tempfile` stage and at most one immutable L1
completion directory. The Azure batch exit must be zero and the stage must
contain at least one safe regular object. Product code keeps bytes opaque,
fsyncs the staged tree, and uses one same-filesystem atomic directory publish;
that rename is the completion point. Empty success is a zero-object no-op.
Failure or interruption before the completion point creates no result, and an
abandoned stage is never considered one. Later successful invocations produce
independent directories without resume, checkpoint, deduplication, or
cross-run idempotency. Full mechanics remain exclusively in the contract.
Real-filesystem acceptance observes current UID/private modes, unsafe terminal
and output types/path escape, and completed-directory retention when response
loss or interruption occurs after the real delegated rename.

## Layering result

- `XcodeWorkspace`: dependency, empty build settings, plist expansion plumbing, and Fastlane path-only xcconfig consumption/cleanup.
- `RepoInfra`: this canonical planning/contract revision only; no dependency
  installation or new implementation task.
- `AIDashApp`: GUI lifecycle, consent, direct construction, action/PLT emission, rollback retention, and hostless-test gate declaration.
- `AidataFoundation`: two empty selectors, dedicated manual CLI surface,
  neutral JSON output, and matching config/CLI tests and routing.
- `AidataL1L2`: one direct batch adapter, private completion-directory
  publication, executable fake-`az` evidence, and matching routing.
- No AidataL3, AidataL4, AidataL5, AidataOps, registry, scheduler, dependency,
  or generic-collect change.

## Remaining gates

- **Manual-batch planning PASS**: the exact RepoInfra planning revision must
  pass independent review and merge before implementation is dispatched.
- Separate live-operation authority gates TestFlight, Azure, manual collection,
  and private T7 evidence. Those operations do not block hermetic
  implementation and are not authorized by this plan. After both merges, the
  Owner-authorized workflow 05 lead/operator—not the Multica Team Lead—must
  re-read the exact final merged VoxPocket producer contract/head, confirm the
  existing authorization still applies, and use any Codex subagent only in the
  workflow lead's own local session.
