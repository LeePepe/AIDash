-- aidata-tier: explore
SELECT
    repo_key,
    workflow_category,
    event_trigger,
    COUNT(*) AS run_count,
    SUM(CASE WHEN conclusion = 'success' THEN 1 ELSE 0 END) AS success_count,
    SUM(CASE WHEN conclusion = 'failure' THEN 1 ELSE 0 END) AS failure_count,
    SUM(CASE WHEN conclusion IN ('cancelled', 'timed_out') THEN 1 ELSE 0 END) AS cancelled_or_timeout_count,
    ROUND(
        1.0 * SUM(CASE WHEN conclusion = 'success' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN conclusion IN ('success', 'failure') THEN 1 ELSE 0 END), 0),
        4
    ) AS pass_rate,
    COALESCE((
        SELECT AVG(j.queue_wait_sec)
        FROM fact_ci_job_run AS j
        WHERE j.repo_key = r.repo_key
          AND j.run_id IN (
              SELECT run_id FROM fact_ci_workflow_run
              WHERE repo_key = r.repo_key
                AND workflow_category = r.workflow_category
                AND event_trigger IS r.event_trigger
          )
    ), 0) AS avg_queue_wait_sec,
    COALESCE((
        SELECT COUNT(*)
        FROM fact_ci_job_run AS j
        WHERE j.repo_key = r.repo_key
          AND j.failure_category LIKE 'config_drift_%'
          AND j.run_id IN (
              SELECT run_id FROM fact_ci_workflow_run
              WHERE repo_key = r.repo_key
                AND workflow_category = r.workflow_category
                AND event_trigger IS r.event_trigger
          )
    ), 0) AS config_noise_job_count
FROM fact_ci_workflow_run AS r
GROUP BY repo_key, workflow_category, event_trigger
ORDER BY repo_key, workflow_category, event_trigger;
