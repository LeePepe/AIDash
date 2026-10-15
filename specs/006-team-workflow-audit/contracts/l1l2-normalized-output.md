# Contract: Team Audit AidataL1L2 Normalized Output

This contract is the only data seam from T026 to T003. T026 produces it in
`clean_path("team_audit_snapshot")`; T003 reads it without inspecting raw
shards, adapter-private models, or the persisted identity cache.

## Source-clean table

The clean database contains exactly one table named `team_audit_record` with
these columns and key:

| Column | SQLite type | Nullability / meaning |
|---|---|---|
| `record_type` | TEXT | NOT NULL; one locked value from the record-type table below |
| `snapshot_id` | TEXT | NOT NULL; accepted snapshot identity |
| `snapshot_sha256` | TEXT | NOT NULL; 64 lowercase hex hash of the accepted snapshot bytes |
| `parent_identity` | TEXT | NOT NULL; immediate logical parent, or `snapshot_id` for direct children |
| `stable_identity` | TEXT | NOT NULL; record identity defined below, never a display label |
| `entity_sha256` | TEXT | NOT NULL; snapshot/sidecar exact-byte hash or canonical child-record hash; distinct from an artifact's source `contentSHA256` |
| `captured_at` | TEXT | NOT NULL; accepted snapshot UTC timestamp |
| `source` | TEXT | NOT NULL; portable value `team_audit_snapshot`, never a local path |
| `ordinal` | INTEGER | NOT NULL and non-negative; source order, or deterministic sorted order for maps |
| `sidecar_id` | TEXT | Nullable only when the accepted snapshot has the explicit missing-sidecar limitation |
| `sidecar_sha256` | TEXT | Nullable exactly when `sidecar_id` is null; otherwise the accepted exact sidecar-byte hash |
| `record_json` | TEXT | NOT NULL; canonical JSON for exactly the decoded record type, with no wrapper aliases, local paths, or rejected body |

Primary key:

```text
(record_type, snapshot_id, parent_identity, stable_identity)
```

`entity_sha256` for decoded child records is SHA-256 over UTF-8
`json.dumps(value, sort_keys=True, separators=(",", ":"),
ensure_ascii=False)`. Snapshot and sidecar rows instead retain their exact
captured file-byte hashes. Artifact rows are the one child exception:
`entity_sha256` hashes canonical `ArtifactManifestEntryWire` bytes before
enrichment, so a sidecar-wide hash or grill-only change cannot create a false
artifact collision. `record_json` still contains the enriched artifact model
and uses canonical JSON encoding for deterministic T003 consumption.

Every row from a bundle repeats the accepted `snapshot_id` and
`snapshot_sha256`. When a valid sidecar exists, every row also repeats its
accepted `sidecar_id` and `sidecar_sha256`; artifact and grill rows require
both. A missing sidecar produces only snapshot-owned rows with both sidecar
columns null and the required unpublishable limitation in the snapshot record.

## Locked record types and grains

