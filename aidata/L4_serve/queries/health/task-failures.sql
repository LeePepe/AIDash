-- aidata-tier: explore
-- health/task-failures — pipeline health: run outcomes, retry pressure, and
-- which agents fail most. Source: fact_task (multica runs carry agent_id).
SELECT
    COALESCE(agent_id, source)                          AS agent_or_source,
    count(*)                                             AS runs,
    sum(status = 'completed')                           AS completed,
    sum(status = 'cancelled')                           AS cancelled,
    sum(status = 'failed')                              AS failed,
    sum(COALESCE(attempt, 1) > 1)                       AS retried,
    round(100.0 * sum(status IN ('failed','cancelled')) / count(*), 1)
                                                        AS bad_pct
FROM fact_task
GROUP BY agent_or_source
ORDER BY runs DESC
LIMIT 20;
