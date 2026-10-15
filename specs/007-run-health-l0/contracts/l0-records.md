# Contract: Run-Health L0 Records

This contract fixes the persistence boundary for implementation. Fields not listed as allowed must be discarded before `write_raw`. Optional means source absence is represented by omission or null according to the existing raw convention, never by an invented value.

## Global rules

1. All Multica commands are read-only and must pass the prefix allowlist before subprocess launch.
2. `observed_at` is an RFC 3339 UTC collection timestamp.
3. Every derived hash is 64 lowercase hexadecimal characters from SHA-256.
4. String lengths are UTF-8 byte counts. Structured values use sorted-key compact JSON before hashing/length.
5. Missing values stay missing. In particular, empty usage is not zero usage and an agent model is not a run model.
6. New message/tool records contain no raw body, input, output, preview, email address, local path, or whole CLI payload.
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
  "failure_reason": null,
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

`usage: []` is allowed and must stay empty. `model` is populated only when this run's source usage identifies it. `trigger_summary` is retained only as an existing compatibility field and passes through the repository's existing raw redaction; no new message body or whole task object may be placed there.

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

Logical identity: `(agent_id, config_hash)`.

Allowed fields: `agent_id`, `workspace_id`, `model`, `thinking_level`, `runtime_id`, `max_concurrent_tasks`, `config_hash`, `observed_at`.

The source agent name, instructions, email, invocation policy, or other `agent get` fields are forbidden. An unchanged `config_hash` writes no record.

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

## Persistence ordering

For every collector:

1. Fetch through the read-only helper.
2. Validate response shape and source identity.
3. Match red-line rules where applicable.
4. Build a listed persistence DTO; discard all other source fields.
5. Canonicalize/hash transient values.
6. Call `write_raw`.
7. Advance cursor, snapshot hash, or pending state only after a successful write.

This order is mandatory and fixture-tested.

## Compatibility boundary

- `multica_run.normalize()` retains its current clean schema and last-write-wins run identity.
- No normalizer is added for the six new raw families.
- `config.SOURCES`, `MERGE_SOURCES`, the cron runner source list, warehouse DDL, L4 SQL, digest source fetchers, and UI are unchanged.
- Existing tests remain active; new tests add old-issue, lifecycle, privacy, empty-usage, idempotency, truncation, and read-only coverage.
