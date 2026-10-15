# Contract: Product Telemetry Blob Wire and Durability

## Writer request

- HTTPS `PUT` BlockBlob with `If-None-Match: *`.
- `Content-Type: application/x-ndjson`; `Content-Encoding: gzip`.
- Object path: `<app>/<build>/<UTC yyyy-mm-dd>/<install-id>/<batch-uuid>.ndjson.gz`.
- Decompressed body: NDJSON with `name`, closed `properties`, and ISO timestamp per event.
- Product allowlists reject the whole event for unknown keys, free text, or non-finite numbers before accepted persistence or network transmission.

Before the first request, a checksummed credential-free sidecar freezes compressed bytes, source digest, destination, and object path. Retry/restart reuses those exact values. Destination drift or corrupt/mismatched input retains and blocks the batch.

Queue removal is allowed only for HTTP `201`, or for a previously ambiguous immutable retransmission that returns HTTP `403` with exactly `x-ms-error-code: UnauthorizedBlobOverwrite`. Every first overwrite rejection, other 403/409/error, and network ambiguity retains work.

Producer transport uses an isolated ephemeral session with no ambient credential store, cookies, shared cache, additional headers, or inherited proxy configuration. Redirects are refused. Server-trust evaluation may use the platform trust path; every other authentication challenge is cancelled.

## Producer host configuration

The GUI host owns these plist keys:

- `LokiKitBlobEndpoint` → `$(TELEMETRY_BLOB_ENDPOINT)`
- `LokiKitBlobSAS` → `$(TELEMETRY_BLOB_SAS)`

Tracked build settings are empty. Protected CI values are written only into one run-owned runner-temp xcconfig at mode `0600`; build tools receive only the file path with `-xcconfig`. Fastlane `ensure` and workflow `if: always()` both delete it. Raw and shell-escaped sentinel values must be absent from captured Release stdout/stderr.

The app manually reads expanded keys, validates them before identity/store creation, and calls the direct initializer with a Blob-only store, product privacy allowlist, nonpersonal UUID provider, explicit consent, and `heartbeatVersion: nil`. The bundle convenience initializer is forbidden.

## Reader interpretation

The reader accepts only the exact five-segment object layout and complete gzip NDJSON unit. It derives a deterministic source-event key from canonical object path plus line ordinal, retains product/build/time and sanitized object provenance, and advances completion state only after the whole unit succeeds.

## Lifecycle and rollback

`flush()` completion is not remote-receipt evidence. Disable/rollback awaits active flush exit and retains pending files, unconfirmed epochs, and historical identity. It never erases the store, rotates pending identity, or represents reset as deletion.
