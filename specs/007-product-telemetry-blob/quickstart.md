# Quickstart: Product Telemetry Blob Pipeline

## Planning verification

From the repository root:

```bash
.specify/scripts/bash/check-prerequisites.sh --require-tasks --include-tasks
scripts/hooks/check-tasks-fresh
scripts/context/audit
git diff --check
```

These are static planning/audit commands, not test-suite invocations. The normal
planning commit invokes the resolver-selected RepoInfra pre-commit gate; retain
and inspect its receipt. Then verify the changed planning tree contains no real
endpoint, personal identity metadata, token, SAS, account key, secret, or
credential-bearing URL. Planning never requires Azure sign-in or live values.

## Implementation order

1. Confirm the exact reviewed planning revision.
2. Resolve REL-001 before editing LokiKit dependency wiring.
3. Confirm the constitution 1.14.0 amendment and migration note are merged before any T001–T010 implementation.
4. Deliver DATA-FOUND and its exact Azure Identity lock plus current-effective `SCHEDULED_SOURCES`; do not activate `product_blob`. Add RepoInfra CI install before DATA-L12 imports Azure Identity.
5. Assemble AID-XCODE, AID-RELEASE, and AID-APP as one producer candidate tree; do not publish a partial producer slice.
6. Deliver DATA-L12 → DATA-L3 → DATA-L4 with the source inactive; DATA-OPS may canonicalize the runner after DATA-FOUND without activating it.
7. Only after adapter/schema/query/runner readiness, deliver DATA-ACTIVATE to add `product_blob` atomically to all three registries.
8. Commit and push normally so hooks select each changed layer; inspect receipts and required CI rather than invoking test suites directly. Run only static context audit after routing changes.
9. Freeze and independently review each implementation candidate at one exact revision before publication.
10. Only after merged slices and OA-003/OA-004 authorization, Team Lead performs E2E-05.

## Local reader configuration

The tracked default and example stay empty:

```python
PRODUCT_BLOB_CONTAINER_URL = ""
```

An authorized operator may set the real query-free HTTPS container URL only in ignored `aidata/config_local.py`. Do not add a token, SAS, account key, tenant/client/principal field, or auth-mode switch. The repository never performs `az login`; unavailable Azure CLI identity is a valid no-op result.

## Hook/CI-owned acceptance evidence

- A normal commit must produce the pre-commit receipt for every
  resolver-selected changed leaf; a normal push must produce the corresponding
  pre-push receipt. Do not bypass hooks.
- Inspect the receipts to confirm the intended leaf and declared gates. Do not
  invoke pytest, Swift tests, context-run test modes, or Xcode test schemes
  directly.
- The AIDashApp local declaration must remain hostless
  (`AIDashAppLogicTests`). Never run host-based `AIDashAppTests` locally.
- Required CI owns macOS/iOS app/workspace builds, hostless logic tests, full
  aidata pytest/Ruff, and structural workflow tests at the pushed revision.
- `scripts/context/audit`, task freshness, clean generated-project diff,
  dependency/license review, shell syntax inspection, and changed-file privacy
  scans are static evidence and may be run directly.

## Safe synthetic verification

- Use neutral fake URLs and fake token providers in hermetic tests.
- Exercise raw and shell-escaped sentinel strings through the Release injection seam; never use a real secret.
- Refuse redirects and assert requests are GET-only for the reader.
- Use temporary raw/clean/warehouse/state paths; never point tests at the operator's real aidata state.
- Use generated project output only for diff evidence; do not track it.

## Rollback

Producer: persist consent off, close admission, disable/cancel delivery without
starting or continuing pending upload, await quiescence, and verify ambiguous
in-flight/pending files and identity epochs remain before removing release and
dependency wiring. Reader: stop scheduled registration and code paths without
deleting accepted append-only raw or warehouse evidence. Any requested
deletion/migration is a separate decision.
