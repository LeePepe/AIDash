# Data Model: Dev Team Run-Health L1 Collection

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

**Source facts**: created, dispatched, started, completed timestamps; sanitized failure reason; stable cancelled-by ID; runtime ID; attempt metadata; source usage; model only when run usage supplies it

**Compatibility facts**: legacy keys consumed by the existing normalizer, including issue identifier and per-issue usage enrichment where available

**Forbidden inference**: configured agent model, zero-filled token counts, synthesized completion time, or issue number as freshness authority

**Free-text rule**: `failure_reason`, `trigger_summary`, and `error` keep their legacy key and string/null shape only after secret/email redaction, URL/path replacement, control removal/whitespace normalization, and the 512-byte cap. Raw source text never enters the DTO. `cancelled_by` contains a stable source ID only, never a display name/email.

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

**Stable key**: `snapshot_key = SHA-256(agent_id, transition_ordinal, config_hash)`

**Fields**: snapshot key, agent ID, workspace ID, monotonic transition ordinal, source-provided model, thinking level, runtime ID, maximum concurrency, canonical `config_hash`, first observed time

**Write rule**: Persist only when `config_hash` differs from that agent's committed hash. Candidate ordinal is `last_ordinal + 1`; first store durable pending `(ordinal, config_hash, first_observed_at, canonical_allowed_projection)`, write the row solely from that exact pending candidate, then commit hash/ordinal and clear pending. Write failure or crash retry reuses the same candidate key/time/values even if the live source has changed; after pending B commits, a newly observed C becomes the next candidate. `A → B → A` yields ordinals 1, 2, 3 and three distinct keys.

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

## 10. Copilot OTel Usage Observation

**Family/source**: `copilot_otel`

**Stable key**: `observation_key = SHA-256(source_slot, stream_generation, line_start_offset, canonical allowed projection)`; path is excluded

**Fields**: observation key, validated neutral source slot (`fullstack` or `pr-manager`), source start/end timestamps, conversation ID, response model, source-supplied input tokens, output tokens, cache-read input tokens, cache-write input tokens, reasoning output tokens, observed time

**Selection rule**: configuration validation rejects unknown or duplicate source slots before file access; only a span whose `gen_ai.operation.name` is exactly `chat` is projected

**Offset state**: keyed by configured source slot, with device, inode, stream generation, and byte offset. Only newline-terminated bytes can advance the candidate offset. A new inode or truncation below the offset increments the generation and restarts at zero. State advances only after all selected DTOs through the candidate offset persist successfully.

**Absent value rule**: any absent counter/model/time remains absent; zero is retained only when the OTel span explicitly supplies zero

**Forbidden fields**: response ID, `github.copilot.context.*`, prompt/completion/content attributes, arbitrary span attributes/events/resources, whole source span, local file path, device/inode/offset

**Normalize boundary**: `normalize() -> 0` creates no clean database; `copilot_otel` is absent from `MERGE_SOURCES`.

**Future join boundary**: preserve `conversation_id` and source timestamps but do not assign tokens to a run in L1. Later attribution must require conversation ID equality and a span timestamp within the run's `started_at..completed_at`; zero or multiple matching run windows remain unassigned/ambiguous rather than guessed.

## State and cursor invariants

1. Collection cursors and committed state advance only after the corresponding records are successfully persisted; agent-snapshot pending state is durably prepared before its raw write and cleared only after committed state advances on success.
2. Run freshness is never determined by issue number.
3. Message sequence and timeline timestamp cursors replay an overlap and rely on stable identities for deduplication.
4. Unknown run status remains pending.
5. Timeline truncation and agent-task pagination incompleteness are explicit observations, not silent success.
6. No state value contains raw message/tool/content data; OTel state is addressed by logical stream label rather than persisted path.
7. Agent snapshot committed state advances only after write; a recurring hash receives a new transition ordinal while a retry writes its complete pre-write pending projection before observing a later source value.
8. An incomplete OTel line never advances its stream offset.

## Relationships

```text
Configured Agent 1 ──* Run Observation *──0..1 Known Issue
        │                    │                    │
        │                    └──* Run Message     ├──* Timeline Event
        ├──* Agent Snapshot                       └──* Issue–PR Candidate
        ├──0..1 Runtime ──* Usage / Activity
        └──0..1 Copilot conversation ──* OTel Usage (future time-window join)
```

These relationships are provenance only. No aggregate, score, duration, run-token attribution, or health conclusion is defined in L1.
