# Data Model: Product Telemetry Blob Pipeline

## Producer models

### AIDashTelemetryPreferences

| Symbolic local key | Type | Rule |
|---|---|---|
| `telemetry.sendUsageData` | `Bool` | Missing or malformed is `false`; the cross-platform GUI Settings toggle **Send usage data** is the sole production writer |
| `telemetry.installID` | canonical UUID string | Absent before first opt-in; created randomly once on the first false-to-true transition, persisted before consent becomes active, and reused across launches and consent cycles for the app's lifetime |

Production preferences read/write `UserDefaults.standard` through the
app-owned seam. Hook-owned hostless tests inject an isolated suite and never
touch the user's standard defaults. First opt-in is the only UUID creation
point. If persisted consent is true but the established UUID is missing or
malformed, construction fails closed instead of silently rotating identity. It
never derives identity from `AIDashCore.DeviceIdentifier`, device/hardware
attributes, account data, a credential, or private telemetry storage.

Turning consent off persists `false` before admission closes and upload
is disabled/cancelled, then awaits quiescence. The install ID, isolated store,
frozen pending batches, and SDK history remain; a request made
ambiguous by cancellation stays retained/unconfirmed and no work uploads while
off. Re-enable is fresh consent and resumes eligible retained work under the
same retained ID. Version 1 has no Reset/rotation action or secondary identity
state. A future Reset requires its own SDK feature and product decision.

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

State: `disabled` → `eligible` → `validated` → `active` → `quiescing` →
`disabledRetained`. First opt-in may persist install-ID/consent preferences
before endpoint validation. Invalid producer input stays `eligible` or
`disabled` and creates no telemetry service, store, uploader, timer, or network
side effect. CLI, headless/XPC, and test-host production composition cannot
enter `eligible`.

### ProductEvent

| Field | Type | Rule |
|---|---|---|
| `name` | product-local closed string | `aidash.action` or `aidash.performance.ready_scene` only |
| `timestamp` | ISO-8601 UTC | Required |
| `properties` | closed scalar map | Exact typed allowlist in `contracts/aidash-events.md` |

`aidash.action` carries only `action_name: "briefing_viewed"`.
`aidash.performance.ready_scene` carries only a finite nonnegative integer
`duration_ms`, computed as complete monotonic milliseconds from the first
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

## Reader configuration and state

### ProductBlobReaderConfiguration

| Field | Type | Rule |
|---|---|---|
| `containerURL` | string | Empty tracked default; real value only in ignored local config |
| `credentialMode` | constant | `aad-owner-local`; not configurable |
| `operations` | constant set | `list`, `read` only |
| `requestTimeoutSeconds` | constant integer | `30` for every list/read request |
| `collectBudgetSeconds` | constant integer | `240` monotonic seconds per `collect()`; below the outer 300-second runner timeout |
| `listMaxResults` | constant integer | `100` per list request |
| `maxListPages` | constant integer | `10` per run |
| `maxObjectReferences` | constant integer | `1,000` listed references/GET attempts per run |
| `maxCompressedBytes` | constant integer | `8,388,608` per object, streaming-enforced |
| `maxDecompressedBytes` | constant integer | `67,108,864` per object, streaming-enforced |

There are deliberately no credential or principal fields.

### BlobObjectReference

| Field | Type | Rule |
|---|---|---|
| `canonicalPath` | string | Validated five-part path; never contains query |
| `etagFingerprint` | string? | Sanitized provenance; not event identity |
| `lastModifiedUTC` | timestamp? | Source metadata only |
| `contentFingerprint` | SHA-256 | Hash of received compressed bytes |

### BlobObjectCursor

| Field | Type | Rule |
|---|---|---|
| `canonicalPath` | string | Stable unit identity |
| `contentFingerprint` | SHA-256 | Detects unexpected same-path drift |
| `completedAtUTC` | timestamp | Written only after full object validation/publication |

### BlobPageCursor

| Field | Type | Rule |
|---|---|---|
| `continuationMarker` | opaque string? | Credential-free service marker; persisted only after the page is completely listed and every listed object is successful or already complete |
| `completedAtUTC` | timestamp | Observation time for the last completed page |

A timed-out, failed, malformed, invalid-path, or oversized object emits no
raw/clean record and receives no object checkpoint. Every listed reference is
selected; an invalid path is rejected before GET and blocks its page marker.
Exhausting the page/object/wall budget after
a complete page is a bounded pause: persist that page's next marker and resume
next run. Exhaustion or failure within a page leaves the page marker unchanged;
already completed object checkpoints remain valid so a retry skips them without
losing failed or later objects. `Content-Length` is only an early-rejection
hint; compressed and decompressed caps are enforced during streaming. Partial
decompression/NDJSON and sensitive material never enter records, state, or
errors.

## L1/L2 records

### ProductBlobRawRecord

Append-only redacted record per accepted event:

| Field | Type | Rule |
|---|---|---|
| `source_event_id` | SHA-256 | `sha256(canonicalPath + "\n" + zero-based line ordinal)` |
| `object_path_fingerprint` | SHA-256 | Never raw install-ID-bearing path in exported evidence |
| `line_ordinal` | non-negative integer | Exact NDJSON position |
| `product` | closed string | From validated path/event contract |
| `build` | closed string | From validated path |
| `event_name` | closed string | Product-owned name |
| `event_timestamp_utc` | timestamp | Parsed ISO timestamp |
| `properties` | closed JSON object | Redacted/validated scalars only |
| `content_fingerprint` | SHA-256 | Object provenance |

Tokens, real endpoint, principal metadata, SAS, account keys, and raw free text are prohibited.

### NormalizedProductEvent

Same stable event identity and provenance as raw, with typed timestamp/properties and source-clean validation status. Same ID/same content is replay; same ID/different content is rejected/observed without overwrite.

## L3 fact

### fact_product_event

Grain: one accepted product event per `source_event_id`.

| Column | Rule |
|---|---|
| `source_event_id` | Primary stable identity |
| `product`, `build`, `event_name` | Closed source dimensions; no inferred formula |
| `event_timestamp_utc` | Event time |
| `properties_json` | Validated closed properties |
| `object_path_fingerprint`, `content_fingerprint`, `line_ordinal` | Provenance/correlation |
| `collected_at_utc` | Pipeline observation time |

Merge is idempotent by `source_event_id`; it never invents product KPIs or overwrites a conflicting immutable event.

## L4 query row

`product/events.sql` returns a stable projection of the fact with explicit product, event-name, and UTC range filters. It is `aidata-tier: explore`, has deterministic ordering, returns empty on missing data, and never attaches/mutates a source DB.

## E2E correlation

`CanaryCorrelation` joins only sanitized evidence:

```text
product/build + event kind + UTC interval
  -> object path fingerprint/content fingerprint
  -> source_event_id + L1 completed cursor
  -> fact_product_event identity/count
  -> L4 query row
```

It never embeds the actual endpoint, SAS/token/key, raw install UUID, personal principal metadata, or raw payload.
