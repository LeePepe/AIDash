-- aidata-tier: explore
-- tokens/automated-share — automated versus interactive token share.
-- Grain: one row per CST day and class. Raven classification uses client rules;
-- Claude turns use the latest same-session prompt at or before the turn, with
-- prompt_id ascending tie-break (or the session's earliest prompt if none is
-- before the turn); cwd_prefix outranks client/originator, then interactive.
-- Raven codex-tui cannot be session-linked and therefore remains interactive.
-- The denominator and share_pct use input+output only; cache is separate.
-- aidata-attach: claude_prompts state_db

WITH raven AS (
    SELECT cst_day, 'raven' AS source,
           CASE WHEN EXISTS (
               SELECT 1 FROM dim_automation_rule r
               WHERE r.kind IN ('client', 'originator')
                 AND r.match = f.client AND r.class = 'automated'
           ) THEN 'automated' ELSE 'interactive' END AS class,
           COALESCE(input_tokens, 0) AS input_tokens,
           COALESCE(output_tokens, 0) AS output_tokens,
           COALESCE(cache_read, 0) AS cache_read,
           COALESCE(cache_write, 0) AS cache_write
    FROM fact_request f
    WHERE client IN ('multica-agent-sdk', 'codex_exec', 'codex-tui')
      AND (:day_from IS NULL OR cst_day >= :day_from)
      AND (:day_to IS NULL OR cst_day <= :day_to)
), claude_base AS (
    SELECT f.*,
           CAST(strftime('%s', f.ts) AS REAL) +
             round((julianday(f.ts) -
                    julianday(strftime('%Y-%m-%dT%H:%M:%SZ', f.ts))) *
                   86400.0, 6) AS turn_epoch
    FROM fact_turn f
    WHERE f.role = 'assistant'
      AND (:day_from IS NULL OR f.cst_day >= :day_from)
      AND (:day_to IS NULL OR f.cst_day <= :day_to)
), claude AS (
    SELECT c.cst_day, 'claude-code' AS source,
           CASE WHEN EXISTS (
               SELECT 1 FROM dim_automation_rule r
               WHERE r.kind = 'cwd_prefix'
                 AND p.cwd LIKE r.match || '%'
                 AND r.class = 'automated'
           ) THEN 'automated'
           WHEN EXISTS (
               SELECT 1 FROM dim_automation_rule r
               WHERE r.kind IN ('client', 'originator')
                 AND r.match = 'claude-code' AND r.class = 'automated'
           ) THEN 'automated'
           ELSE 'interactive' END AS class,
           COALESCE(c.input_tokens, 0) AS input_tokens,
           COALESCE(c.output_tokens, 0) AS output_tokens,
           COALESCE(c.cache_read, 0) AS cache_read,
           COALESCE(c.cache_creation, 0) AS cache_write
    FROM claude_base c
    LEFT JOIN claude_prompts.prompt p ON p.prompt_id = (
        COALESCE(
            (SELECT q.prompt_id
             FROM claude_prompts.prompt q
             WHERE q.session_id = c.session_id
               AND q.ts <= c.turn_epoch
             ORDER BY q.ts DESC, q.prompt_id DESC
             LIMIT 1),
            (SELECT q.prompt_id
             FROM claude_prompts.prompt q
             WHERE q.session_id = c.session_id
             ORDER BY q.ts ASC, q.prompt_id ASC
             LIMIT 1)
        )
    )
), hermes AS (
    SELECT date(started_at, 'unixepoch', '+8 hours') AS cst_day,
           'hermes' AS source, CASE WHEN is_automated = 1
                                    THEN 'automated' ELSE 'interactive' END AS class,
           COALESCE(input_tokens, 0) AS input_tokens,
           COALESCE(output_tokens, 0) AS output_tokens,
           COALESCE(cache_read_tokens, 0) AS cache_read,
           COALESCE(cache_write_tokens, 0) AS cache_write
    FROM state_db.session
    WHERE (:day_from IS NULL OR date(started_at, 'unixepoch', '+8 hours') >= :day_from)
      AND (:day_to IS NULL OR date(started_at, 'unixepoch', '+8 hours') <= :day_to)
), unioned AS (
    SELECT * FROM raven UNION ALL SELECT * FROM claude UNION ALL SELECT * FROM hermes
), grouped AS (
    SELECT cst_day, class, sum(input_tokens) AS input, sum(output_tokens) AS output,
           sum(cache_read) AS cache_read, sum(cache_write) AS cache_write
    FROM unioned GROUP BY cst_day, class
)
SELECT cst_day, class, input, output, cache_read, cache_write,
       round(100.0 * (input + output) /
             NULLIF(sum(input + output) OVER (PARTITION BY cst_day), 0), 2)
         AS share_pct
FROM grouped ORDER BY cst_day, class;
