-- aidata-tier: explore
SELECT skill,
       COUNT(*) AS eligible_invocations,
       SUM(edit_tool_calls) AS edit_tool_calls,
       SUM(assistant_turn_count) AS assistant_turn_count,
       CAST(SUM(edit_tool_calls) AS REAL) / MAX(1, SUM(assistant_turn_count)) AS normalized_edit_churn,
       AVG(active_duration_sec) AS active_duration_mean_sec,
       MAX(active_duration_sec) AS active_duration_max_sec,
       MAX(end_ts) AS source_as_of,
       0 AS estimated
FROM fact_skill_invocation
WHERE eligible = 1
  AND julianday(replace(replace(start_ts, 'T', ' '), 'Z', '')) >= julianday(COALESCE(:since, datetime('now', '-30 days')))
  AND julianday(replace(replace(start_ts, 'T', ' '), 'Z', '')) < julianday(COALESCE(:until, date('now', '+1 day')))
GROUP BY skill
ORDER BY skill
