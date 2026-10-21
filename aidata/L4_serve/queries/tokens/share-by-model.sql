-- aidata-tier: explore
-- tokens/share-by-model — token union by CST day and model.
-- Grain: one row per CST day and model across the same Raven, Claude Code, and
-- Hermes sources as tokens/daily-by-client. Model labels are the stored model
-- identifiers; NULL models are reported as '(unknown)'. Cache measures remain
-- separate, and share_pct uses input+output only. :day_from and :day_to are
-- inclusive CST dates.
-- aidata-attach: state_db

WITH unioned AS (
    SELECT cst_day, COALESCE(model_canon, model, '(unknown)') AS model,
           COALESCE(input_tokens, 0) AS input_tokens,
           COALESCE(output_tokens, 0) AS output_tokens,
           COALESCE(cache_read, 0) AS cache_read,
           COALESCE(cache_write, 0) AS cache_write
    FROM fact_request
    WHERE client IN ('multica-agent-sdk', 'codex_exec', 'codex-tui')
      AND (:day_from IS NULL OR cst_day >= :day_from)
      AND (:day_to IS NULL OR cst_day <= :day_to)

    UNION ALL

    SELECT cst_day, COALESCE(model, '(unknown)'),
           COALESCE(input_tokens, 0), COALESCE(output_tokens, 0),
           COALESCE(cache_read, 0), COALESCE(cache_creation, 0)
    FROM fact_turn
    WHERE role = 'assistant'
      AND (:day_from IS NULL OR cst_day >= :day_from)
      AND (:day_to IS NULL OR cst_day <= :day_to)

    UNION ALL

    SELECT date(started_at, 'unixepoch', '+8 hours'), COALESCE(model, '(unknown)'),
           COALESCE(input_tokens, 0), COALESCE(output_tokens, 0),
           COALESCE(cache_read_tokens, 0), COALESCE(cache_write_tokens, 0)
    FROM state_db.session
    WHERE (:day_from IS NULL OR date(started_at, 'unixepoch', '+8 hours') >= :day_from)
      AND (:day_to IS NULL OR date(started_at, 'unixepoch', '+8 hours') <= :day_to)
), grouped AS (
    SELECT cst_day, model, sum(input_tokens) AS input, sum(output_tokens) AS output,
           sum(cache_read) AS cache_read, sum(cache_write) AS cache_write
    FROM unioned
    GROUP BY cst_day, model
)
SELECT cst_day, model, input, output, cache_read, cache_write,
       round(100.0 * (input + output) /
             NULLIF(sum(input + output) OVER (PARTITION BY cst_day), 0), 2)
         AS share_pct
FROM grouped
ORDER BY cst_day, model;
