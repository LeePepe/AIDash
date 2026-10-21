# Token union

The L4 token queries provide a read-only, additive union for the three sources
that have comparable usage measures:

| Source | Query label | Grain |
| --- | --- | --- |
| Raven (`fact_request`) | stored client / model | one API request |
| Claude Code (`fact_turn`) | `claude-code` / stored model | one assistant turn |
| Hermes (`state_db.session`) | `hermes` / stored model | one session |

Raven clients included in v1 are `multica-agent-sdk`, `codex_exec`, and
`codex-tui`. Raven `Claude` and `curl` rows are excluded because their usage
overlaps the Claude transcript or is not part of this union. Kimi and
`fact_task.tokens` are also excluded. A row is bucketed by its stored or
source-defined CST day (`+8 hours`); query parameters `day_from` and `day_to`
are inclusive dates.

Version 1 is token-only; cost is out of scope by Owner decision (2026-10-21).
Each query reports `input`, `output`, `cache_read`, and `cache_write` as
separate measures. Cache read/write never enter the input/output denominator or
`share_pct`. Shares are input+output shares within the same CST day and
therefore sum to 100% when the day has usage.

`tokens/automated-share` applies one class per row. A matching `cwd_prefix`
rule wins first; otherwise a matching `client`/`originator` rule wins; the
default is `interactive`. Claude turns are linked to the latest prompt in the
same session whose prompt timestamp is not later than the turn. Equal prompt
timestamps use the highest `prompt_id`; if no prompt precedes the turn, the
earliest prompt is used (lowest timestamp, then lowest `prompt_id`). Raven
`codex-tui` cannot be session-linked and follows its interactive client rule.
