-- aidata-tier: explore
WITH eligible AS (
    SELECT skill, COUNT(*) AS eligible_invocations
    FROM fact_skill_invocation
    WHERE eligible = 1
      AND julianday(replace(replace(start_ts, 'T', ' '), 'Z', '')) >= julianday(COALESCE(:since, datetime('now', '-30 days')))
      AND julianday(replace(replace(start_ts, 'T', ' '), 'Z', '')) < julianday(COALESCE(:until, date('now', '+1 day')))
    GROUP BY skill
), judged AS (
    SELECT i.skill, COUNT(DISTINCT j.invocation_id) AS valid_judgements
    FROM fact_skill_judgement j
    JOIN fact_skill_invocation i ON i.invocation_id = j.invocation_id
    WHERE i.eligible = 1
      AND j.status = 'valid' AND j.abstained = 0
      AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) >= julianday(COALESCE(:since, datetime('now', '-30 days')))
      AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) < julianday(COALESCE(:until, date('now', '+1 day')))
    GROUP BY i.skill
)
SELECT r.skill,
       CASE WHEN e.eligible_invocations > 0 THEN 1 ELSE 0 END AS eligible,
       COALESCE(e.eligible_invocations, 0) AS eligible_invocations,
       CASE WHEN COALESCE(j.valid_judgements, 0) > 0 THEN 1 ELSE 0 END AS judged,
       COALESCE(j.valid_judgements, 0) AS valid_judgements,
       CASE WHEN e.eligible_invocations IS NULL THEN 'unknown'
            WHEN COALESCE(j.valid_judgements, 0) > 0 THEN 'covered'
            ELSE 'partial' END AS coverage_status,
       CASE WHEN e.eligible_invocations > 0
            THEN CAST(COALESCE(j.valid_judgements, 0) AS REAL) / e.eligible_invocations * 100 END AS coverage_pct,
       0 AS estimated
FROM dim_skill_registry r
LEFT JOIN eligible e ON e.skill = r.skill
LEFT JOIN judged j ON j.skill = r.skill
WHERE r.active = 1
ORDER BY r.skill
