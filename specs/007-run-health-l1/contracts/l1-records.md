# Contract: Run-Health L1 Records

This contract fixes the persistence boundary for implementation. Fields not listed as allowed must be discarded before `write_raw`. Optional means source absence is represented by omission or null according to the existing raw convention, never by an invented value.

## Global rules

1. All Multica commands are read-only and must pass the prefix allowlist before subprocess launch.
2. `observed_at` is an RFC 3339 UTC collection timestamp.
3. Every derived hash is 64 lowercase hexadecimal characters from SHA-256.
4. String lengths are UTF-8 byte counts. Structured values use sorted-key compact JSON before hashing/length.
5. Missing values stay missing. In particular, empty usage is not zero usage and an agent model is not a run model.
6. New records contain no raw message/tool/content preview, email address, local path, or whole CLI/file payload. Permitted lifecycle text is sanitized before DTO construction.
7. Stable logical identity, not physical JSONL line count, defines idempotency.

## Read-only command contract

Allowed leading argument vectors:

```text
agent tasks <agent-id>
agent get <agent-id>
issue list
issue usage <issue-id-or-key>
issue comment list <issue-id>
issue run-messages <run-id>
issue timeline <issue-id>
runtime usage <runtime-id>
runtime activity <runtime-id>
```

Flags may only refine output, pagination, workspace, time window, or activity filtering. Any unlisted verb/subcommand fails before `subprocess.run`. Tests must prove mutation commands such as `issue update`, `issue comment add`, `agent update`, and runtime mutation never launch.

## `multica_run`

Logical identity: `id`/run ID.

Allowed projection:

```json
{
  "id": "run-placeholder",
  "issue_id": "issue-placeholder",
  "agent_id": "agent-placeholder",
  "runtime_id": "runtime-placeholder",
  "kind": "implementation",
  "status": "running",
  "attempt": 1,
  "max_attempts": 1,
  "created_at": "2026-10-15T00:00:00Z",
  "dispatched_at": "2026-10-15T00:00:01Z",
  "started_at": "2026-10-15T00:00:02Z",
  "completed_at": null,
  "failure_reason": "command failed at <LOCAL_PATH>",
  "cancelled_by": null,
  "usage": [],
  "model": null,
  "result": {"session_id": null, "pr_url": null},
  "trigger_summary": null,
  "trigger_comment_id": null,
  "error": null,
  "_workspace_id": "workspace-placeholder",
  "_issue_identifier": "MY-0",
  "_issue_usage": {},
  "_observed_at": "2026-10-15T00:01:00Z",
  "_task_history_complete": true
}
```

`usage: []` is allowed and must stay empty. `model` is populated only when this run's source usage identifies it. `cancelled_by` may contain only a stable source actor ID; display names and emails are dropped. `failure_reason`, `trigger_summary`, and `error` are retained only as compatibility fields after the lifecycle-text contract below. No raw lifecycle string, message body, or whole task object may cross the DTO boundary.

### Lifecycle-text contract

The same deterministic `sanitize_lifecycle_text` function applies to every allowed lifecycle free-text field before the run DTO is built:

1. Null remains null and an empty source string remains empty. A non-string structured value is rejected rather than serialized.
2. Normalize Unicode and line endings, then replace whole email addresses with `<EMAIL>`.
3. Apply the repository's existing secret redactor as defense-in-depth.
4. Replace `file:` URIs, absolute POSIX (`/...`), home-relative (`~/...`), Windows drive (`C:\\...`), and UNC (`\\server\\...`) path-shaped sequences with `<LOCAL_PATH>`. Privacy wins over a possible path false positive.
5. Replace every remaining URI-shaped token, including query/fragment, with `<URL>`.
6. Remove disallowed control characters and collapse whitespace deterministically.
7. Cap the result at 512 UTF-8 bytes without splitting a code point; an over-limit value ends with an in-budget `<TRUNCATED>` marker.

Fixture sentinels cover each step independently in `failure_reason`, `trigger_summary`, and `error`, plus a combined case. Assertions inspect both the projected DTO and captured serialized raw row. The existing normalizer still receives the same keys and string/null shapes; only unsafe content is replaced. Historical raw/clean rows are not rewritten by this feature.

Terminal statuses are exactly `completed`, `failed`, and `cancelled`. Every other status remains in pending state.

## `multica_run_message`

Logical identity: `(run_id, sequence)`.

