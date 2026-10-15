# Data Model: Product Telemetry Blob Pipeline

## Producer models

### ProductTelemetryConfiguration

| Field | Type | Rule |
|---|---|---|
| `containerURL` | URL | Query-free HTTPS container URL; no userinfo/fragment/embedded credential |
| `sasQuery` | opaque runtime value | Producer-only create authority; never logged/persisted outside protected build/runtime seams |
| `app` | closed string | Trusted product identifier, not user input |
| `build` | closed string | Trusted build identifier |
| `consent` | bool | Must be true before identity/store/network construction |
| `storeDirectory` | path | Blob-only, isolated from Loki and UserEvent stores |
| `maxDiskBytes` | positive integer | Invalid/zero/overflow fails before store creation |
| `heartbeatVersion` | null | Always `nil`; no SDK timer/heartbeat |

State: `disabled` → `validated` → `active` → `quiescing` → `disabledRetained`. Invalid input stays `disabled` and creates no durable/network side effect.

### ProductEvent

| Field | Type | Rule |
|---|---|---|
| `name` | product-local closed string | Exactly one action kind or one performance kind for the canary set |
| `timestamp` | ISO-8601 UTC | Required |
| `properties` | closed scalar map | Static allowlist; no free text; finite numeric values only |

Unknown key, free text, or non-finite number rejects the whole event before accepted persistence/network.

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

No page/object cursor advances for partial list, download, decompression, parse, redaction, or publication failure.

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
