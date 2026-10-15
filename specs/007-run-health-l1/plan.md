# Implementation Plan: Dev Team Run-Health L1 Collection

**Branch**: `007-run-health-l1` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-run-health-l1/spec.md`

## Summary

Repair stale Multica run collection by making configured per-agent task history the run-discovery and lifecycle source, retaining a pending-run revisit set, and emitting six additional privacy-safe L1 raw families from the three scheduled Multica adapters. Add `copilot_otel` as one registered L1-only source, producing the eighth total family through the existing daily repository runner. The runner and an ordered-list equality verifier ship together in `AidataOps`; one authorized manual `cli.py collect` run supplies privacy-safe repository acceptance evidence. Shared helpers project and sanitize before persistence, canonicalize hashes, apply red-line rules before hashing, enforce a read-only CLI allowlist, and read OTel JSONL with replay-safe byte offsets. Existing normalized contracts and every downstream aidata layer remain unchanged.

## Technical Context

**Language/Version**: Python 3.9+ compatible with the repository hook interpreter and cron Python 3.14

**Primary Dependencies**: Python standard library, existing `multica` CLI, existing aidata `rawio` and `state` helpers

**Storage**: Existing append-only JSONL raw shards under the configured aidata `L1_collect/raw/<family>/`; existing watermark state for cursors/pending identities

**Testing**: `pytest` with injected canned CLI payloads and subprocess spies; normal repository hook-selected gates

**Target Platform**: macOS local aidata collector and existing 04:00 cron chain

**Project Type**: Python data-collection adapters inside the AIDash monorepo

**Performance Goals**: One CLI call per unique configured agent/runtime where possible; bounded pages of 200 agent tasks; incremental message/timeline and per-file byte-offset reads; no new timer or duplicate Multica pass

**Constraints**: Read-only CLI and local-file reads; fixture-only CI; no raw message/tool/content/path persistence; no L2–L5 change or OTel-to-run join; empty Multica usage remains empty; no machine-local IDs or paths in tracked files

**Scale/Scope**: Explicit configured agent allowlist across configured workspaces, existing known issues and runs, plus explicitly configured Copilot OTel logical source slots; eight resulting raw families counting repaired `multica_run`

## Constitution Check

*GATE: Passed before research and re-checked after design.*

| Authority | Design response | Result |
|---|---|---|
| Constitution: ship the smallest correct thing | Extends existing adapters and schedule; adds no analysis or UI. | PASS |
| Constitution: least privilege / privacy | Exact read-only command allowlist; sanitizer/project-before-write; hash/length only for message/tool content; OTel field allowlist. | PASS |
| Constitution: deterministic, testable behavior | Canonical SHA-256, explicit terminal statuses, transition ordinals, stable keys, byte-offset/overlap replay, canned fixtures. | PASS |
| `AidataFoundation` leaf | Only shared configuration and its owned tests change in the Foundation commit. | PASS |
| `AidataL1L2` leaf | Collection and paired compatibility behavior stay in adapters; no fictional new layer directory. | PASS |
| `AidataL1L2` red line | External access is read-only and raw output append-only. | PASS |
| Aidata test contract | Unit tests are hermetic and do not require `config_local.py`, network, or live CLI. | PASS |
| Existing cadence contract | Add `copilot_otel` to `SOURCES` and the repository runner without adding a timer; require ordered-list registry equality; keep `MERGE_SOURCES` unchanged; require no installed-copy mutation or live scheduled-run proof for repository acceptance. | PASS |
| Cross-layer task rule | Work is split into Foundation, AidataL1L2, and AidataOps commits in one PR. | PASS |
| Repository verification contract | Implementation relies on normal commit/push hooks and CI; T004's one manual `cli.py collect` run is fixed-candidate acceptance evidence, never a CI test. | PASS |

No constitutional violation requires a complexity exception.

## Technical Design

### Collection topology

The physical repository boundary remains the existing L1/L2 adapter seam. This feature changes only its L1 raw side:

```text
existing 04:00 schedule
├── multica_issue.collect()
│   ├── existing multica_issue raw
│   ├── multica_issue_timeline raw
│   └── multica_issue_pr_link raw (metadata candidates)
├── multica_comment.collect()
│   ├── existing multica_comment raw
│   └── multica_issue_pr_link raw (comment candidates)
├── multica_run.collect()
    ├── repaired multica_run raw (agent-task discovery)
    ├── multica_run_message raw
    ├── multica_agent_snapshot raw
    ├── multica_runtime_usage raw
    └── multica_runtime_activity raw