Allowed fields:

```json
{
  "run_id": "run-placeholder",
  "issue_id": "issue-placeholder",
  "workspace_id": "workspace-placeholder",
  "sequence": 42,
  "created_at": "2026-10-15T00:02:00Z",
  "message_type": "tool",
  "tool_name": "exec_command",
  "body_sha256": null,
  "body_bytes": null,
  "tool_input_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "tool_input_bytes": 12,
  "tool_output_sha256": null,
  "tool_output_bytes": null,
  "red_line_rule": "no_verify",
  "observed_at": "2026-10-15T00:03:00Z"
}
```

Forbidden keys include `body`, `content`, `text`, `input`, `output`, `preview`, `arguments`, `payload`, and any alias containing a raw value.

## Red-line rules

The enabled identifiers come from `MULTICA_RED_LINE_RULES` in priority order. Unknown identifiers are configuration errors, not silently ignored matchers.

| Identifier | Required token-aware match | Mandatory near misses |
|---|---|---|
| `gh_pr_merge_bypass` | Exact `gh pr merge` prefix and one configured bypass flag | `gh pr view --admin`; prose containing the words; merge without bypass |
| `force_push_protected` | `git push`, exact `--force`/`--force-with-lease`/`-f`, and destination resolving to a configured protected branch | force to feature branch; protected branch without force; `-foo` |
| `no_verify` | Exact `--no-verify` token | `--no-verify-mode`; quoted prose not parsed as a command token |
| `admin_flag` | Exact `--admin` token | `--administrator`; `admin` without dashes |

Only the first match is stored. Matching occurs on transient input before canonical bytes are hashed.

## `multica_agent_snapshot`

Logical identity: `snapshot_key`, full SHA-256 of `(agent_id, transition_ordinal, config_hash)`.

Allowed fields: `snapshot_key`, `agent_id`, `workspace_id`, `transition_ordinal`, `model`, `thinking_level`, `runtime_id`, `max_concurrent_tasks`, `config_hash`, `observed_at`.

The source agent name, instructions, email, invocation policy, or other `agent get` fields are forbidden. An unchanged `config_hash` writes no record. For a change, derive `candidate_ordinal = last_successful_ordinal + 1` and persist pending `(ordinal, config_hash, first_observed_at, canonical_allowed_projection)` before raw write, where the projection contains exactly `workspace_id`, `model`, `thinking_level`, `runtime_id`, and `max_concurrent_tasks`. Build the raw row solely from that pending candidate, then commit hash/ordinal and clear pending only after success. If pending B survives a crash and the source now reports C, retry persists B with its original key/time/values and only then prepares C; mixing B's identity with C's values or skipping B is forbidden. A genuine `A → B → A` sequence persists ordinals 1, 2, and 3.

## `multica_runtime_usage`

Logical identity: SHA-256 of runtime ID, requested window, and canonical returned usage.

Allowed fields: `runtime_id`, `workspace_ids`, `days`, `usage`, `observation_key`, `observed_at`.

```json
{
  "runtime_id": "runtime-placeholder",
  "workspace_ids": ["workspace-placeholder"],
  "days": 90,
  "usage": [],
  "observation_key": "0000000000000000000000000000000000000000000000000000000000000000",
  "observed_at": "2026-10-15T00:03:00Z"
}
```

The example is a valid truthful Copilot observation. It must not acquire `input_tokens: 0`, `output_tokens: 0`, cost, or model.

## `multica_runtime_activity`

Logical identity: SHA-256 of runtime ID and the canonical source activity row/payload.

Allowed fields: `runtime_id`, `workspace_ids`, `activity`, `observation_key`, `observed_at`. No field is synthesized inside `activity`.

## `multica_issue_timeline`

Logical identity: a source/derived event key for `record_kind=event`; a derived collection key for `record_kind=collection`.

Allowed fields:

```json
{
  "record_kind": "event",
  "event_key": "event-placeholder",
  "collection_key": null,
  "workspace_id": "workspace-placeholder",
  "issue_id": "issue-placeholder",
  "issue_identifier": "MY-0",
  "action": "status_changed",
  "created_at": "2026-10-15T00:00:00Z",
  "actor_id": null,
  "before": "in_progress",
  "after": "in_review",
  "query_since": null,
  "returned_event_count": null,
  "history_truncated": false,
  "warning_code": null,
  "observed_at": "2026-10-15T00:03:00Z"
}
```

