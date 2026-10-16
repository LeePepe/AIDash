# Quickstart: Manual Product Blob Batch Landing

The normative collector behavior is
[`contracts/manual-batch-collector.md`](contracts/manual-batch-collector.md). This
quickstart records delivery order and verification entry points only. It does not
duplicate or extend that contract. The merged producer, consent, and generic
`collect` behavior remain unchanged and are not evidence for this collector.

## Planning verification

From the repository root:

```bash
.specify/scripts/bash/check-prerequisites.sh --require-tasks --include-tasks
scripts/hooks/check-tasks-fresh
scripts/context/audit
git diff --check
```

These are static planning checks, not product test-suite invocations. Commit the
RepoInfra planning revision normally so the resolver-selected pre-commit gate
runs, and retain its receipt. The planning tree must contain no endpoint,
resource identifier, personal identity metadata, token, SAS, account key,
secret, credential-bearing URL, or absolute private path.

## Delivery order

1. Independently review and merge the exact RepoInfra planning revision.
2. Deliver T101 as one AidataFoundation commit. It owns the manual CLI,
   configuration seam, Azure CLI adapter, executable fake-`az` boundary, and
   matching parent/leaf routing.
3. After T101 is green, deliver T102 as one AidataL1L2 commit. It owns opaque
   staging and immutable completion-directory publication, real-filesystem
   acceptance, and matching parent/leaf routing.
4. Bind implementation review to the final head of that two-commit descendant
   chain. Hooks and required CI own suite execution; do not bypass them.
5. Treat T7 as a later, separately authorized post-merge operator milestone,
   not as an implementation task or a substitute for hermetic acceptance.

No AidataOps, registry, scheduler, activation, L2-L5 transformation, dependency,
or automatic source-execution task belongs to this graph. If retained production
cannot satisfy the reviewed contract, stop and return exact evidence to Team
Lead instead of widening either implementation task.

## Local manual configuration

Tracked defaults and examples keep both selectors empty:

```python
PRODUCT_BLOB_CONTAINER_URL = ""
PRODUCT_BLOB_PREFIX = ""
```

Only ignored `aidata/config_local.py` may contain the Owner-authorized, query-free
HTTPS container URL and the single allow-listed VoxPocket prefix. Do not add a
token, SAS, account key, tenant/client/principal selector, credential field, or
authentication switch. The product never runs `az login`; it uses the already
authenticated read-only AAD identity through `--auth-mode login`.

## Hermetic acceptance

Apply MB-018–MB-019 through the production CLI and adapter with one executable
fake `az` and real temporary filesystem state. The fake may record only commands
actually invoked and cannot manufacture the expected completion result.

Normal commits and pushes must produce the resolver-selected hook receipts for
their changed layer. Required CI owns the corresponding suites. Static context
audit, task freshness, shell syntax inspection, changed-file privacy scans, and
`git diff --check` may be run directly.

## Later manual operator and T7 evidence

After the reviewed implementation is merged and Team Lead separately authorizes
the live operation, the bounded collector invocation is exactly:

```bash
gtimeout --signal=KILL 300s python3.14 aidata/cli.py product-blob
```

The external GNU timeout is an operator boundary, not a scheduler or product
supervisor. A separately requested one-time
`python3.14 aidata/cli.py collect` remains generic producer evidence and must not
be presented as Blob ingestion evidence.

Real Blob names and the completion-directory association stay only in the
Owner's private workflow evidence file. T7 must associate the real TestFlight
build, the selected Blob, and the published completion batch, then run a query
explicitly limited to that batch and Blob to prove no duplicate counting within
that result. It must not claim cross-run incremental or idempotent behavior, and
no real endpoint, Blob name, resource identifier, credential, payload, or
absolute private path may enter the repository or issue.

## Rollback boundary

Before the atomic directory rename, failure, empty success, or interruption
produces no completion. An abandoned private stage is never a result. After the
rename, the whole immutable directory is complete even if the caller loses the
success response. Completed batches are preserved; deletion or migration is a
separate Owner decision.
