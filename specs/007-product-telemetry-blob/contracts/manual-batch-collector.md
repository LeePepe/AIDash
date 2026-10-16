# Contract: Manual Product Blob Batch Collector

This file is the sole normative contract for the `product-blob` collector.
Other feature artifacts define ownership, sequencing, or evidence and MUST
reference this contract rather than restating its mechanics.

## Authority and threat model

- **MB-001 — Manual scope**: The collector is invoked by an authorized human
  operator for VoxPocket only. It is not registered in generic `collect`, a
  source registry, a runner, cron, scheduler, or L2-L5 pipeline.
- **MB-002 — Reader identity**: Azure CLI uses the Owner's existing signed-in
  Azure AD identity with externally administered Blob read/list authority.
  The repository does not sign in, inspect the identity, parse access tokens,
  add credentials, or change Azure resources or policy.
- **MB-003 — Trusted local host**: The Owner's local filesystem and same-user
  processes are trusted. At startup the collector rejects symlink and
  non-directory terminal paths for the product root, staging root, and
  completion root, and requires each directory's `st_uid` to equal the current
  effective UID with no group/other permission bits (`st_mode & 0o077 == 0`).
  New private directories are created mode `0700`; every stage and completion
  remains current-UID-owned and private. Same-user replacement after those
  checks is outside the threat model; descriptor confinement and repeated
  metadata-call choreography are not required.

## Configuration and preflight

- **MB-004 — Tracked configuration**: tracked defaults and examples expose
  only `PRODUCT_BLOB_CONTAINER_URL = ""` and
  `PRODUCT_BLOB_PREFIX = ""`. Both empty is a successful disabled no-op. A
  partially configured pair fails before staging or Azure use. The URL must be
  exactly `https://<account>.blob.core.windows.net/<container>` with no port,
  query, userinfo, fragment, extra path segment, or percent-encoded structural
  character; account and container use Azure's lowercase DNS grammars. The one
  configured prefix is nonempty slash-separated ASCII `[A-Za-z0-9._-]+`
  segments, with no empty, `.`/`..`, glob, control, or backslash segment. Real
  values exist only in ignored `aidata/config_local.py`.
  That local prefix is the Owner-approved single VoxPocket allowlist value; the
  command accepts no selector argument or per-run override.
  The future AidataFoundation context migration records URL plus this single
  prefix as the only noncredential selector exception for `product_blob`; its
  URL-only/default-empty rule remains unchanged for every other source.
- **MB-005 — Azure CLI preflight**: the implementation resolves one external
  `az` executable and invokes these exact argv sequences with MB-006's child
  environment:

  ```text
  az version --output json --only-show-errors
  az cloud show --name AzureCloud --query {name:name,isActive:isActive,storageEndpoint:suffixes.storageEndpoint,resourceManager:endpoints.resourceManager} --output json --only-show-errors
  ```

  Both commands must exit `0`. The first must report `azure-cli` and
  `azure-cli-core` exactly `2.91.0` and an empty `extensions` object. The second
  must report exactly `AzureCloud`, `true`, `core.windows.net`, and
  `https://management.azure.com/` for the queried tuple. Any other shape or
  value fails closed. The repository never ships an Azure binary or adds a
  Python/Azure SDK dependency.
- **MB-006 — Child privacy**: every Azure child uses `shell=False` and a fresh
  environment. It may inherit only present values for `PATH`, `HOME`,
  `AZURE_CONFIG_DIR`, `TMPDIR`, `TMP`, `TEMP`, `LANG`, `LC_ALL`, `LC_CTYPE`,
  `SSL_CERT_FILE`, and `REQUESTS_CA_BUNDLE`; it then fixes
  `AZURE_CLOUD_NAME=AzureCloud`, `AZURE_LOGGING_ENABLE_LOG_FILE=false`, and
  `AZURE_CORE_COLLECT_TELEMETRY=false`. Every other parent variable is absent,
  including all `AZURE_STORAGE_*`, `ARM_*`, proxy, Python-injection, and
  connection-verification override variables. Preflight output is parsed only
  in memory and never logged. Batch stdout/stderr are discarded. Product output
  and diagnostics contain no endpoint, account/container/prefix, identity,
  token, absolute local path, or payload. Fixtures and public evidence may use
  only clearly synthetic selectors and never a real resource identifier.

## Exact batch invocation

