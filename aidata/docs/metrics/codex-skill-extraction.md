# Codex prompt and skill extraction

`adapters/codex_prompts.py` produces two L2 tables in
`L2_normalize/clean/codex_prompts.db`:

- `prompt`: one selected user prompt per session turn. A session file uses one
  deterministic format: `event_msg` `item_completed` `UserMessage` wins,
  otherwise `response_item` user messages win, otherwise legacy
  `event_msg/user_message` is used. Lower-priority formats are not matched or
  merged with the selected format. This prevents one turn represented several
  ways from becoming several prompts.
- `skill_use(day, session_id, ts, call_id, skill)`: tool-call arguments are
  searched only for paths ending in `/<skill>/SKILL.md`. The adapter stores the
  skill name, call id, session and timestamp; it does not store the argument or
  command text. Rows are deduplicated by `(call_id, skill)`.

Skill reads are event counts. Re-reading a skill in a later turn creates
another `skill_use` row and therefore increases the count. For adoption or
reach, prefer `count(distinct session_id)` alongside the event count; use the
event count when measuring read volume. The `skill` value is the final path
component only, so path prefixes and local usernames are not persisted.

Collection keeps the existing per-file byte watermark. Format precedence is
recomputed from all collected raw candidates during normalization, so an
incremental collection has the same result as a full collection of that file.