└── copilot_otel.collect()               # one new registered source
    └── copilot_otel raw (configured local JSONL slots)
```

The six Multica family names are additive destinations passed to `write_raw`, not registered sources. `copilot_otel` is registered in `config.SOURCES` and the repository runner so it runs on the same cadence. Because `cli.py normalize` invokes every registered source, its adapter exposes a tested `normalize() -> 0` that creates no clean DB; it is excluded from `MERGE_SOURCES`.

### Configuration

`aidata/config.py` adds neutral tracked defaults:

- `MULTICA_RUN_AGENTS`: ordered `(workspace_id, agent_id)` pairs, empty by default and populated only in ignored `config_local.py`.
- `MULTICA_RED_LINE_RULES`: ordered enabled identifiers. Initial order is `gh_pr_merge_bypass`, `force_push_protected`, `no_verify`, `admin_flag` so a command-specific match wins over a generic flag match.
- `MULTICA_PROTECTED_BRANCHES`: defaults to `("main", "master")`.
- `MULTICA_GH_MERGE_BYPASS_FLAGS`: defaults to `("--admin",)`.
- `COPILOT_OTEL_SOURCE_SLOTS`: tracked allowlist `("fullstack", "pr-manager")`.
- `COPILOT_OTEL_STREAMS`: ordered `(source_slot, file_path)` pairs, empty by default and populated only in ignored `config_local.py`; a slot outside the tracked neutral allowlist is a configuration error before any file read or persistence, while the path is never persisted.

The example file uses only zero UUIDs/placeholders. With no configured agents, new run-health collection returns zero without crashing.

### Run discovery and lifecycle

For every unique configured agent, `multica agent tasks <agent> --limit 200 --output json` is the sole discovery feed. The collector supports both the documented cursor envelope and a bare-list terminal response. It follows every provided `before` cursor. A full bare list without a cursor is recorded as incomplete and must not advance a completeness cursor.

State is per agent and contains the newest stable discovery marker plus the set of non-terminal run IDs. Each scheduled pass reads the newest task pages and continues far enough to find every pending ID or exhaust the source. Runs whose last status is not exactly `completed`, `failed`, or `cancelled` remain pending. Unknown statuses therefore fail open for refresh, not closed as if complete.

The persisted run projection includes only the stable legacy fields needed by the current normalizer plus newly required lifecycle facts. Queue timestamps come directly from created/dispatched/started/completed fields. `cancelled_by` retains only a stable source actor ID. `failure_reason`, `trigger_summary`, and `error` retain their existing key and string/null shape only after the lifecycle sanitizer described below. A run model is taken only from that run's source usage entry; the current agent model is never substituted. For normalized-run compatibility, per-issue usage may still be queried for a discovered run's known issue, but issue history never discovers or filters runs.

### Lifecycle free-text sanitizer

Every allowed lifecycle free-text value is sanitized before DTO construction and before `write_raw`: non-string structured values are rejected; Unicode/newlines are normalized; whole emails become `<EMAIL>`; the existing secret redactor runs; file URIs plus absolute POSIX, home-relative, Windows drive, and UNC path-shaped sequences become `<LOCAL_PATH>`; remaining URI-shaped values become `<URL>`; disallowed controls are removed and whitespace is collapsed; output is capped deterministically at 512 UTF-8 bytes without splitting a code point, using an in-budget `<TRUNCATED>` suffix. Null remains null and an empty source string remains empty. Privacy-favoring path false positives are accepted.

Fixtures apply distinct sentinels to every permitted free-text field and assert both the DTO and serialized `write_raw` capture contain no source secret, email, URL, path, control, or over-limit suffix. `multica_run.normalize()` continues to receive the same compatibility keys/types and last-write-wins run identity, now with sanitized rather than raw text; historical rows are not rewritten.

### Message privacy and red-line ordering

`multica issue run-messages <run-id> --since <sequence> --output json` uses a per-run sequence cursor with overlap and stable `(run_id, sequence)` identity. Before any call to `write_raw`, the adapter builds a persistence DTO that has no raw body/input/output field.

Canonical bytes are UTF-8 for strings and sorted-key, compact, UTF-8 JSON for structured values. Hashes are full lowercase SHA-256; lengths are canonical byte counts. A tool input is first tokenized with `shlex` when it is a string, or by the string value under `cmd`/`command` when structured. The ordered rule matcher runs on those transient tokens before canonical hashing. Unparseable input receives no guessed rule. Only the first rule identifier or null crosses the DTO boundary.

Force-push matching requires a `git push` command, an exact force token, and a destination resolving to a configured protected branch (including `HEAD:<branch>`). The generic `admin_flag` and `no_verify` rules match exact tokens only. The `gh_pr_merge_bypass` rule requires the exact `gh pr merge` prefix plus a configured bypass flag.

### Agent and runtime observations

`multica agent get <agent>` is projected to workspace ID, model, thinking level, runtime ID, and maximum concurrency. Per-agent state holds committed `(last_hash, last_ordinal)` plus an optional pending candidate containing `(ordinal, config_hash, first_observed_at)` and the complete canonical allowed projection. When the hash changes, persist that complete pending candidate to state before the raw write, derive SHA-256 of `(agent_id, ordinal, config_hash)`, write the row only from the pending projection, then commit hash/ordinal and clear pending only after success. If pending B survives a crash and the live source has already changed to C, retry writes B exactly before observing and preparing C; it never combines B's identity with C's fields or loses B. Write failure or crash retry therefore reuses the same key/time and values, while `A → B → A` produces ordinals 1/2/3 and three distinct observations. Each unique referenced runtime is queried once per pass with `runtime usage --days 90` and `runtime activity`. The payload is wrapped only with runtime/workspace provenance and `observed_at`. An empty list/object stays empty; no numeric default or model fallback is introduced.

### Copilot OTel L1 collection

`copilot_otel.collect()` first validates every configured logical source slot against the tracked `fullstack`/`pr-manager` allowlist, then reads each accepted stream in binary from state `{device, inode, generation, offset}`. An unknown, duplicate, or non-neutral slot fails configuration before any file read or persistence. Only newline-terminated JSON records are consumed; an incomplete trailing line leaves the offset at its start for the next pass. A new inode or a size below the stored offset increments the local stream generation and starts at byte zero. Complete malformed/non-chat lines may be consumed without persistence; state advances only after every selected record before the candidate offset is successfully written.

Only spans with `gen_ai.operation.name=chat` cross the DTO boundary. The projection retains the neutral configured source slot, source start/end timestamps, `gen_ai.conversation.id`, `gen_ai.response.model`, and source-supplied `gen_ai.usage.input_tokens`, `output_tokens`, `cache_read.input_tokens`, `cache_write.input_tokens`, and `reasoning.output_tokens`. The stable observation key hashes `(source_slot, generation, line_start_offset, canonical allowed projection)`; the path never persists. `gen_ai.response.id`, `github.copilot.context.*`, content attributes, whole spans, and paths are discarded before `write_raw` and covered by serialized sentinel fixtures.

This L1 family is independent of empty Multica run/runtime usage. It preserves the fields later needed to attribute a span by `(conversation_id, span timestamp within run started_at..completed_at)` but performs no attribution or token aggregation here; conversation ID alone is explicitly insufficient because one Copilot session can span several runs.

### Issue timeline and PR candidates

`multica_issue` reads `issue timeline <id> --activity-only --output json` for every known issue. First observation attempts a full available backfill; later reads use a one-second overlap from the last event timestamp. Stable server IDs are preferred; otherwise the key is the SHA-256 of issue ID, action, timestamp, actor identity, and before/after values. Every response also writes a stable collection marker keyed from the issue, effective `since` value, returned event keys, and truncation state, so an empty truncated response remains observable. Successful stderr is classified so the server's truncation warning becomes `history_truncated: true` plus a fixed warning identifier; raw warning text is not persisted. A truncated backfill is never represented as complete.

Issue metadata and comments are scanned transiently for strict `https://github.com/<owner>/<repo>/pull/<number>` candidates. Stored values are the normalized URL without query/fragment plus workspace ID, issue ID, source kind, source record ID, and observation time. Surrounding comment/metadata content never enters the candidate record. Identity includes provenance so the same URL from distinct sources remains attributable while replay is idempotent.

