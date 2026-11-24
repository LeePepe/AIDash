-- aidata-tier: explore
SELECT date(sampled_at, '+8 hours') AS day,
       skill,
       COUNT(*) AS valid_judgements,
       AVG(overall_score) AS score_mean,
       SUM(pass_flag) AS pass_count,
       MAX(rubric_version) AS rubric_version,
       MAX(judge_model) AS judge_model,
       0 AS estimated
FROM fact_skill_judgement j
JOIN fact_skill_invocation i ON i.invocation_id = j.invocation_id
WHERE j.status = 'valid' AND j.abstained = 0
  AND i.eligible = 1
  AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) >= julianday(COALESCE(:since, datetime('now', '-30 days')))
  AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) < julianday(COALESCE(:until, date('now', '+1 day')))
GROUP BY day, skill
ORDER BY day, skill