- **MB-007 — One foreground batch**: after preflight the adapter executes
  exactly one foreground command, with account/container derived from the
  validated local URL and one validated local prefix:

  ```text
  az storage blob download-batch
    --account-name <account>
    --source <container>
    --pattern <prefix>/*
    --destination <private-run-stage>
    --auth-mode login
    --overwrite false
    --output none
    --no-progress
    --only-show-errors
  ```

  Argument order is normative. No LIST/GET implementation, custom pagination,
  token parsing, alternate auth mode, fallback, write/delete operation, or
  additional batch is allowed.

## Staging and completion

- **MB-008 — Private same-filesystem stage**: under umask `077`, the collector
  creates `RAW_DIR/product_blob/.staging/<run>` with `tempfile` and publishes
  only to the sibling `RAW_DIR/product_blob/batches/<batch-id>`. Stage and
  destination therefore share a filesystem. A batch ID is a new random,
  non-identity value; it is not a Blob ID, install ID, or cross-run key.
- **MB-009 — Opaque bytes**: downloaded gzip files and their relative Blob
  paths remain byte-for-byte opaque. The collector does not decompress,
  parse, redact, hash for identity, normalize, rename individual leaves, or
  enforce custom per-file/run byte caps. After exit `0`, it checks only the
  filesystem shape needed for safe publication: every entry is a real directory
  or regular file, no entry is a symlink or another special type, every lexical
  and resolved entry remains beneath the run stage, and at least one regular
  downloaded object exists. `product_blob` is the sole opaque immutable-L1,
  no-normalize exception to the AidataL1L2 collect+normalize and redacted
  append-only-raw defaults; those defaults remain unchanged for every other
  adapter.
- **MB-010 — One atomic publication**: after a successful nonempty batch, the
  collector fsyncs every downloaded regular file and the staged directory tree,
  performs exactly one same-filesystem atomic directory rename/`os.replace`
  from the run stage to an absent `batches/<batch-id>`, then fsyncs the
  completion parent. The rename is the commit point. Before it there is no
  completion; after it the entire immutable batch is complete even if the
  caller loses the success response or execution is interrupted. Once the real
  delegated rename returns, later response construction/return failure or
  post-commit interruption must not clean, mutate, or reclassify the completed
  directory. Existing completion directories are never overwritten or mutated.
- **MB-011 — Empty, failure, and interruption**: Azure exit `0` with zero
  regular objects is an `empty` no-op and publishes no completion. Invalid
  config, preflight failure, nonzero batch exit, unsafe output, or any
  interruption before MB-010's commit point publishes none. Catchable paths
  attempt to remove their run stage; an uncatchable kill may leave it. Anything
  under `.staging` is never completion and every later run ignores it.
- **MB-012 — Independent later runs**: each later successful invocation uses a
  fresh stage and batch ID and creates a distinct completion directory. The
  collector performs no cross-run resume, checkpoint, deduplication, recovery,
  existing-final scan, per-Blob registry, or idempotency claim.

## CLI contract

- **MB-013 — Dedicated command**: `python3.14 aidata/cli.py product-blob`
  accepts no additional arguments and is separate from generic `collect`.
- **MB-014 — Success envelope**: exit `0` writes exactly one compact JSON line
  to stdout and nothing to stderr. It follows the Constitution envelope:

  ```json
  {"ok":true,"data":{"status":"completed","batchId":"<random-id>","objectCount":1},"requestId":"<random-id>"}
  ```

  A zero-object success uses `data.status = "empty"`, `objectCount = 0`, and
  omits `batchId`. The request and batch identifiers are fresh non-identity
  values. No endpoint, identity, Blob name, absolute path, or payload is
  returned.
- **MB-015 — Neutral failure**: every invalid argument, adapter import/load
  failure, adapter exception, malformed return, or collection failure exits
  `1`, leaves stdout empty, and writes exactly one compact Constitution error
  envelope to stderr with no additional keys:

  ```json
  {"ok":false,"error":{"code":"product_blob.collection_failed","message":"product blob collection failed","field":null,"requestId":"<random-id>"}}
  ```

  `requestId` is a fresh random non-identity UUID. The message, code, and field
  are fixed and uninterpolated; no exception, argument, selector, identity,
  child output, Blob name, or local path is exposed.

## Operator and T7 boundary

