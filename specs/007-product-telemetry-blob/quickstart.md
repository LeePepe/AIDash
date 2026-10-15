# Quickstart: Product Telemetry Blob Pipeline

## Planning verification

From the repository root:

```bash
.specify/scripts/bash/check-prerequisites.sh --require-tasks --include-tasks
scripts/hooks/check-tasks-fresh
scripts/context/run RepoInfra --mode local
scripts/context/audit
```

Then verify the changed planning tree contains no real endpoint, personal identity metadata, token, SAS, account key, secret, or credential-bearing URL. Planning never requires Azure sign-in or live values.

## Implementation order

1. Confirm the exact reviewed planning revision.
2. Resolve REL-001 before editing LokiKit dependency wiring.
3. Deliver DATA-FOUND and its exact Azure Identity lock; then add RepoInfra CI install before DATA-L12 imports it.
4. Assemble AID-XCODE, AID-RELEASE, and AID-APP as one producer candidate tree; do not publish a partial producer slice.
5. Run DATA-L12 → DATA-L3 → DATA-L4; DATA-OPS may proceed after DATA-FOUND.
6. Run each changed layer's resolver gate plus context audit after routing changes.
7. Freeze and independently review each implementation candidate at one exact revision before publication.
8. Only after merged slices and OA-003/OA-004 authorization, Team Lead performs E2E-05.

## Local reader configuration

The tracked default and example stay empty:

```python
PRODUCT_BLOB_CONTAINER_URL = ""
```

An authorized operator may set the real query-free HTTPS container URL only in ignored `aidata/config_local.py`. Do not add a token, SAS, account key, tenant/client/principal field, or auth-mode switch. The repository never performs `az login`; unavailable Azure CLI identity is a valid no-op result.

## Layer gates

```bash
scripts/context/run XcodeWorkspace --mode ci
scripts/context/run AIDashApp --mode local
scripts/context/run AIDashApp --mode ci
scripts/context/run AidataFoundation --mode local
scripts/context/run AidataL1L2 --mode local
scripts/context/run AidataL3 --mode local
scripts/context/run AidataL4 --mode local
scripts/context/run AidataOps --mode local
scripts/context/run RepoInfra --mode local
scripts/context/audit
```

The AIDashApp local gate must remain hostless (`AIDashAppLogicTests`). Never run host-based `AIDashAppTests` locally. Required CI supplies macOS/iOS builds and full aidata pytest/Ruff.

## Safe synthetic verification

- Use neutral fake URLs and fake token providers in hermetic tests.
- Exercise raw and shell-escaped sentinel strings through the Release injection seam; never use a real secret.
- Refuse redirects and assert requests are GET-only for the reader.
- Use temporary raw/clean/warehouse/state paths; never point tests at the operator's real aidata state.
- Use generated project output only for diff evidence; do not track it.

## Rollback

Producer: disable emission, await active flush exit, verify pending files/identity epochs remain, then remove release and dependency wiring. Reader: stop scheduled registration and code paths without deleting accepted append-only raw or warehouse evidence. Any requested deletion/migration is a separate decision.
