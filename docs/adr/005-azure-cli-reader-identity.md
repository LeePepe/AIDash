# ADR-005: Superseded Azure CLI-Only Credential Plan

## Status

Superseded by
`specs/007-product-telemetry-blob/contracts/manual-batch-collector.md`.

## Superseding decision

The planned Python `azure-identity` credential and repository-owned LIST/GET
reader never shipped. The selected collector instead invokes the installed
Azure CLI directly for one manual
`az storage blob download-batch --auth-mode login --overwrite false`, using the
Owner's existing externally administered read-only Azure AD identity. The
repository parses no token, adds no Azure SDK dependency, stores no credential,
and implements no pagination, per-object checkpoint, custom cap, or fallback.

The sole normative reader, privacy, staging, completion, CLI, operator, and
evidence rules now live in the manual-batch collector contract. This file is a
historical pointer and MUST NOT be used as competing implementation authority.

## Historical rationale

The superseded plan attempted to make the chosen local identity mechanically
exclusive by constructing `DefaultAzureCredential` with only its Azure CLI leg
enabled and by implementing bounded Blob LIST/GET in stdlib Python. Direct CLI
batch collection is materially smaller for the selected human-operated scope:
it removes a Python dependency, token handling, pagination, per-object state,
and repository-owned retry machinery while retaining external read-only RBAC
and public-repository privacy.
