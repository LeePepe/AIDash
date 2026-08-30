# Contract: T002 AidataL1L2 Acceptance Matrix

This contract replaces the former monolithic T002 proof with a serial,
contract-first graph. It covers only the manual Team Audit source inside the
AidataL1L2 resolver leaf. T001 owns CLI/config registration; T003 and later
tasks consume the final normalized output.

## Locked module interfaces

1. `decode_team_audit_bundle(snapshot_bytes, sidecar_bytes)` in
   `aidata/adapters/team_audit_contract.py` is the single schema decoder. It
   returns one immutable decoded bundle or structured rejection and performs
   no I/O.
2. `read_bundle(root, bundle_dir)` in
   `aidata/adapters/team_audit_bundle.py` returns the exact bytes read once
   from a contained immediate bundle directory, or a typed skip/rejection.
3. `TeamAuditIdentityIndex.open(index_path, raw_history)`,
   `classify(decoded_bundle, observed_at)`, and `commit(import_plan)` in
   `aidata/adapters/team_audit_index.py` expose the restart-safe identity
   decision seam. T026 injects
   `raw_source_dir("team_audit_snapshot") / ".identity-index.sqlite"` in
   production; tests inject `tmp_path`. The SQLite index is a derived cache;
   append-only raw history is authoritative and can rebuild it. T026 calls
   `commit` only after the planned raw append writes its expected count.
4. `collect() -> int` and `normalize() -> int` remain the only public adapter
   entry points. `team_audit_snapshot.py` wires the three modules only after
   their contracts and fixtures pass.

No second validator, fallback key alias, alternate JSON/JSONL input, or
in-memory-only replay map may exist on the active collector path.

## Matrix

