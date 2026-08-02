-- aidata-tier: explore
-- health/agent-scorecard — reliability + speed + token burn per multica agent.
-- Cycle time from ISO ts_start/ts_end (julianday diff -> seconds). Only
-- multica_run rows carry agent_id; claude_job rows are excluded.
SELECT agent_id,
       count(*)                                              AS runs,
       sum(status = 'completed')                             AS completed,
       sum(status = 'cancelled')                             AS cancelled,
       sum(status = 'failed')                                AS failed,
       round(100.0 * sum(status = 'completed') / count(*), 1) AS completion_pct,
       round(avg((julianday(ts_end) - julianday(ts_start)) * 86400.0), 0)
                                                             AS avg_seconds,
       round(avg(tokens), 0)                                 AS avg_tokens
FROM fact_task
WHERE source = 'multica_run' AND agent_id IS NOT NULL
GROUP BY agent_id
ORDER BY completion_pct ASC;
