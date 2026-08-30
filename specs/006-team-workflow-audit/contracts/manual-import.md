# Contract: Manual Team Audit Import

## Authority boundary

This interface imports an audit that has already been run. It does not locate,
invoke, schedule, configure, retry, or remediate Team Workflow Audit.

`team_audit_snapshot` belongs to `MANUAL_SOURCES`, not the default scheduled
`SOURCES` set. Normal `collect`/`normalize` without `--source` never touches it.
No file under `aidata/scripts/` or any cron configuration is changed.

## Operator flow

The operator configures a portable, local import directory through the
git-ignored local configuration and explicitly runs:

```bash
./aidata/cli.py collect --source team_audit_snapshot
./aidata/cli.py normalize --source team_audit_snapshot
./aidata/cli.py merge
```

An absent or empty import directory returns zero records and keeps the rest of
the pipeline healthy.

## Bundle layout

Each immutable bundle is a directory containing:

```text
<stable-snapshot-id>/
├── snapshot.json
└── artifacts.json       # required for publication; typed hosted-artifact sidecar
```

`snapshot.json` follows the upstream Team Workflow Audit evidence schema.
`artifacts.json` is an AIDash portability extension with this typed envelope:

```json
{
  "schemaVersion": 1,
  "snapshotID": "audit-snapshot-001",
  "sidecarID": "audit-snapshot-001:artifact-sidecar:v1",
  "artifacts": [],
  "grillMeURL": "https://example.com/grill-me",
  "grillWithDocsURL": "https://example.com/grill-with-docs"
}
```

`artifacts` contains `ArtifactManifestEntry[]` as defined in `data-model.md`;
both grill fields are optional untrusted strings. The sidecar never changes
the snapshot body or hash. A missing sidecar may be ingested as an import
limitation, but the snapshot is not publishable until its mandatory generic,
team/repository, and P0/P1 chain entries are present and valid.

The importer computes normalized `ArtifactSidecar.contentSHA256` from the exact
immutable `artifacts.json` bytes; the file does not self-declare its hash. The stable
`sidecarID` plus computed hash is retained on normalized artifact/grill rows,
warehouse facts, L4 bundles, payload provenance, and collision observations.

## Contract-first internal seams

The AidataL1L2 implementation has four ordered interfaces behind the existing
public `collect()`/`normalize()` adapter surface:

1. `decode_team_audit_bundle(snapshot_bytes, sidecar_bytes)` is the sole strict
   decoder. It validates every documented nested model and reference, computes
   both hashes from those buffers, and returns an immutable decoded bundle or
   structured rejection without performing I/O.
2. `read_bundle(root, bundle_dir)` is the filesystem adapter. It resolves and
   contains an immediate bundle directory, reads each regular contract file at
   most once, and returns those exact buffers or a typed skip/rejection.
3. `TeamAuditIdentityIndex.open(index_path, raw_history)` reconstructs or opens
   a derived SQLite identity cache at an injected git-ignored path. T026 uses
   `raw_source_dir("team_audit_snapshot") / ".identity-index.sqlite"`;
   hermetic tests use `tmp_path`. `classify(decoded_bundle, observed_at)`
   returns an import plan; `commit(import_plan)` atomically updates the cache
   only after the planned raw append succeeds. Classification is independent
   for snapshot, child, and sidecar identities. Raw history—not the cache—is
   the acceptance authority.
4. `team_audit_snapshot.collect()` and `normalize()` wire these interfaces to
   `rawio.write_raw` and `cleanio.write_clean`. No schema, filesystem, or
   identity fallback remains in this final wiring module.

The complete observable proof is locked in
`contracts/t002-acceptance-matrix.md`.

## Collection and normalization

1. Enumerate only immediate configured bundle directories; never modify or
   delete them, accept loose JSON/JSONL/NDJSON, or recurse into unrelated paths.
2. Reject symlink escapes and paths outside the configured import root; degrade
   root/iteration/read races and permission failures to zero/skip.
3. Read `snapshot.json` and `artifacts.json` once each. Decode and hash the same
   captured buffers so replacement cannot split accepted content from its hash.
4. Validate required stable identities, exact lowercase SHA-256 values, UTC
   timestamps, typed mode-specific cohort/cases or cursors, evidence coverage,
   axis-specific verdict reconciliation, Task Effectiveness separation,
   ordered case/event/attempt/role/cycle references, five-role tagged repeat
   metrics, locked release/collision/finding enums, and evidence references.
5. Classify snapshot, every child entity, and sidecar identity against the
   restart-safe persisted index before any raw append. Treat same identity +
   same hash as replay. Treat same identity + different
   hash as an immutable collision: retain the accepted fact, append an
   independently keyed `ImportCollisionObservation`, add a limitation, and
   emit no overwrite or rejected content.
6. Apply the existing redaction policy only to accepted records and body-free
   observations, then append raw records. Call `commit(import_plan)` only when
   the append writes the expected count; on interruption or short/failed write,
   the next open rebuilds from raw history. Cache rows not supported by raw
   history are discarded.
7. Normalize accepted/body-free records into source-clean facts while
   preserving hashes, provenance, and `(parentSnapshotID, observationID)`.
8. Validate that every mandatory generic workflow, team/repository
   relationship, and P0/P1 finding-event-chain sidecar entry satisfies the
   bounded direct-link contract. A malformed or individually oversized
   mandatory entry rejects publication instead of being truncated.

## Prohibited behavior

- Import code must not shell out to an audit, Multica, an agent CLI, or a
  remediation workflow.
- Import code must not contact CloudKit or mutate issues/runs/source repos.
- Import code must not ingest full daemon/session logs or unredacted personal
  content.
- Local paths are provenance for the importer only and must never appear in a
  card payload or actionable URL.

## Contract tests

- Explicit `--source` imports one valid baseline and one valid incremental
  fixture.
- Default collect/normalize source selection excludes the manual source.
- Same bundle replay is idempotent; identity/hash conflict never overwrites.
- Repeating the same collision observation ID merges once while distinct
  import attempts remain separate append-only observations; every observation
  carries the accepted parent snapshot ID/hash.
- A 24-hour overlap replay deduplicates stable source event IDs.
- Sidecar fixtures cover absent/present grill URLs, unsafe optional URLs
  preserved as non-actionable data, and every mandatory P0/P1 chain entry.
- Exact sidecar bytes produce a stable sidecar ID/hash through normalize;
  same ID/different bytes produces a parented collision observation.
- Finding fixtures preserve explicit `subject_id` and `responsibility_layer`.
- Timeline fixtures preserve ordered embedded events/attempts and reject
  missing, duplicate, reordered, or foreign case/event/attempt references.
- Repeat fixtures cover all five role-specific variants, tag/role mismatch,
  negative counts, and inconsistent attempt/repeat/cycle/cause totals.
- Missing/unsafe mandatory URLs reject publication input; unsafe optional
  artifact/grill URLs remain non-actionable data.
- Missing configuration returns zero without raising.
- Test spies observe no subprocess, network, audit, dispatch, or mutation call.
- Atomic read tests prove parsing and hashing use one captured buffer per file,
  including replacement/removal/permission races.
- Restart tests cover missing/corrupt/stale index, raw-ahead/index-behind crash
  recovery, unsupported index-ahead state, and independently keyed snapshot,
  child, and sidecar conflicts without rejected bodies.
- Every case in `contracts/t002-acceptance-matrix.md` names its implementation
  and proof task and passes through the normal AidataL1L2 hook gate.