| ID | Owner | Input / disturbance | Required observable result |
|---|---|---|---|
| D01 | T022/T025 | Neutral valid baseline bundle | Decodes one immutable model with cohort present, cursors absent, all stable identities and hashes preserved. |
| D02 | T022/T025 | Neutral valid incremental bundle | Decodes with cohort absent, non-empty per-source cursors, timestamps/stable IDs/overlap hours preserved. |
| D03 | T022/T025 | Naive or non-zero-offset timestamp | Structured rejection; only UTC `Z`/`+00:00` values are accepted. |
| D04 | T022/T025 | Missing/duplicate/unknown core axis or unreconciled counts | Structured rejection; exactly Conformance, Fitness, and Outcome reconcile independently. |
| D05 | T022/T025 | Task Effectiveness encoded as a core axis or unreconciled effectiveness counts | Structured rejection; the separate effectiveness model is preserved only in its own field. |
| D06 | T022/T025 | Findings across all six states and four priorities | Exact locked enums plus explicit fingerprint, subject ID, responsibility layer, evidence, cases, and remediation owner survive. |
| D07 | T022/T025 | Case/event/attempt graph | Stable references, UTC order, roles, cycle/cause/outcome, revision SHA, and evidence refs validate and survive without raw bodies. |
| D08 | T022/T025 | Complete feedback lineage in every effectiveness/release state | Every problem/origin/delivery/PR/merge/release/build/observation/related-feedback identity survives; invalid references reject. |
| D09 | T022/T025 | Five actor-role repeat records | Common, cycle, cause, role-specific, subject, and event fields survive; missing role, duplicate role, or tag/role mismatch rejects. |
| D10 | T022/T025 | Valid sidecar bytes | Schema version 1, matching snapshot ID, stable sidecar ID, typed artifacts, optional grill strings, and exact byte SHA-256 survive. |
| D11 | T022/T025 | Missing generic/team relationship or P0/P1 chain, unsafe mandatory URL, bad hash, bad parent, or oversized mandatory entry | Structured rejection before raw append. |
| D12 | T022/T025 | Unsafe optional artifact/grill URL or absent sidecar | Optional URL remains explicitly non-actionable data; absent sidecar yields an unpublishable limitation rather than fabricated provenance. |
| D13 | T022/T025 | Unknown/future field or enum at any typed level | Structured rejection; no silent drop, coercion, or generic payload preservation. |
| D14 | T022/T025 | `payload`, `body`, `message`, `note`, daemon/session/raw-log field at any typed level | Structured privacy rejection before storage; rejected content is absent from every returned record/observation. |
| D15 | T022/T025 | Invalid UTF-8, malformed JSON, non-object root, alias/snake-case key, non-contract filename content | Structured rejection; documented camel-case contract keys are the only accepted wire shape. |
| R01 | T023/T025 | Configured root with immediate `<snapshotID>/snapshot.json` plus `artifacts.json` | Returns one portable bundle identity and the exact two byte buffers; no local absolute path escapes the reader. |
| R02 | T023/T025 | Nested directory, loose JSON, JSONL/NDJSON, extra JSON-like sibling, non-regular file | Typed skip/rejection; none reaches the decoder. |
| R03 | T023/T025 | Root/bundle/file symlink or resolved path outside root | Typed skip/rejection with zero external read. |
| R04 | T023/T025 | File changes after its single read | Decoder and hash consume the same captured buffer; the reader never rereads for hashing. |
| R05 | T023/T025 | Root or bundle removed/unreadable during resolve, iteration, or read | Graceful zero/skip on `OSError`; no exception escapes collection. |
| R06 | T023/T025 | Missing `artifacts.json` | Returns snapshot bytes plus explicit absent-sidecar state for D12; a torn/failed sidecar read is not mistaken for a stable absence. |
| I01 | T024/T025 | Empty raw history and empty index | First valid snapshot, child identities, and sidecar classify as accepted with exact hashes. |
| I02 | T024/T025 | Same snapshot/children/sidecar identities and hashes after restart | Replay/no-op; no duplicate raw record or observation is planned. |
| I03 | T024/T025 | Same snapshot ID, different snapshot hash | First hash remains accepted; one body-free parented collision observation is planned. |
| I04 | T024/T025 | Same sidecar ID, different exact sidecar bytes/hash | Snapshot remains accepted; sidecar collision is independently observed and rejected bytes are absent. |
| I05 | T024/T025 | Same case/event/attempt/finding/lineage/repeat/artifact identity, different hash | Each entity kind is independently indexed and produces its own body-free parented observation. |
| I06 | T024/T025 | Collision | Observation carries normative SHA-256 ID, UTC observed time, portable source, entity kind/stable identity, accepted/rejected hashes, exact accepted parent snapshot ID/hash, locked disposition, and limitation. |
| I07 | T024/T025 | Same observation ID replay; later distinct observed-at attempt | Same ID is idempotent; distinct ID remains append-only history. |
| I08 | T024/T025 | Index missing/corrupt/stale while raw history is complete | Index rebuilds from raw truth and reaches the same acceptance map without emitting a false collision or storing rejected content. |
| I09 | T024/T025 | Crash after raw append but before `commit(import_plan)` | Restart repairs the raw-ahead/index-behind state and treats the accepted record as replay. |
| I10 | T024/T025 | Raw append fails or writes fewer records than planned | T026 does not call `commit`; index remains unchanged and restart derives only verifiable raw identities. |
| I11 | T024/T025 | Index ahead of raw or otherwise unverifiable cache row | Unverified row is discarded during rebuild; the cache never becomes acceptance authority. |
| I12 | T024/T025 | Incremental overlap repeats stable event IDs | Exact repeats dedupe; changed hashes become child collisions; cursors/overlap provenance remain intact. |
| F01 | T025 | Committed fixtures | Baseline/incremental directory bundles use invented neutral identities, valid 64-hex hashes, no account/workspace/machine identifiers, and no raw logs. |
| F02 | T025 | Full module matrix | Tests cross only the three declared interfaces, assert returned outcomes instead of private helpers, and remain hermetic under `tmp_path`. |
| F03 | T025/T026 | Subprocess, network, audit, agent, issue/run, source-mutation spies | Zero calls for valid, invalid, missing-config, replay, and collision paths. |
| W01 | T026 | Valid baseline/incremental through public adapter | Reader → decoder → index classification occurs before append; `collect()` returns accepted raw count and `normalize()` preserves all contract facts. |
| W02 | T026 | Replay or any rejected/colliding body | `write_raw` receives no replay/rejected body; collision writes only the body-free observation. |
| W03 | T026 | Accepted raw records plus observations | Existing redaction remains on accepted writes; normalization keys observations by `(parentSnapshotID, observationID)` and retains sidecar/child provenance. |
| W04 | T026 | Missing/unreadable config/root/index or write/normalize I/O failure | Graceful zero/skip with pipeline progress preserved; tests restore every patched shared helper. |
| W05 | T026 | Active adapter source inspection | Only the strict decoder validates; no duplicate validator, alias map, second file read, or collector-local identity map remains. |

## Gate contract

T022 through T026 are strictly serial and all belong to AidataL1L2. Each task
must use normal `git commit` and `git push` with
`core.hooksPath=scripts/hooks`. Pre-commit/pre-push must report a clean routing
audit and a zero-exit resolver-selected AidataL1L2 local gate. New test files
must appear in both `aidata/CONTEXT.md` and
`aidata/adapters/CONTEXT.md` `test_paths` in the same commit. A focused
`scripts/context/run AidataL1L2 --mode local` is diagnostic only after an
emitted hook failure and never substitutes for the next normal hook run.

The delivery checkout/branch that triggered this re-scope is evidence only
until the reviewed T022–T026 graph is scheduled. No stopped monolithic repair
is reused as a task result merely because some code resembles a matrix row.
