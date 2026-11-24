-- aidata-tier: explore
SELECT judge_run_uid, started_at, finished_at, dry_run, sampled, valid, abstained,
       excluded, status, exclusion_reasons, judge_provider, judge_model,
       rubric_version, runner_version, 0 AS estimated
FROM fact_quality_judge_run
WHERE julianday(replace(replace(started_at, 'T', ' '), 'Z', '')) >= julianday(COALESCE(:since, datetime('now', '-30 days')))
  AND julianday(replace(replace(started_at, 'T', ' '), 'Z', '')) < julianday(COALESCE(:until, date('now', '+1 day')))
ORDER BY started_at DESC
