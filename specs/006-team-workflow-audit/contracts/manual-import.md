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
└── artifacts.json       # optional hosted-artifact sidecar
```

`snapshot.json` follows the upstream Team Workflow Audit evidence schema.
`artifacts.json` is an AIDash portability extension containing
`ArtifactManifestEntry[]` as defined in `data-model.md`. It never changes the
snapshot body or hash.

## Collection and normalization

1. Read only configured bundle files; never modify or delete them.
2. Reject symlink escapes and paths outside the configured import root.
3. Apply the existing redaction policy before writing append-only raw records.
4. Compute the snapshot and sidecar SHA-256 values.
5. Validate required stable identities, UTC timestamps, mode-specific
   cohort/cursors, core-axis reconciliation, Task Effectiveness separation,
   finding enums, and evidence references.
6. Normalize into source-clean facts while preserving hashes and provenance.
7. Treat same identity + same hash as replay. Treat same identity + different
   hash as an immutable collision: retain the accepted fact, add a limitation,
   and emit no overwrite.

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
- A 24-hour overlap replay deduplicates stable source event IDs.
- Missing configuration returns zero without raising.
- Test spies observe no subprocess, network, audit, dispatch, or mutation call.
