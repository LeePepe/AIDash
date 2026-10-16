# Data Model: Product Telemetry Blob Pipeline

## Producer models

### AIDashTelemetryPreferences

| Symbolic local key | Type | Rule |
|---|---|---|
| `telemetry.sendUsageData` | `Bool` | Missing or malformed is `false`; the cross-platform GUI Settings toggle **Send usage data** is the sole production writer |
| `telemetry.installID` | canonical UUID string | Absent in the exact never-opted state; created randomly once only when that state receives its first false-to-true action, persisted before the marker and active consent, and reused across launches and consent cycles for the app's lifetime |
| `telemetry.identityEstablished` | `Bool` | Key is absent before first opt-in and persisted as `true` after the first UUID is written; it is monotonic lifecycle provenance, contains no identity value, and is never cleared or set to `false` in version 1 |

Production preferences read/write `UserDefaults.standard` through the
app-owned seam. Hook-owned hostless tests inject an isolated suite and never
touch the user's standard defaults. The seam derives one explicit state from
all three raw keys; it does not use `bool(forKey:)` in a way that loses
missing/malformed-marker information:

| Derived state | Stored conditions | Allowed behavior |
|---|---|---|
| `neverOpted` | Consent is off; marker key is absent; install-ID key is absent | The only state from which a false-to-true action may generate one UUID |
| `establishedDisabled` | Consent is off; marker is exactly `true`; install ID is a canonical UUID | Retain both values; re-enable reuses the UUID without calling UUID generation |
| `establishedEnabled` | Consent is exactly `true`; marker is exactly `true`; install ID is a canonical UUID | Eligible for later producer-configuration validation |
| `establishedInvalid` | Consent is true without a complete established identity; the marker exists but is not exactly `true`; the marker is true with a missing/malformed UUID; or any install-ID value exists without a true marker | Fail closed, keep consent inactive, create no producer resources, and never generate a replacement UUID |

First opt-in is the only UUID creation point: write the canonical UUID, persist
the monotonic marker as `true`, and only then make consent active. A partial or
corrupt combination is never reclassified as `neverOpted`. The marker is not a
second identifier and is never emitted, logged, copied into events, or used in
an object path. Identity never derives from `AIDashCore.DeviceIdentifier`,
device/hardware attributes, account data, a credential, or private telemetry
storage.

Turning consent off persists `false` before admission closes and upload
is disabled/cancelled, then awaits quiescence. The established marker, install
ID, isolated store, frozen pending batches, and SDK history remain; a request made
ambiguous by cancellation stays retained/unconfirmed and no work uploads while
off. Re-enable is fresh consent and resumes eligible retained work under the
same retained ID. If the retained identity is missing/malformed, re-enable
enters `establishedInvalid` and fails closed rather than recreating it. Version
1 has no Reset/rotation action or alternative identity value; the monotonic
marker records only whether UUID creation has already occurred. A future Reset
requires its own SDK feature and product decision.

### ProductTelemetryConfiguration

| Field | Type | Rule |
|---|---|---|
| `containerURL` | URL | Query-free HTTPS container URL; no userinfo/fragment/embedded credential |
| `sasQuery` | opaque runtime value | Producer-only create authority; never logged/persisted outside protected build/runtime seams |
| `app` | closed string | Trusted product identifier, not user input |
| `build` | closed string | Trusted build identifier |
| `consent` | bool | Read from `telemetry.sendUsageData`; must be true before telemetry service/store/uploader/timer/network construction |
| `installID` | UUID | From the lifetime-stable `telemetry.installID`; never derived from device identity or private telemetry storage |
| `storeDirectory` | path | Blob-only, isolated from Loki and UserEvent stores |
| `maxDiskBytes` | positive integer | Invalid/zero/overflow fails before store creation |
| `heartbeatVersion` | null | Always `nil`; no SDK timer/heartbeat |

Producer state: `disabled` → `eligible` → `validated` → `active` →
`quiescing` → `disabledRetained`. Only `establishedEnabled` preferences may
enter `eligible`; `neverOpted`, `establishedDisabled`, and
`establishedInvalid` remain producer-disabled. First opt-in may persist the
install ID, established marker, and consent before endpoint validation.
Invalid producer input stays `eligible` or `disabled` and creates no telemetry
service, store, uploader, timer, or network side effect. CLI, headless/XPC, and
test-host production composition cannot enter `eligible`.

### ProductEvent

| Field | Type | Rule |
|---|---|---|
| `name` | product-local closed string | `aidash.action` or `aidash.performance.ready_scene` only |
| `timestamp` | ISO-8601 UTC | Required |
| `properties` | SDK 0.2.0 string-to-string dictionary | Exact semantic allowlist in `contracts/aidash-events.md` |