### Read-only enforcement and failure behavior

The shared Multica helper accepts only these command prefixes for collectors:

- `agent tasks`, `agent get`
- `issue list`, `issue usage`, `issue comment list`, `issue run-messages`, `issue timeline`
- `runtime usage`, `runtime activity`

Any other prefix fails before spawning the subprocess. Existing `run_json` callers keep their return shape; a metadata-preserving variant returns parsed stdout plus classified successful-stderr facts for timeline truncation. One agent, run, runtime, or issue failure is isolated and does not abort other configured sources. State advances only for evidence successfully persisted.

## Project Structure

### Documentation (this feature)

```text
specs/007-run-health-l1/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── acceptance-matrix.md
│   └── l1-records.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
aidata/
├── config.py                      # source registration + neutral config
├── config_local.example.py
├── CONTEXT.md                  # register the new adapter-owned fixture path
├── adapters/
│   ├── CONTEXT.md
│   ├── _multica.py
│   ├── _multica_l1.py              # new projection/sanitize/hash/rule/PR helpers
│   ├── copilot_otel.py             # registered L1 reader + no-op normalize
│   ├── multica_run.py
│   ├── multica_issue.py
│   └── multica_comment.py
├── scripts/
│   └── aidata_digest_run.sh             # existing cadence, add source
└── tests/
    ├── test_config_multica.py
    ├── test_copilot_otel_adapter.py
    ├── test_multica_shared.py
    ├── test_multica_run_collect.py
    ├── test_multica_issue_collect.py
    ├── test_multica_comment_adapter.py
    └── test_runner_sources.py          # AidataOps ordered registry verifier
```

