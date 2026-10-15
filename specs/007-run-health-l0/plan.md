# Implementation Plan: Dev Team Run-Health L0 Collection

**Branch**: `007-run-health-l0` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-run-health-l0/spec.md`

## Summary

Repair stale Multica run collection by making configured per-agent task history the run-discovery and lifecycle source, retaining a pending-run revisit set, and emitting six additional privacy-safe raw families from the three already scheduled Multica adapters: run messages, agent snapshots, runtime usage, runtime activity, issue timelines, and issue–PR candidates. A shared adapter helper projects source payloads, canonicalizes hashes, applies red-line rules before hashing, and enforces a read-only CLI allowlist. Existing normalized contracts and every downstream aidata layer remain unchanged.

## Technical Context

**Language/Version**: Python 3.9+ compatible with the repository hook interpreter and cron Python 3.14

**Primary Dependencies**: Python standard library, existing `multica` CLI, existing aidata `rawio` and `state` helpers

**Storage**: Existing append-only JSONL raw shards under the configured aidata `L1_collect/raw/<family>/`; existing watermark state for cursors/pending identities

**Testing**: `pytest` with injected canned CLI payloads and subprocess spies; normal repository hook-selected gates

**Target Platform**: macOS local aidata collector and existing 04:00 cron chain

**Project Type**: Python data-collection adapters inside the AIDash monorepo

**Performance Goals**: One CLI call per unique configured agent/runtime where possible; bounded pages of 200 agent tasks; incremental message/timeline reads; no new scheduled source pass

**Constraints**: Read-only CLI; fixture-only CI; no raw message/tool content; no L2–L5 change; empty usage remains empty; no machine-local IDs in tracked files

**Scale/Scope**: Explicit configured agent allowlist across configured workspaces, existing known issues, and their observed runs; seven resulting raw families counting repaired `multica_run`

## Constitution Check

*GATE: Passed before research and re-checked after design.*

| Authority | Design response | Result |
|---|---|---|
| Constitution: ship the smallest correct thing | Extends existing adapters and schedule; adds no analysis or UI. | PASS |
| Constitution: least privilege / privacy | Exact read-only command allowlist; project-before-write; hash/length only for message/tool content. | PASS |
| Constitution: deterministic, testable behavior | Canonical SHA-256, explicit terminal statuses, stable keys, overlap replay, canned fixtures. | PASS |
| `AidataFoundation` leaf | Only shared configuration and its owned tests change in the Foundation commit. | PASS |
| `AidataL1L2` leaf | Collection and paired compatibility behavior stay in adapters; no fictional new layer directory. | PASS |
| `AidataL1L2` red line | External access is read-only and raw output append-only. | PASS |
| Aidata test contract | Unit tests are hermetic and do not require `config_local.py`, network, or live CLI. | PASS |
| Existing schedule contract | No `SOURCES` entry or runner list is added; the three registered adapters emit the raw sub-families. | PASS |
| Cross-layer task rule | Work is split into one Foundation commit and one AidataL1L2 commit in one PR. | PASS |
| Repository verification contract | Implementation relies on normal commit/push hooks and CI; the sole real collection is explicit acceptance evidence, not a CI test. | PASS |

No constitutional violation requires a complexity exception.

## Technical Design

### Collection topology

The physical repository boundary remains the existing L1/L2 adapter seam. In this feature, “L0” names only the raw side of that seam:

```text
existing 04:00 schedule
├── multica_issue.collect()
│   ├── existing multica_issue raw
│   ├── multica_issue_timeline raw
│   └── multica_issue_pr_link raw (metadata candidates)
├── multica_comment.collect()
│   ├── existing multica_comment raw
│   └── multica_issue_pr_link raw (comment candidates)
└── multica_run.collect()
    ├── repaired multica_run raw (agent-task discovery)
    ├── multica_run_message raw
    ├── multica_agent_snapshot raw
    ├── multica_runtime_usage raw
    └── multica_runtime_activity raw
