# Contract: Product Blob Reader Authorization and Configuration

## Tracked schema

`aidata/config.py` declares exactly one selector:

```python
PRODUCT_BLOB_CONTAINER_URL = ""
```

The tracked `aidata/config_local.example.py` keeps the selector empty. A real query-free HTTPS Azure Blob container URL may be set only in gitignored `aidata/config_local.py`.

There is no config field for a token, SAS, account key, tenant, client ID, client secret, username, object ID, stored policy, auth-mode switch, or fallback.

## Credential construction

The reader uses `DefaultAzureCredential` with Azure CLI as the only enabled credential leg. Environment, workload identity, managed identity, shared token cache, Visual Studio Code, Azure PowerShell, Azure Developer CLI, broker, interactive browser, and every later-added non-CLI leg are disabled explicitly. Interactive authentication is forbidden.

The credential requests only the Azure Storage data-plane scope. A token is held in memory only for the request lifecycle and is never persisted, logged, returned in an error, copied into raw data, or exposed to another source.

## Allowed operations

- List blobs in the configured container with `maxresults=100`, at most 10
  pages and 1,000 listed object references per `collect()` run.
- Read at most 1,000 listed objects per run, with a 30-second timeout for each
  list/read request.

No create, write, overwrite, append, metadata mutation, lease, delete, role operation, resource discovery, or container/account administration is permitted.

## Validation and degradation

Before credential or network construction, the adapter requires one query-free HTTPS container URL with no userinfo, fragment, or embedded credential. An empty or invalid value returns zero records.

Missing Azure CLI, an unsigned-in/expired local session, or configuration,
credential, or initial-token failure before the first list request degrades this
source to zero/no-op for the run with no state change. They do not start
interactive login, try another credential, or crash other sources. A later
list/read/auth/network failure leaves its incomplete object/page unadvanced but
preserves records and object checkpoints completed earlier in the run; the
collector may return that already accepted count.

## Collection bounds and checkpoint behavior

- One `collect()` has a 240-second monotonic wall budget, below the existing
  300-second outer source-runner timeout.
- Each object's compressed body is limited to 8,388,608 bytes; decompressed
  output is limited to 67,108,864 bytes. Both limits are enforced while
  streaming. `Content-Length` is only an early-rejection hint.
- A timed-out, failed, malformed, or oversized object emits no raw/clean record
  and receives no object checkpoint.
- Every object reference returned by a page is selected. An invalid path is
  rejected before GET, receives no rejection checkpoint, and blocks that page's
  marker just like a failed object. A continuation marker advances only after
  its page is listed completely and every listed object has reached successful
  or already-complete object state.
- Page/object/run-budget exhaustion after a complete page is a bounded pause:
  persist that completed page's next marker and resume on the next run.
  Exhaustion or failure within a page leaves the page marker unchanged.
  Completed object checkpoints remain valid, so retry skips them without
  losing failed or later objects.
- No partial decompression, partial NDJSON, token, endpoint, or principal data
  enters records, state, diagnostics, errors, or logs.

## Tests

- Empty and invalid selectors create no credential, network, raw record, or state update.
- A fake CLI credential is the only reachable credential leg.
- Spies prove every non-CLI leg is excluded and no fallback occurs after CLI failure.
- Requests are GET-only, confined to the validated container origin/path, and refuse redirects.
- Boundary fakes cover exactly 30-second request timeout, 240-second run
  budget, 100-result pages, 10 pages, 1,000 references/GETs, both byte limits,
  missing/lying `Content-Length`, and exhaustion before/within/after a page.
- Checkpoint assertions prove the exact page/object behavior above and prove a
  retry reuses completed-object checkpoints without skipping incomplete work.
- Setup-token failure proves zero/no state; mid-run token/network failure proves
  prior completed records/checkpoints survive while the current page marker and
  incomplete object remain unadvanced.
- Errors, records, and logs contain no token, real endpoint, or personal identity metadata.
