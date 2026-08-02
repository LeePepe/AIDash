-- trend/daily-pipeline — per-CST-day multica run outcomes. ts_start is ISO text
-- (not epoch-ms), so bucket with date(ts_start,'+8 hours'). Feeds pipeline arrow.
SELECT date(ts_start, '+8 hours')       AS day,
       count(*)                         AS runs,
       sum(status = 'completed')        AS completed,
       sum(status = 'cancelled')        AS cancelled,
       sum(status = 'failed')           AS failed
FROM fact_task
WHERE source = 'multica_run' AND ts_start IS NOT NULL
GROUP BY day
ORDER BY day DESC;