- **MB-016 — External bound**: the later authorized operator invocation is
  `gtimeout --signal=KILL 300s python3.14 aidata/cli.py product-blob`. GNU
  timeout is an operator boundary, not repository scheduling or a second
  product supervisor. The repository adds no timer, process-tree manager, or
  unattended wrapper.
- **MB-017 — Temporary private T7 query**: only after both the final VoxPocket
  producer and collector heads are merged, the Owner-authorized workflow 05
  lead/operator verifies that the existing live-operation authorization still
  applies and starts one manual collection/query through a Codex subagent in
  that workflow lead's local session. The Multica Team Lead neither owns that
  local subagent nor gains personal TestFlight/Azure authority from this plan.
  This is not collector behavior, product query/state-machine code, L2-L5
  state, credential authority, personal TestFlight authority, an unauthorized
  manual dispatch, or current authorization to execute a live operation.

  The subagent opens each selected gzip file exactly once, streams its NDJSON in
  source order, and validates the SDK 0.2.0 wire before counting: `name` is a
  string, `properties` is a string-to-string dictionary, and `timestamp` is a
  UTC timestamp. Immediately before execution, the workflow lead re-reads the
  exact final merged VoxPocket
  `specs/012-azure-blob-telemetry/contracts/product-telemetry-contract.md` and
  records its exact head. That final merged contract is the sole authority for
  event names, property/value constraints, and which records contribute to
  product-event counts; this collector contract deliberately copies no producer
  vocabulary. AIDash's `aidash-events.md` remains unchanged AIDash producer
  authority and does not govern this VoxPocket query. Input and records are
  limited by the selected TestFlight build from the producer path, authorized
  UTC window, completion batch ID, and exact relative Blob path.

  Each source line is located by `(batch-id, relative Blob path, NDJSON line
  number)`. Locator keys must be unique; identical content on different lines is
  counted separately and is never content-deduplicated. The query makes no
  cross-batch or cross-run incremental/idempotency claim.

  Evidence is aggregate-only: the product-event counts and property-validation
  results required by the exact final merged producer contract, total validated
  lines, duplicate locator keys exactly `0`, the
  selected TestFlight build/Blob/completion-relative L1 association, the UTC
  window, and query summary/output. Real build, Blob, and L1 path values remain
  only in the Owner's local workflow evidence file; public evidence uses
  sanitized labels/counts. It prints no payload, free text, install identity,
  endpoint, principal metadata, credential, token, SAS, key, or absolute local
  path, and no plan/template may prefill or fabricate live values. Generic
  `collect` is separately labelled and is not Blob-ingestion evidence.

## Hermetic acceptance

- **MB-018 — One executable fake Azure CLI**: tests place one scenario-driven
  executable fake `az` at the production lookup seam, then call the real CLI,
  adapter, tempfile, and filesystem publication path. The fake records only
  invocations it actually receives and writes neutral synthetic byte fixtures;
  it cannot prewrite product results, completion directories, or success
  traces.
- **MB-019 — Required observations**: hermetic evidence covers disabled and
  invalid config, exact preflight/batch argv and child environment, no private
  output retention, fixed CLI output, nonzero and interrupted batch with no
  pre-commit-point completion, zero-object no-op, byte-identical nonempty
  completion, fsync plus one directory publish plus parent fsync, ignored
  abandoned stages, untouched earlier completions, and a distinct later batch.
  Real-filesystem cases also observe current-UID ownership and private modes for
  roots/stage/completion; reject terminal symlink/non-directory, output symlink,
  special file, and lexical/resolved path escape; and delegate to the real
  atomic rename before inducing response loss/post-commit interruption, proving
  the full immutable completion remains. The fixture never creates that final.
  Assertions use invoked argv and real filesystem outcomes, not generic traces
  or test counts.

## Explicitly removed planned behavior

- **MB-020 — Superseded reader model**: the earlier Python
  `DefaultAzureCredential` plus hand-built LIST/GET reader, page/object cursors,
  per-object raw IDs, custom 8 MiB/64 MiB caps, collector-side NDJSON parsing,
  durable/product L2-L4 rows/query, registry activation, Ops runner, scheduler,
  and cross-run resume/deduplication are not part of this feature. MB-017's
  temporary read-only evidence query is the sole parsing exception and creates
  no repository entity, table, product state, or reusable query surface. No
  existing live-main product behavior or test is deleted or weakened by this
  planning decision.
