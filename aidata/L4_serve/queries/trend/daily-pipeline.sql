-- trend/daily-pipeline — per-CST-day multica run outcomes. Buckets on
-- fact_task.cst_day (generated from ts_start; see schema). Feeds pipeline arrow.
SELECT cst_day                          AS day,
       count(*)                         AS runs,
       sum(status = 'completed')        AS completed,
       sum(status = 'cancelled')        AS cancelled,
       sum(status = 'failed')           AS failed
FROM fact_task
WHERE source = 'multica_run' AND ts_start IS NOT NULL
GROUP BY cst_day
ORDER BY day DESC;
