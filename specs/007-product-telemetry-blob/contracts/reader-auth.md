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

- List blobs in the configured container with bounded pagination.
- Read one listed object.

No create, write, overwrite, append, metadata mutation, lease, delete, role operation, resource discovery, or container/account administration is permitted.

## Validation and degradation

Before credential or network construction, the adapter requires one query-free HTTPS container URL with no userinfo, fragment, or embedded credential. An empty or invalid value returns zero records.

Missing Azure CLI, an unsigned-in/expired local session, token failure, authorization failure, and network failure all degrade this source to zero/no-op for the affected collection run. They do not start interactive login, try another credential, change state, or crash other sources.

## Tests

- Empty and invalid selectors create no credential, network, raw record, or state update.
- A fake CLI credential is the only reachable credential leg.
- Spies prove every non-CLI leg is excluded and no fallback occurs after CLI failure.
- Requests are GET-only, confined to the validated container origin/path, and refuse redirects.
- Errors, records, and logs contain no token, real endpoint, or personal identity metadata.
