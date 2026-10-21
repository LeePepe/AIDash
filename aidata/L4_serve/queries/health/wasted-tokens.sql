-- aidata-tier: explore
-- health/wasted-tokens — tokens burned on runs that did not complete.
-- unavailable: fact_task.tokens is issue-wide, merge.py:116. It is not
-- run-wide, so it cannot
-- be attributed to a terminal status without inventing a split. Keep the
-- token-shaped output columns for the explore query's stable contract, but
-- return NULL rather than double-counting or fabricating attribution.
SELECT status,
       count(*)                                        AS runs,
       CAST(NULL AS INTEGER)                            AS tokens,
       CAST(NULL AS REAL)                               AS pct_of_tokens
FROM fact_task
WHERE source = 'multica_run'
GROUP BY status
ORDER BY runs DESC, status ASC;
