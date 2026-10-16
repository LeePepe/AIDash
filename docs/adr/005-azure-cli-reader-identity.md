# ADR-005: Use Azure CLI-Only DefaultAzureCredential for Product Blob Reads

## Status

Accepted by Owner decision `aad-owner-local` for this planning scope.

## Context

The `aidata` product Blob source needs one reader that can list and read the reviewed telemetry container. The prior repository baseline is stdlib-only and has no Python dependency manifest. The Owner selected an existing local Azure AD identity, with local sign-in/session lifecycle managed outside this repository, and explicitly prohibited SAS, stored secrets, dual-mode authentication, and activation of the existing inactive read policy.

The public repository must not carry the real endpoint or personal principal/operator metadata. Missing local configuration or identity must degrade to no-op.

## Decision

- Use Python `azure-identity`'s `DefaultAzureCredential`, configured so Azure CLI is its only enabled leg.
- Explicitly exclude environment, workload identity, managed identity, shared token cache, Visual Studio Code, Azure PowerShell, Azure Developer CLI, broker, interactive browser, and every other non-CLI leg.
- Never initiate interactive authentication. An unavailable/expired CLI session returns zero for this source with no checkpoint advance.
- Request only the Azure Storage data-plane scope and use the in-memory bearer token solely for GET-based container list and object read requests.
- Keep Blob HTTP/list/gzip/NDJSON handling in stdlib code. Do not add the Azure Storage SDK.
- Expose only `PRODUCT_BLOB_CONTAINER_URL`, empty in tracked configuration/examples. The real query-free HTTPS container selector may exist only in ignored `aidata/config_local.py`.
- Add no token, SAS, account-key, tenant, client, username, object-ID, stored-policy, or auth-mode config field.
- Reject embedded query/userinfo/fragment, cross-origin/path escape, redirects, non-GET requests, and any authentication fallback.
- Enforce the deterministic request/run/page/object/byte limits and checkpoint
  behavior in `specs/007-product-telemetry-blob/contracts/reader-auth.md`; a
  limit hit is a bounded pause/failure, never authority to broaden access.
- Persist no token, real endpoint, or personal identity in raw data, normalized data, state, diagnostics, errors, fixtures, or logs.

## Dependency and CI cost

- `azure-identity` and its transitive runtime set become the first non-stdlib aidata dependencies.
- Implementation must create a routed dependency manifest/lock with exact audited versions; ranges and ambient machine packages are forbidden.
- CI must install from that exact lock before aidata pytest/Ruff. The install change belongs to RepoInfra, while the manifest/config belongs to AidataFoundation.
- Dependency review must cover licenses, supported Python version, vulnerability signal, import/startup cost, and the exact `DefaultAzureCredential` exclusion surface available in the pinned version.

## Operational and security cost

- The reader depends on the operator's existing Azure CLI sign-in and its token-cache lifecycle. This repository neither signs in nor signs out.
- Revocation happens outside the repository by removing the reader role and invalidating the local session.
- A compromised local signed-in session retains whatever external role it has; the repository limits its own calls to the configured container and read/list operations but cannot redefine external RBAC.
- Network access is restricted to the validated Blob origin/container. No resource-management API is used.

## Alternatives considered

1. **Dedicated service/workload principal** — superseded by the Owner choice for this version.
2. **Read/list SAS in ignored config** — rejected: explicitly unauthorized and would create a second auth mode/secret lifecycle.
3. **Existing inactive stored policy** — rejected: the Owner kept it inactive.
4. **Raw Azure CLI token subprocess** — rejected: changes the chosen credential mechanism and creates avoidable output/parsing leakage.
5. **Unrestricted DefaultAzureCredential chain** — rejected: it can silently choose a different principal/mechanism.
6. **Azure Storage SDK** — rejected: unnecessary dependency surface for bounded list/read; stdlib transport remains adequate.

## Consequences

- OA-002 is closed as a single explicit auth contract; DATA-FOUND no longer waits for an identity-mode decision.
- A fresh clone and CI remain no-op-safe with an empty selector and no local sign-in.
- The Python dependency manifest, routing metadata, and CI installation must land before the adapter can pass deterministically.
- Any future service principal, workload identity, SAS, stored policy, interactive login, write/delete operation, or Azure Storage SDK use requires a superseding Owner decision and ADR.
