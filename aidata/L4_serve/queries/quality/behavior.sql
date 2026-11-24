-- aidata-tier: explore
-- One row per registered skill; missing eligible evidence remains NULL.
WITH eligible AS (
    SELECT i.skill,
           COUNT(DISTINCT i.invocation_id) AS eligible_invocations,
           COUNT(DISTINCT CASE WHEN c.correction_class NOT IN ('none') THEN i.invocation_id END) AS correction_count,
           COUNT(DISTINCT CASE WHEN i.max_tokens = 0 THEN i.invocation_id END) AS satisfaction_invocations,
           COUNT(DISTINCT CASE WHEN i.max_tokens = 0 AND c.correction_class NOT IN ('none') THEN i.invocation_id END) AS satisfaction_correction_count,
           COUNT(DISTINCT CASE WHEN i.max_tokens = 1 THEN i.invocation_id END) AS max_tokens_invocations,
           SUM(i.edit_tool_calls) AS edit_tool_calls,
           SUM(i.assistant_turn_count) AS assistant_turn_count,
           AVG(i.active_duration_sec) AS active_duration_mean_sec
    FROM fact_skill_invocation i
    LEFT JOIN fact_skill_correction c ON c.invocation_id = i.invocation_id
    WHERE i.eligible = 1
      AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) >= julianday(COALESCE(:since, datetime('now', '-30 days')))
      AND julianday(replace(replace(i.start_ts, 'T', ' '), 'Z', '')) < julianday(COALESCE(:until, date('now', '+1 day')))
    GROUP BY i.skill
)
SELECT r.skill,
       COALESCE(e.eligible_invocations, 0) AS eligible_invocations,
       e.correction_count,
       e.max_tokens_invocations,
       e.satisfaction_invocations,
       CASE WHEN e.satisfaction_invocations > 0
            THEN CAST(e.satisfaction_invocations - e.satisfaction_correction_count AS REAL) / e.satisfaction_invocations END AS first_pass_satisfaction_rate,
       CASE WHEN e.satisfaction_invocations > 0
            THEN CAST(e.satisfaction_correction_count AS REAL) / e.satisfaction_invocations END AS implicit_correction_rate,
       e.edit_tool_calls,
       e.assistant_turn_count,
       CASE WHEN e.assistant_turn_count > 0
            THEN CAST(e.edit_tool_calls AS REAL) / e.assistant_turn_count END AS normalized_edit_churn,
       e.active_duration_mean_sec,
       CASE WHEN e.eligible_invocations IS NULL THEN 'unknown' ELSE 'covered' END AS coverage_status,
       0 AS estimated
FROM dim_skill_registry r
LEFT JOIN eligible e ON e.skill = r.skill
WHERE r.active = 1
ORDER BY r.skill