**Structure Decision**: Reuse the existing Foundation configuration seam and the honest combined L1/L2 adapter seam. Generic Multica projection logic stays private; the OTel reader is a registered adapter because the accepted addition explicitly adds an L1 source. Routing metadata adds its fixture to `AidataL1L2`; `AidataOps` wires only the existing runner cadence. No normalized schema, new timer, or downstream directory is added.

## Delivery Slices

1. **AidataFoundation commit**: neutral configuration, `SOURCES` registration, local example, and Foundation-owned tests. Independently proves no-config degradation, no tracked private identifiers, and `MERGE_SOURCES` exclusion.
2. **AidataL1L2 commit**: shared read-only/privacy helper, lifecycle sanitizer, replay-safe snapshots, registered OTel adapter/no-op normalizer, run repair, raw families, routing metadata, and all canned adapter/compatibility tests. Depends on slice 1 and independently proves every collection contract.
3. **AidataOps commit**: add `copilot_otel` to the existing repository runner list and change its owned verifier to compare the parsed ordered list directly with ordered `config.SOURCES`, so omissions, duplicates, and reordering fail. Depends on slices 1–2; adds no timer or collection logic.
4. **Acceptance and publication evidence (no additional source commit)**: normal hook-selected gates plus exactly one unfiltered manual `cli.py collect` run with a nonzero sanitized count/sample for every family belong to the fixed prepublication candidate. After independent implementation PASS grants publication permission, push only that reviewed SHA, create/update the non-Draft PR, then prove local/remote/PR equality.

The three commits form one PR and one feature goal. Host installation and scheduled-run proof are not delivery slices, acceptance gates, or PR merge conditions. Separately after merge, the Owner-authorized lead CLI session may synchronize the merged runner to the installed Hermes copy, verify cadence, and post the receipt that gates MY-1817 closure only; no squad agent or prepublication candidate mutates the host. A failure whose root cause is outside these owned leaves becomes a new task rather than scope expansion.

## Post-Design Constitution Re-check

- Exactly three implementation leaves are changed and each owns one commit.
- The physical L1/L2 layout and source registry remain authoritative; `copilot_otel` has no L2 output or L3 registration.
- Privacy is structural: persistence DTOs cannot carry raw message/tool/path/content fields and lifecycle text is sanitized before construction.
- No source mutation command, live CI dependency, analysis layer, or UI was introduced.
- Missing configuration degrades to zero collection, and missing source values remain missing.
- Host mutation and scheduled-run proof are outside repository implementation and acceptance; the Owner-authorized lead CLI session's post-merge receipt gates MY-1817 closure only.

Result: **PASS**. No complexity exception is required.