`aidash.action` carries only `action_name: "briefing_viewed"`.
`aidash.performance.ready_scene` carries only `duration_ms` as a decimal string
encoding a finite nonnegative integer, computed as complete monotonic
milliseconds from the first
instant of the GUI-production app-init branch—before consent/config reads—to
first interactive `.ready(container)` appearance. The start is discarded when
the lifecycle is ineligible. Both events are unsampled and at
most once per eligible GUI lifecycle. Unknown keys/values, free text,
non-finite numbers, negative duration, or overflow reject the whole event
before accepted persistence/network.

### FrozenBlobBatch

| Field | Type | Rule |
|---|---|---|
| `compressedBytes` | gzip NDJSON bytes | Frozen before first request |
| `sourceDigest` | lowercase SHA-256 | Covers accepted source batch |
| `bodyDigest` | lowercase SHA-256 | Covers exact compressed bytes |
| `destination` | credential-free canonical URL | Never includes SAS |
| `objectPath` | five-part path | `<app>/<build>/<date>/<install-id>/<batch-id>.ndjson.gz` |
| `attemptState` | enum | `unattempted`, `ambiguous`, `confirmed` |

Retry reuses every frozen field. Only `201`, or exact qualified overwrite response after `ambiguous`, transitions to `confirmed` and permits queue removal.

## Manual reader models

The complete behavioral authority is
[`contracts/manual-batch-collector.md`](contracts/manual-batch-collector.md).
This file names only the durable concepts needed by planning and does not
restate the collector algorithm.

### ProductBlobManualConfiguration

| Field | Type | Rule |
|---|---|---|
| `containerURL` | string | Empty tracked default; real value only in ignored local config |
| `prefix` | string | Empty tracked default; exactly one validated VoxPocket prefix only in ignored local config |

Both fields empty is disabled. There is no credential, identity, token, SAS,
account key, tenant, auth-mode, cap, page, cursor, registry, schedule, or
checkpoint field.

### CompletionBatch

| Field | Type | Rule |
|---|---|---|
| `batchId` | random non-identity name | Fresh for one invocation; names one completion directory and is never a cross-run key |
| `root` | relative private path | `product_blob/batches/<batch-id>` under `RAW_DIR`; absolute paths are not public output |
| `objects` | nonempty relative file tree | Byte-identical opaque gzip downloads at their relative Blob paths |
| `state` | filesystem fact | Absent before one atomic directory publish; complete and immutable afterward |

The directory is the L1 unit. The collector creates no per-object raw record,
parsed event, normalized product row, page/object cursor, event identity, L3
fact, L4 product query, or L5 consumer. MB-017's later temporary evidence reader
creates no repository entity, table, state, or reusable product query.

### CollectionOutcome

| Status | Durable result | CLI result |
|---|---|---|
| `disabled` | No stage and no completion | successful `empty` envelope with count zero |
| `empty` | Temporary stage removed or ignored; no completion | successful `empty` envelope with count zero |
| `completed` | Exactly one immutable nonempty `CompletionBatch` | successful `completed` envelope with safe batch ID and positive count |
| `failed` | No pre-commit-point completion; catchable cleanup is best effort | Constitution error envelope with one fixed neutral message, exit 1 |

An uncatchable kill may leave a private staging directory. Staging is not a
state value and is never consumed as a completion. The atomic rename is the
commit point: after it the batch is complete even if the caller loses the
success response.

## T7 association

`ManualBatchEvidence` is private workflow evidence, not a repository table:

```text
exact merged revision + actual TestFlight build + UTC interval
  -> actual Blob relative name
  -> one completion batch + matching relative file
  -> query filtered to that completion batch and Blob + scoped count
```

Its ephemeral source locator is `(batchId, relativeBlobPath,
ndjsonLineNumber)`. Locator uniqueness, one-pass wire validation, filter rules,
counting, execution ownership, and privacy are defined only by MB-017; the
locator is not persisted or reused across batches.

Immediately before T7, the Owner-authorized workflow 05 lead/operator re-reads
the exact final merged VoxPocket producer contract/head; that external contract,
not AIDash's unchanged `contracts/aidash-events.md`, governs the temporary event
counts. Execution uses a Codex subagent in the workflow lead's local session and
does not give the Multica Team Lead local-session, TestFlight, Azure, credential,
or manual-dispatch authority.

The public record contains only sanitized labels/counts. It carries no real
endpoint, principal metadata, token/SAS/key, actual Blob name, install UUID,
absolute local path, or raw payload, and it makes no cross-run idempotency
claim.
