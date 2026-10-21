-- aidata-tier: explore
-- aidata-attach: claude_prompts state_db
-- tokens/by-project — grain: one CST day x common project key.
-- Sources: selected raven clients, Claude fact_turn joined to prompt.repo,
-- and Hermes state_db.session. Raven rows are explicitly unattributed.
-- Claude allocation: latest same-session prompt with prompt.ts <= turn.ts;
-- otherwise earliest prompt. Equal timestamps use prompt_id DESC/ASC.
-- Missing/non-git paths and missing prompt matches are (unresolved). Every row
-- remains in the share denominator; cache tokens are not in that denominator.

WITH
claude_turn_repo AS (
    SELECT t.cst_day,
           COALESCE(
               (SELECT p.repo FROM claude_prompts.prompt p
                WHERE p.session_id = t.session_id
                  AND p.ts <= (julianday(t.ts) - 2440587.5) * 86400.0
                ORDER BY p.ts DESC, p.prompt_id DESC LIMIT 1),
               (SELECT p.repo FROM claude_prompts.prompt p
                WHERE p.session_id = t.session_id
                ORDER BY p.ts ASC, p.prompt_id ASC LIMIT 1),
               '(unresolved)') AS repo,
           t.input_tokens AS input, t.output_tokens AS output,
           t.cache_read AS cache_read, t.cache_creation AS cache_write,
           COALESCE(t.cost_usd, 0) AS cost_usd
    FROM fact_turn t
),
raven AS (
    SELECT cst_day, '(unattributed)' AS repo,
           input_tokens AS input, output_tokens AS output,
           cache_read, cache_write, COALESCE(cost_usd, 0) AS cost_usd
    FROM fact_request
    WHERE client IN ('multica-agent-sdk', 'codex_exec', 'codex-tui')
),
hermes AS (
    SELECT date(started_at, 'unixepoch', '+8 hours') AS cst_day,
           COALESCE(repo, '(unresolved)') AS repo,
           input_tokens AS input, output_tokens AS output,
           cache_read_tokens AS cache_read, cache_write_tokens AS cache_write,
           COALESCE(actual_cost_usd, estimated_cost_usd, 0) AS cost_usd
    FROM state_db.session
),
all_rows AS (
    SELECT * FROM raven
    UNION ALL SELECT * FROM claude_turn_repo
    UNION ALL SELECT * FROM hermes
),
grouped AS (
    SELECT cst_day, repo, SUM(COALESCE(input, 0)) AS input,
           SUM(COALESCE(output, 0)) AS output,
           SUM(COALESCE(cache_read, 0)) AS cache_read,
           SUM(COALESCE(cache_write, 0)) AS cache_write,
           SUM(cost_usd) AS cost_usd
    FROM all_rows
    WHERE (:day_from IS NULL OR cst_day >= :day_from)
      AND (:day_to IS NULL OR cst_day <= :day_to)
    GROUP BY cst_day, repo
),
day_totals AS (
    SELECT cst_day, SUM(input + output) AS total_io
    FROM grouped GROUP BY cst_day
)
SELECT g.cst_day, g.repo, g.input, g.output, g.cache_read, g.cache_write,
       round(g.cost_usd, 6) AS cost_usd,
       round(100.0 * (g.input + g.output) / NULLIF(d.total_io, 0), 4)
           AS share_pct
FROM grouped g JOIN day_totals d ON d.cst_day = g.cst_day
ORDER BY g.cst_day, g.repo;