Timeline collection always passes `--activity-only`. Each response also writes one `record_kind=collection` marker whose `collection_key` hashes issue ID, effective `query_since`, ordered returned event keys, and truncation state; this marker carries `returned_event_count`, `history_truncated`, and `warning_code` even when zero events return. Event-only fields are null on a collection marker. Comment bodies and raw stderr are forbidden. The only allowed warning code for the initial implementation is `timeline_history_truncated`; unknown successful stderr may be logged transiently but is not persisted as source content.

## `multica_issue_pr_link`

Logical identity: hash of workspace, issue, normalized URL, source kind, and source record ID.

Allowed fields: `link_key`, `workspace_id`, `issue_id`, `issue_identifier`, `pr_url`, `source_kind`, `source_record_id`, `source_created_at`, `observed_at`.

`source_kind` is `issue_metadata` or `comment`. `pr_url` must exactly match the normalized GitHub pull-request path contract. Comment bodies, metadata maps, URL query/fragment, and non-PR URLs are forbidden.

## `copilot_otel`

Logical identity: `observation_key`, full SHA-256 of source slot, stream generation, line-start byte offset, and canonical allowed projection. Path and `observed_at` are excluded.

Allowed projection:

```json
{
  "observation_key": "0000000000000000000000000000000000000000000000000000000000000000",
  "source_slot": "fullstack",
  "started_at": "2026-10-15T00:00:00Z",
  "ended_at": "2026-10-15T00:00:30Z",
  "conversation_id": "conversation-placeholder",
  "model": "model-placeholder",
  "input_tokens": 120,
  "output_tokens": 40,
  "cache_read_input_tokens": 10,
  "cache_write_input_tokens": 5,
  "reasoning_output_tokens": 8,
  "observed_at": "2026-10-15T00:01:00Z"
}
```

Only configured slots exactly equal to tracked `fullstack` or `pr-manager` qualify; any unknown or duplicate slot is a configuration error before file access or persistence. Only `gen_ai.operation.name=chat` spans qualify. Values map only from source span timestamps, `gen_ai.conversation.id`, `gen_ai.response.model`, `gen_ai.usage.input_tokens`, `output_tokens`, `cache_read.input_tokens`, `cache_write.input_tokens`, and `reasoning.output_tokens`; missing stays missing and explicit zero stays zero.

`gen_ai.response.id`, every `github.copilot.context.*` and content attribute, prompt/completion text, arbitrary resource/event attributes, whole span objects, local file paths, device/inode/offset, malformed-line content, and arbitrary configured labels are forbidden. The validated role slot is neutral provenance; the configured path is local-only input.

Per source slot, binary state stores device/inode/generation/offset locally. Only newline-terminated records are consumed; an incomplete tail keeps the offset at its first byte. Rotation or truncation increments generation and restarts at zero. Complete malformed/non-chat lines may advance, but selected lines advance state only after successful raw persistence.

This source's `normalize() -> 0` creates no clean DB and it is absent from `MERGE_SOURCES`. It never fills `multica_run.usage` or `multica_runtime_usage`. It preserves conversation ID and timestamps for a later `(conversation_id, span time within run start..completion)` join; zero/multiple future matches remain unresolved and no run attribution occurs in L1.

## Persistence ordering

For every collector:

1. Fetch through the read-only helper.
2. Validate response shape and source identity.
3. Sanitize permitted lifecycle text and match red-line rules where applicable.
4. Build a listed persistence DTO; discard all other source/file fields.
5. Canonicalize/hash transient values.
6. Call `write_raw`.
7. Advance collection cursors, committed snapshot hash/ordinal, and OTel offsets only after a successful write. Snapshot pending state is the sole exception: it is durably prepared before the raw write and is cleared only after committed state advances on success.

This order is mandatory and fixture-tested.

## Compatibility boundary

- `multica_run.normalize()` retains its current clean schema and last-write-wins run identity.
- No new normalized row/schema is added for any of the seven new raw families. The registered `copilot_otel` adapter implements the required no-op `normalize() -> 0` interface without emitting normalized output.
- `config.SOURCES` and the repository runner add only `copilot_otel`; `MERGE_SOURCES`, warehouse DDL, L4 SQL, digest source fetchers, and UI are unchanged.
- Existing tests remain active; new tests add old-issue, lifecycle, privacy, empty-usage, idempotency, truncation, and read-only coverage.