| `record_type` | `parent_identity` | `stable_identity` | Required `record_json` content | T003 target |
|---|---|---|---|---|
| `snapshot` | snapshot ID | snapshot ID | scope, mode, evidence coverage, limitations | `fact_team_audit_snapshot` |
| `instructionVersion` | snapshot ID | instruction source ID | source ID, UTC update time, exact instruction SHA-256 | `fact_team_audit_instruction_version` |
| `cohort` | snapshot ID | cohort ID | cohort ID and source-ordered unique case IDs; baseline only | `fact_team_audit_cohort` |
| `cursor` | snapshot ID | cursor ID | source ID, cursor ID, UTC timestamp, non-negative overlap hours; incremental only | `fact_team_audit_cursor` |
| `coreAxisSummary` | snapshot ID | locked core-axis value | axis-specific verdict and reconciled total/positive/negative/insufficient counts | `fact_team_audit_axis_summary` |
| `taskEffectivenessSummary` | snapshot ID | `taskEffectiveness` | evaluated total plus effective/ineffective/regressed/pending/insufficient counts | `fact_team_audit_task_effectiveness` |
| `case` | snapshot ID | case ID | case fields, ordered event/attempt identity lists, limitations | `fact_team_audit_case` |
| `event` | case ID | event ID | case ID, source, subject ID, actor role, kind, UTC timestamp, revision SHA, evidence reference | `fact_team_audit_event` |
| `attempt` | case ID | attempt ID | case ID, role/cycle identities, actor role, trigger cause, outcome, evidence references | `fact_team_audit_attempt` |
| `finding` | snapshot ID | finding fingerprint | explicit subject ID/responsibility layer, axis, priority, verdict, state, evidence/case/event references, remediation owner | `fact_team_audit_finding` |
| `individualMetric` | snapshot ID | metric ID | definition, numerator, denominator, observation window, limitation | `fact_team_audit_individual_metric` |
| `feedbackLineage` | snapshot ID | lineage ID | problem/origin/delivery/PR/merge/release/build/availability/effectiveness fields | `fact_team_audit_feedback_lineage` |
| `lineageObservation` | lineage ID | observation event ID | lineage ID and observation event ID | `bridge_team_audit_lineage_observation` |
| `lineageRelatedFeedback` | lineage ID | related feedback issue ID | lineage ID and related feedback issue ID | `bridge_team_audit_lineage_related_feedback` |
| `agentRepeatMetric` | snapshot ID | actor role | common repeat totals and tagged role-specific shape | `fact_team_audit_agent_repeat_metric` |
| `repeatCycleKind` | actor role | cycle-kind key | actor role, key, non-negative count | `fact_team_audit_repeat_cycle_kind` |
| `repeatTriggerCause` | actor role | locked trigger-cause value | actor role, cause, non-negative count | `fact_team_audit_repeat_trigger_cause` |
| `repeatRoleValue` | actor role | allowed role-specific key | actor role, key, non-negative value | `fact_team_audit_repeat_role_value` |
| `repeatSubject` | actor role | subject ID | actor role and subject ID | `bridge_team_audit_repeat_subject` |
| `repeatEvent` | actor role | event ID | actor role and event ID | `bridge_team_audit_repeat_event` |
| `importCollisionObservation` | accepted snapshot ID | observation ID | observed-at, portable source, entity kind/stable identity, accepted/rejected hashes, locked disposition, limitation, accepted parent ID/hash; no rejected body | `fact_team_audit_import_collision_observation` |
| `artifactSidecar` | snapshot ID | sidecar ID | schema version, snapshot ID, sidecar ID, exact sidecar-byte hash | `fact_team_audit_artifact_sidecar` |
| `artifact` | sidecar ID | artifact ID | enriched `ArtifactManifestEntry`: all raw wire fields plus validated sidecar binding/hash, canonical wire-only `encodedByteCount`, and URL value/status | `fact_team_audit_artifact` |
| `grillLink` | sidecar ID | `grillMe` or `grillWithDocs` | sidecar binding plus original untrusted URL string and `actionableHTTPS` or `nonActionable` status | `fact_team_audit_grill_link` |

`coreAxisSummary` permits exactly the three core axes.
`taskEffectivenessSummary` is never coerced into a core verdict. Unknown
`record_type` values are contract violations; T003 must not invent a warehouse
mapping for them.

## URL distinction

Mandatory generic-workflow, team-relationship, and P0/P1-chain artifact rows
exist only after the decoder accepts a present HTTPS URL with a non-empty host
and validates their hashes/references. Invalid mandatory values reject the
bundle before raw or clean output.

Artifact entry counting uses only canonical `ArtifactManifestEntryWire` JSON
as specified in `data-model.md`; it excludes the sidecar envelope and derived
sidecar ID/hash, byte count, and URL status. Every nullable wire key is present
with JSON null when absent, and duplicate JSON object members reject before
canonicalization. Mandatory 65,536-byte entries are accepted; 65,537-byte
entries reject before raw output. This is a pre-ingest defense margin, not a
fit guarantee; L5 still measures the complete serialized card against 262,144
bytes. The normalized row stores the enriched model and exact computed count.

Optional artifact and grill URL strings do not reject an otherwise valid
bundle solely for URL safety. The decoder preserves the original untrusted
string and emits status `actionableHTTPS` only for HTTPS plus non-empty host;
otherwise it emits `nonActionable`. An absent optional artifact URL is stored
as JSON null with status `absent`; an absent grill field emits no `grillLink`
row. T003 preserves present values/status unchanged. Downstream URLPolicy still
revalidates before rendering a link.

## Producer and consumer checks

- T026 rebuilds `team_audit_record` from accepted append-only raw records and
  body-free observations. Replay produces one row per primary key; a different
  hash never updates the accepted row.
- `normalize()` returns the number of accepted `snapshot` rows, not the total
  number of tagged rows written.
- T026 writes no row for rejected snapshot, sidecar, or child content and no
  local filesystem provenance.
- Artifact `entity_sha256` and `encodedByteCount` both derive from the same
  canonical raw wire bytes; enriched sidecar hash/status fields never affect
  child collision identity.
- T003 reads only this table, verifies locked `record_type`, hash formats,
  parent keys, sidecar nullability, and canonical `record_json`, then maps each
  row to the named L3 grain without reinterpreting optional URL status.
- T003 preserves accepted snapshot/sidecar linkage on every target row and
  keys collision observations by `(parentSnapshotID, observationID)`.
- An `importCollisionObservation` row's `entity_sha256` is the canonical hash
  of its complete body-free observation JSON. Its snapshot columns and parent
  identity/hash always name the accepted snapshot; sidecar columns, when the
  colliding entity is a sidecar, name the accepted sidecar and never rejected
  bytes.
- Neutral contract tests assert the complete record-type set, primary-key
  idempotency, required columns, T003 mapping coverage, missing-sidecar
  nullability, and optional-versus-mandatory URL behavior.
