-- aidata-tier: explore
-- aidata-attach: claude_prompts, codex_prompts, hermes_tools
-- skills/daily — skill usage by CST day, source, and skill.
-- Grain: one (day, source, skill) row.  Claude attribution and tool usage are
-- separate populations; Codex call rows are not unioned with slash commands;
-- Hermes is read from its deduplicated L2 skill_day table.  No cross-source
-- total is emitted.  All day filters use the fixed +8h day already materialized
-- by each source.  Empty or missing L2 sources naturally produce no rows.
WITH
claude_attribution AS (
    SELECT cst_day AS day, 'claude_attribution' AS source,
           attribution_skill AS skill, count(*) AS n,
           count(DISTINCT session_id) AS sessions
    FROM fact_turn
    WHERE attribution_skill IS NOT NULL AND attribution_skill != ''
      AND cst_day BETWEEN COALESCE(:day_from, '0000-01-01')
                      AND COALESCE(:day_to, '9999-12-31')
    GROUP BY cst_day, attribution_skill
),
claude_skill_tool AS (
    SELECT t.cst_day AS day, 'claude_skill_tool' AS source,
           json_each.value AS skill, count(*) AS n,
           count(DISTINCT t.session_id) AS sessions
    FROM fact_turn t, json_each(t.skill_names)
    WHERE t.skill_names IS NOT NULL AND json_each.value != ''
      AND t.cst_day BETWEEN COALESCE(:day_from, '0000-01-01')
                        AND COALESCE(:day_to, '9999-12-31')
    GROUP BY t.cst_day, json_each.value
),
codex_skill_read AS (
    SELECT day, 'codex_skill_read' AS source, skill, count(*) AS n,
           count(DISTINCT session_id) AS sessions
    FROM codex_prompts.skill_use
    WHERE day BETWEEN COALESCE(:day_from, '0000-01-01')
                  AND COALESCE(:day_to, '9999-12-31')
    GROUP BY day, skill
),
claude_slash AS (
    SELECT day, 'claude_slash' AS source,
           CASE
             WHEN instr(text_preview, '<command-name>') > 0
              AND instr(text_preview, '</command-name>') >
                  instr(text_preview, '<command-name>') + length('<command-name>')
             THEN substr(
                    text_preview,
                    instr(text_preview, '<command-name>') + length('<command-name>'),
                    instr(text_preview, '</command-name>') -
                    instr(text_preview, '<command-name>') - length('<command-name>')
                  )
             ELSE '(unrecorded)'
           END AS skill,
           count(*) AS n, count(DISTINCT session_id) AS sessions
    FROM claude_prompts.prompt
    WHERE source_kind = 'slash_command'
      AND day BETWEEN COALESCE(:day_from, '0000-01-01')
                  AND COALESCE(:day_to, '9999-12-31')
    GROUP BY day, skill
),
codex_slash AS (
    SELECT day, 'codex_slash' AS source, '(unrecorded)' AS skill,
           count(*) AS n, count(DISTINCT session_id) AS sessions
    FROM codex_prompts.prompt
    WHERE source_kind = 'slash_command'
      AND day BETWEEN COALESCE(:day_from, '0000-01-01')
                  AND COALESCE(:day_to, '9999-12-31')
    GROUP BY day
),
hermes AS (
    SELECT day, 'hermes_skill_view' AS source, skill, n,
           NULL AS sessions
    FROM hermes_tools.skill_day
    WHERE day BETWEEN COALESCE(:day_from, '0000-01-01')
                  AND COALESCE(:day_to, '9999-12-31')
)
SELECT day, source, skill, n, sessions FROM claude_attribution
UNION ALL SELECT day, source, skill, n, sessions FROM claude_skill_tool
UNION ALL SELECT day, source, skill, n, sessions FROM codex_skill_read
UNION ALL SELECT day, source, skill, n, sessions FROM claude_slash
UNION ALL SELECT day, source, skill, n, sessions FROM codex_slash
UNION ALL SELECT day, source, skill, n, sessions FROM hermes
ORDER BY day, source, skill;
