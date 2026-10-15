# Data Model: Dev Team Run-Health L0 Collection

All entities in this document are append-only raw observation contracts. They do not define new normalized tables or analytical metrics.

## Identity conventions

- Source UUIDs are retained when supplied.
- A derived identity is full lowercase SHA-256 of canonical UTF-8 bytes.
- Canonical structured values use JSON with sorted keys, compact separators, and UTF-8 encoding.
- Observation replay may write physical JSONL lines through existing raw IO, but logical consumers identify records by the stable keys below.
- `observed_at` records collection time and never substitutes for a missing source event time.

## 1. Run Observation

**Family**: `multica_run`

**Stable key**: `run_id`

**Required provenance**: `run_id`, `agent_id`, `workspace_id`, `issue_id` when supplied, `observed_at`, `status` when supplied

**Source facts**: created, dispatched, started, completed timestamps; failure reason; cancelled-by identity; runtime ID; attempt metadata; source usage; model only when run usage supplies it

**Compatibility facts**: legacy keys consumed by the existing normalizer, including issue identifier and per-issue usage enrichment where available

**Forbidden inference**: configured agent model, zero-filled token counts, synthesized completion time, or issue number as freshness authority

### Lifecycle

```text
unknown/new status ─┐
queued/dispatched ──┼──> running ──> completed
running/unknown ────┤             ├─> failed
                    └─────────────└─> cancelled
```

Only `completed`, `failed`, and `cancelled` leave the pending set. Any other value, including null or a future status, remains pending.

## 2. Pending Run State

**Storage**: existing collector state, not a raw family

**Stable key**: `(agent_id, run_id)`

**Fields**: run ID, last observed status, last successful observation time

**Transition rule**: add/update after a successful non-terminal persistence; remove only after successfully persisting a terminal observation

**Failure rule**: a missing page, inaccessible run, or write failure does not remove pending state

## 3. Run Message Observation

**Family**: `multica_run_message`

**Stable key**: `(run_id, sequence)`

**Fields**:

- Run/issue/workspace identity and sequence
- Source timestamp, message type, and tool name when supplied
- Optional message-body SHA-256 and UTF-8 byte length
- Optional tool-input SHA-256 and UTF-8 byte length
- Optional tool-output SHA-256 and UTF-8 byte length
- Optional first matched `red_line_rule`
- Observation time

**Forbidden fields**: raw body, raw input, raw output, body/input/output preview, whole source message

## 4. Red-Line Match

**Storage**: embedded in a Run Message Observation

**Value**: one enabled configured rule identifier or null

**Evaluation order**:

1. `gh_pr_merge_bypass`
2. `force_push_protected`
3. `no_verify`
4. `admin_flag`

Local configuration can disable or reorder identifiers. The first successful matcher wins; the raw match is never stored.

## 5. Agent Snapshot

**Family**: `multica_agent_snapshot`

**Stable key**: `(agent_id, config_hash)`

**Fields**: agent ID, workspace ID, source-provided model, thinking level, runtime ID, maximum concurrency, canonical `config_hash`, observed time

**Write rule**: persist only when `config_hash` differs from that agent's last successfully persisted hash

**Absent value rule**: null stays null; a missing value can itself cause a change from the prior snapshot

## 6. Runtime Usage Observation

**Family**: `multica_runtime_usage`

**Stable key**: SHA-256 of `(runtime_id, observed window identity, canonical source payload)`

**Fields**: runtime ID, associated configured workspace IDs, requested day window, exact source `usage` value, observed time

**Empty rule**: an empty list/object or no usage rows is stored as that exact empty value inside an observation wrapper; no token, cost, or model default is added

## 7. Runtime Activity Observation

**Family**: `multica_runtime_activity`

**Stable key**: SHA-256 of `(runtime_id, canonical source activity row or payload identity)`

**Fields**: runtime ID, associated configured workspace IDs, exact source activity value, observed time

**Deduplication**: identical replay for the same runtime has the same logical key

## 8. Issue Timeline Event

**Family**: `multica_issue_timeline`

**Stable key**: for `record_kind=event`, server event ID or SHA-256 of issue ID, action, source timestamp, actor identity, and canonical before/after values; for `record_kind=collection`, SHA-256 of issue ID, effective `since`, ordered returned event keys, and truncation state

**Fields**: record kind, event/collection key, workspace ID, issue ID/identifier, action, source timestamp, actor identity when supplied, before/after values when supplied, effective `since`, returned event count, observation time, `history_truncated`, optional fixed `warning_code`

**Cursor state**: per issue maximum successfully persisted source timestamp plus a one-second replay overlap

**Completeness rule**: every response writes a collection marker, including an empty response. A truncated first backfill is marked incomplete and is never represented as full issue history.

**Forbidden fields**: comment body or raw successful-stderr text

## 9. Issue–PR Candidate

**Family**: `multica_issue_pr_link`

**Stable key**: SHA-256 of workspace ID, issue ID, normalized URL, source kind, and source record ID

**Fields**: workspace ID, issue ID/identifier, normalized GitHub PR URL, source kind (`issue_metadata` or `comment`), source record ID, source timestamp when supplied, observation time

**Normalization**: retain only `https://github.com/<owner>/<repo>/pull/<positive integer>`; lowercase the host, strip query and fragment, and preserve path spelling

**Forbidden fields**: metadata object, comment body, URL-adjacent text

## State and cursor invariants

1. State advances only after the corresponding records are successfully persisted.
2. Run freshness is never determined by issue number.
3. Message sequence and timeline timestamp cursors replay an overlap and rely on stable identities for deduplication.
4. Unknown run status remains pending.
5. Timeline truncation and agent-task pagination incompleteness are explicit observations, not silent success.
6. No state value contains raw message/tool content.

## Relationships

```text
Configured Agent 1 ──* Run Observation *──0..1 Known Issue
        │                    │                    │
        │                    └──* Run Message     ├──* Timeline Event
        ├──* Agent Snapshot                       └──* Issue–PR Candidate
        └──0..1 Runtime ──* Usage / Activity
```

These relationships are provenance only. No aggregate, score, duration, or health conclusion is defined in L0.
