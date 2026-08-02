-- health/rework-loops — issues showing rework: multiple runs, especially a
-- cancelled run before a completed one. Run count per issue is the proxy.
SELECT i.identifier,
       i.issue_number,
       count(t.task_id)                       AS runs,
       sum(t.status = 'cancelled')            AS cancelled_runs,
       sum(t.status = 'completed')            AS completed_runs,
       CASE WHEN sum(t.status = 'cancelled') > 0
             AND sum(t.status = 'completed') > 0
            THEN 1 ELSE 0 END                 AS had_rework_loop
FROM fact_issue i
JOIN fact_task t
  ON t.issue_id = i.issue_id AND t.source = 'multica_run'
GROUP BY i.issue_id
HAVING runs > 1
ORDER BY runs DESC;
