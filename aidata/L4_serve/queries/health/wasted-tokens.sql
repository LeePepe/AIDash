-- health/wasted-tokens — tokens burned on runs that did not complete.
-- Uses multica_run tokens (the corrected, populated field). Shows each terminal
-- status's token share so cancelled/failed waste is explicit.
WITH totals AS (
  SELECT sum(COALESCE(tokens, 0)) AS all_tokens
  FROM fact_task WHERE source = 'multica_run'
)
SELECT status,
       count(*)                                        AS runs,
       sum(COALESCE(tokens, 0))                        AS tokens,
       round(100.0 * sum(COALESCE(tokens, 0)) /
             (SELECT all_tokens FROM totals), 1)        AS pct_of_tokens
FROM fact_task
WHERE source = 'multica_run'
GROUP BY status
ORDER BY tokens DESC;
