-- aidata-tier: explore
WITH current_valid AS (
    SELECT j.judgement_uid, j.invocation_id, j.skill, j.overall_score,
           j.pass_flag, j.rubric_version, j.judge_model, j.sampled_at
    FROM fact_skill_judgement j
    JOIN fact_skill_invocation i ON i.invocation_id = j.invocation_id
    WHERE j.status = 'valid' AND j.abstained = 0
      AND i.eligible = 1
      AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) >= julianday(COALESCE(:since, datetime('now', '-30 days')))
      AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) < julianday(COALESCE(:until, date('now', '+1 day')))
)
SELECT r.skill,
       COUNT(DISTINCT j.invocation_id) AS valid_judgements,
       AVG(j.overall_score) AS score_mean,
       MIN(j.overall_score) AS score_min,
       MAX(j.overall_score) AS score_max,
       COUNT(DISTINCT CASE WHEN j.pass_flag = 1 THEN j.invocation_id END) AS pass_count,
       CASE WHEN COUNT(DISTINCT j.invocation_id) > 0
            THEN CAST(COUNT(DISTINCT CASE WHEN j.pass_flag = 1 THEN j.invocation_id END) AS REAL) / COUNT(DISTINCT j.invocation_id) END AS pass_rate,
       MAX(j.rubric_version) AS rubric_version,
       MAX(j.judge_model) AS judge_model,
       MAX(j.sampled_at) AS source_as_of,
       0 AS estimated
FROM dim_skill_registry r
LEFT JOIN current_valid j ON j.skill = r.skill
WHERE r.active = 1
GROUP BY r.skill
ORDER BY r.skill