```

The additional family names are destinations passed to `write_raw`; they are not added to `config.SOURCES`, do not receive normalize/merge stages, and do not require a runner change.

### Configuration

`aidata/config.py` adds neutral tracked defaults:

- `MULTICA_RUN_AGENTS`: ordered `(workspace_id, agent_id)` pairs, empty by default and populated only in ignored `config_local.py`.
- `MULTICA_RED_LINE_RULES`: ordered enabled identifiers. Initial order is `gh_pr_merge_bypass`, `force_push_protected`, `no_verify`, `admin_flag` so a command-specific match wins over a generic flag match.
- `MULTICA_PROTECTED_BRANCHES`: defaults to `("main", "master")`.
- `MULTICA_GH_MERGE_BYPASS_FLAGS`: defaults to `("--admin",)`.

The example file uses only zero UUIDs/placeholders. With no configured agents, new run-health collection returns zero without crashing.

### Run discovery and lifecycle

For every unique configured agent, `multica agent tasks <agent> --limit 200 --output json` is the sole discovery feed. The collector supports both the documented cursor envelope and a bare-list terminal response. It follows every provided `before` cursor. A full bare list without a cursor is recorded as incomplete and must not advance a completeness cursor.

State is per agent and contains the newest stable discovery marker plus the set of non-terminal run IDs. Each scheduled pass reads the newest task pages and continues far enough to find every pending ID or exhaust the source. Runs whose last status is not exactly `completed`, `failed`, or `cancelled` remain pending. Unknown statuses therefore fail open for refresh, not closed as if complete.

The persisted run projection includes only the stable legacy fields needed by the current normalizer plus newly required lifecycle facts. Queue timestamps come directly from created/dispatched/started/completed fields. `failure_reason` and `cancelled_by` are copied only when present. A run model is taken only from that run's source usage entry; the current agent model is never substituted. For normalized-run compatibility, per-issue usage may still be queried for a discovered run's known issue, but issue history never discovers or filters runs.

### Message privacy and red-line ordering

`multica issue run-messages <run-id> --since <sequence> --output json` uses a per-run sequence cursor with overlap and stable `(run_id, sequence)` identity. Before any call to `write_raw`, the adapter builds a persistence DTO that has no raw body/input/output field.

Canonical bytes are UTF-8 for strings and sorted-key, compact, UTF-8 JSON for structured values. Hashes are full lowercase SHA-256; lengths are canonical byte counts. A tool input is first tokenized with `shlex` when it is a string, or by the string value under `cmd`/`command` when structured. The ordered rule matcher runs on those transient tokens before canonical hashing. Unparseable input receives no guessed rule. Only the first rule identifier or null crosses the DTO boundary.

Force-push matching requires a `git push` command, an exact force token, and a destination resolving to a configured protected branch (including `HEAD:<branch>`). The generic `admin_flag` and `no_verify` rules match exact tokens only. The `gh_pr_merge_bypass` rule requires the exact `gh pr merge` prefix plus a configured bypass flag.

### Agent and runtime observations

`multica agent get <agent>` is projected to model, thinking level, runtime ID, and maximum concurrency. A SHA-256 of that canonical projection is state only; the raw snapshot is written when the hash changes. Each unique referenced runtime is queried once per pass with `runtime usage --days 90` and `runtime activity`. The payload is wrapped only with runtime/workspace provenance and `observed_at`. An empty list/object stays empty; no numeric default or model fallback is introduced.

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
specs/007-run-health-l0/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── acceptance-matrix.md
│   └── l0-records.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
aidata/
├── config.py
├── config_local.example.py
├── adapters/
│   ├── _multica.py
│   ├── _multica_l0.py              # new projection/hash/rule/PR helpers
│   ├── multica_run.py
│   ├── multica_issue.py
│   └── multica_comment.py
└── tests/
    ├── test_config_multica.py
    ├── test_multica_shared.py
    ├── test_multica_run_collect.py
    ├── test_multica_issue_collect.py
    ├── test_multica_comment_adapter.py
    └── test_runner_sources.py
```

**Structure Decision**: Reuse the existing Foundation configuration seam and the honest combined L1/L2 adapter seam. New generic collection logic belongs in one private adapter helper. Existing adapter entry points retain scheduling and test monkeypatch seams; no source, schema, cron script, or downstream directory is added.

## Delivery Slices

1. **AidataFoundation commit**: neutral configuration, local example, and Foundation-owned tests. Independently proves no-config degradation and no tracked private identifiers.
2. **AidataL1L2 commit**: shared read-only/privacy helper, run repair, raw families, and all canned adapter/compatibility tests. Depends on slice 1 and independently proves every collection contract.
3. **Acceptance evidence (no additional source commit)**: normal hook-selected gates plus one explicit real local collection with sanitized per-family counts/samples. This is attached to the implementation handoff and never run in CI.

The two commits form one PR and one feature goal. A failure whose root cause is outside these two owned leaves becomes a new task rather than scope expansion.

## Post-Design Constitution Re-check

- Exactly two implementation leaves are changed and each owns one commit.
- The physical L1/L2 layout and existing source registry remain authoritative.
- Privacy is structural: persistence DTOs cannot carry raw message/tool fields.
- No source mutation command, live CI dependency, analysis layer, or UI was introduced.
- Missing configuration degrades to zero collection, and missing source values remain missing.

Result: **PASS**. No complexity exception is required.
