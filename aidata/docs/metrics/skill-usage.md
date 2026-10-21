# Skill usage

`skills/daily` is an exploratory L4 query. It reports one row per CST day,
source, and skill, with the event count (`n`) and, where meaningful, the number
of distinct sessions. It intentionally does not produce a cross-source total:
the source populations have different event grains and attribution rules.

The sources are:

- `claude_attribution`: Claude assistant turns whose attribution metadata names
  a skill.
- `claude_skill_tool`: Claude turns with a `skill_names` list from Skill tool
  calls.
- `codex_skill_read`: Codex skill-read calls, with distinct sessions.
- `claude_slash`: Claude prompt rows classified as `slash_command`; the
  `<command-name>` value is used when present.
- `codex_slash`: Codex slash-command rows. The command name is not retained,
  so the skill is `(unrecorded)`.
- `hermes_skill_view`: Hermes `skill_view` calls. Collection reads only the
  assistant tool-call function, its `name` argument, call id, and timestamp;
  repeated call ids are counted once during normalization.

All day bucketing is fixed UTC+08:00 (CST), independent of the host timezone.
The query is read-only and degrades to no rows when a source has no normalized
data. It is not a union denominator for token or cost metrics.
