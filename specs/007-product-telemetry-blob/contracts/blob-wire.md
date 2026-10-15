# Contract: Product Telemetry Blob Wire and Durability

## Writer request

- HTTPS `PUT` BlockBlob with `If-None-Match: *`.
- `Content-Type: application/x-ndjson`; `Content-Encoding: gzip`.
- Object path: `<app>/<build>/<UTC yyyy-mm-dd>/<install-id>/<batch-uuid>.ndjson.gz`.
- Decompressed body: NDJSON with `name`, closed `properties`, and ISO timestamp per event. AIDash event names, triggers, typed properties, timing, sampling, and cardinality are fixed by `contracts/aidash-events.md`.
- Product allowlists reject the whole event for unknown keys, free text, or non-finite numbers before accepted persistence or network transmission.

Before the first request, a checksummed credential-free sidecar freezes compressed bytes, source digest, destination, and object path. Retry/restart reuses those exact values. Destination drift or corrupt/mismatched input retains and blocks the batch.

Queue removal is allowed only for HTTP `201`, or for a previously ambiguous immutable retransmission that returns HTTP `403` with exactly `x-ms-error-code: UnauthorizedBlobOverwrite`. Every first overwrite rejection, other 403/409/error, and network ambiguity retains work.

Producer transport uses an isolated ephemeral session with no ambient credential store, cookies, shared cache, additional headers, or inherited proxy configuration. Redirects are refused. Server-trust evaluation may use the platform trust path; every other authentication challenge is cancelled.

## Producer host configuration

The GUI host owns these plist keys:

- `LokiKitBlobEndpoint` → `$(TELEMETRY_BLOB_ENDPOINT)`
- `LokiKitBlobSAS` → `$(TELEMETRY_BLOB_SAS)`

Tracked build settings are empty. Protected CI values are written only into one run-owned runner-temp xcconfig at mode `0600`; build tools receive only the file path with `-xcconfig`. Fastlane `ensure` and workflow `if: always()` both delete it. Raw and shell-escaped sentinel values must be absent from captured Release stdout/stderr.

The app manually reads expanded keys and calls the direct initializer only after
GUI mode, persisted explicit consent, install-ID readiness, and producer
configuration validate. First opt-in may create the local consent preference
and random UUID even when configuration is invalid, but invalid configuration
creates no telemetry service/store/uploader/timer/network work. The initializer
uses a Blob-only store, the product privacy allowlist, the persisted random UUID
provider, and `heartbeatVersion: nil`. The bundle convenience initializer is
forbidden.

If a generation-bound Reset target is pending, the same valid construction
opens the retained service disabled. Admission and flush remain closed while
the app reads the catalog's current epoch, accepts an already-current target or
otherwise applies the pinned SDK reset seam, and reads back proof. Only proof
that the target is current may promote it, clear the matching generation, and
enable the service. Failure, ambiguity, malformed state, or stale completion
leaves the exact transition pending and retryable; retry reconciles before
deciding whether another SDK reset is needed.

## Reader interpretation

The reader accepts only the exact five-segment object layout and complete gzip NDJSON unit. It derives a deterministic source-event key from canonical object path plus line ordinal, retains product/build/time and sanitized object provenance, and advances completion state only after the whole unit succeeds.

## Lifecycle and rollback

`flush()` completion is not remote-receipt evidence. Turning consent off first
persists false, closes admission, disables/cancels active delivery, and then
awaits quiescence. No queued/later upload may start or continue while off; a
request made ambiguous by cancellation remains retained and unconfirmed. The
store, pending files, install ID, epochs, and history remain. Re-enable is fresh
consent; eligible retained work resumes only when no Reset is pending. Before
first opt-in, Reset is disabled/no-op. After an ID exists, Reset first
disables/cancels active delivery and awaits quiescence, then persists a target
UUID and opaque generation. While off it constructs/uploads nothing. On the
next consented valid construction, disabled catalog reconciliation and target
epoch proof must complete before any admission/flush. Failure or ambiguity
remains pending, closed, and retryable across restart. Reset affects future
batches only and never rewrites frozen paths/batches or deletes history.
Dependency rollback follows the same disable/cancel/quiesce/retain order and
never represents reset as deletion.
