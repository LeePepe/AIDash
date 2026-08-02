-- health/failure-rootcause — aggregate multica_run failures by root cause.
-- Source: fact_task.error (wired through L3 from multica_run clean). Additive
-- companion to task-failures.sql (kept untouched — additive, doesn't alter it);
-- this query answers "WHY runs fail", not just "how many". (task-failures has no
-- L5 consumer today; it's an ad-hoc L4 query, not a digest contract.)
--
-- error text is free-form and codex errors carry multi-line stacktraces (same
-- class, different text), so we collapse to a stable category by prefix/LIKE.
-- pct is share of all classified failures (no window functions — serve.py runs on
-- stdlib sqlite; total comes from a scalar subquery).
SELECT
    CASE
        WHEN error LIKE 'runtime went offline%'         THEN 'runtime-offline'
        WHEN error LIKE 'task expired%'                 THEN 'queue-timeout'
        WHEN error LIKE 'codex initialize failed%'      THEN 'codex-init-fail'
        WHEN error LIKE 'daemon restarted%'             THEN 'daemon-restart'
        WHEN error LIKE '%model_not_supported%'
          OR error LIKE '%model_not_available%'         THEN 'model-config'
        WHEN error LIKE 'Missing environment%'          THEN 'env-missing'
        ELSE 'other'
    END                                                  AS root_cause,
    count(*)                                             AS runs,
    round(100.0 * count(*) / (
        SELECT count(*) FROM fact_task WHERE error IS NOT NULL AND error != ''
    ), 1)                                                AS pct
FROM fact_task
WHERE error IS NOT NULL AND error != ''
GROUP BY root_cause
ORDER BY runs DESC;
