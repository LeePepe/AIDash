-- aidata-tier: explore
SELECT date(j.sampled_at, '+8 hours') AS day,
       j.skill AS skill,
       COUNT(*) AS valid_judgements,
       AVG(j.overall_score) AS score_mean,
       SUM(j.pass_flag) AS pass_count,
       MAX(j.rubric_version) AS rubric_version,
       MAX(j.judge_model) AS judge_model,
       0 AS estimated
FROM fact_skill_judgement j
JOIN fact_skill_invocation i ON i.invocation_id = j.invocation_id
WHERE j.status = 'valid' AND j.abstained = 0
  AND i.eligible = 1
  AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) >= julianday(COALESCE(:since, datetime('now', '-30 days')))
  AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) < julianday(COALESCE(:until, date('now', '+1 day')))
GROUP BY day, j.skill
ORDER BY day, j.skill
