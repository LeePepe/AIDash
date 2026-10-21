# Codex prompt and skill extraction

`adapters/codex_prompts.py` produces two L2 tables in
`L2_normalize/clean/codex_prompts.db`:

- `prompt`: every distinct prompt from one winning format per session file.
  Format precedence is deterministic: `event_msg` `item_completed`
  `UserMessage` wins; otherwise `response_item` user messages win; otherwise
  legacy `event_msg/user_message` is used. There is no cross-format matching
  or merging, and every distinct prompt in the winning format is kept,
  including prompts that share a turn id. Collection advances by each session
  file's byte cursor; normalization recomputes the winning format from all
  collected raw candidates, so incremental collection has the same result as
  a full collection of that file.
- `skill_use(day, session_id, ts, call_id, skill)`: tool-call arguments are
  searched only for paths ending in `/<skill>/SKILL.md`. The adapter stores the
  skill name, call id, session and timestamp; it does not store the argument or
  command text. Rows are deduplicated by `(call_id, skill)`.

Skill reads are event counts. Re-reading a skill in a later turn creates
another `skill_use` row and therefore increases the count. For adoption or
reach, prefer `count(distinct session_id)` alongside the event count; use the
event count when measuring read volume. The `skill` value is the final path
component only, so path prefixes and local usernames are not persisted.
