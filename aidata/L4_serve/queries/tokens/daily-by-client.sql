-- aidata-tier: explore
-- tokens/daily-by-client — token union by CST day and source client.
-- Grain: one row per CST day and client label. Sources are fact_request for
-- the selected Raven clients, fact_turn for Claude Code, and state_db.session
-- for Hermes. Raven Claude/curl and Kimi are deliberately excluded.
-- Cache read/write are separate measures and never contribute to input/output.
-- Cost is the sum of priced rows, or NULL when the group has no priced rows.
-- CST windows are inclusive (:day_from) and inclusive (:day_to), matching the
-- verifier's seven-day acceptance window.
-- aidata-attach: state_db

WITH unioned AS (
    SELECT cst_day, client,
           COALESCE(input_tokens, 0) AS input_tokens,
           COALESCE(output_tokens, 0) AS output_tokens,
           COALESCE(cache_read, 0) AS cache_read,
           COALESCE(cache_write, 0) AS cache_write,
           cost_usd,
           CASE WHEN cost_usd IS NULL THEN 1 ELSE 0 END AS unpriced
    FROM fact_request
    WHERE client IN ('multica-agent-sdk', 'codex_exec', 'codex-tui')
      AND (:day_from IS NULL OR cst_day >= :day_from)
      AND (:day_to IS NULL OR cst_day <= :day_to)

    UNION ALL

    SELECT cst_day, 'claude-code',
           COALESCE(input_tokens, 0), COALESCE(output_tokens, 0),
           COALESCE(cache_read, 0), COALESCE(cache_creation, 0),
           cost_usd,
           CASE WHEN cost_usd IS NULL THEN 1 ELSE 0 END
    FROM fact_turn
    WHERE role = 'assistant'
      AND (:day_from IS NULL OR cst_day >= :day_from)
      AND (:day_to IS NULL OR cst_day <= :day_to)

    UNION ALL

    SELECT date(started_at, 'unixepoch', '+8 hours'), 'hermes',
           COALESCE(input_tokens, 0), COALESCE(output_tokens, 0),
           COALESCE(cache_read_tokens, 0), COALESCE(cache_write_tokens, 0),
           COALESCE(actual_cost_usd, estimated_cost_usd),
           CASE WHEN COALESCE(actual_cost_usd, estimated_cost_usd) IS NULL
                THEN 1 ELSE 0 END
    FROM state_db.session
    WHERE (:day_from IS NULL OR date(started_at, 'unixepoch', '+8 hours') >= :day_from)
      AND (:day_to IS NULL OR date(started_at, 'unixepoch', '+8 hours') <= :day_to)
), grouped AS (
    SELECT cst_day, client,
           sum(input_tokens) AS input,
           sum(output_tokens) AS output,
           sum(cache_read) AS cache_read,
           sum(cache_write) AS cache_write,
           CASE WHEN count(cost_usd) > 0 THEN sum(cost_usd) END AS cost_usd,
           sum(unpriced) AS unpriced_rows
    FROM unioned
    GROUP BY cst_day, client
)
SELECT cst_day, client, input, output, cache_read, cache_write, cost_usd,
       unpriced_rows,
       round(100.0 * (input + output) /
             NULLIF(sum(input + output) OVER (PARTITION BY cst_day), 0), 2)
         AS share_pct
FROM grouped
ORDER BY cst_day, client;
