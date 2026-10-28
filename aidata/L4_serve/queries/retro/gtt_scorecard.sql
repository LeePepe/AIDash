-- aidata-tier: explore
SELECT
    COALESCE(g.goal_id, 'unknown') AS goal_id,
    COALESCE(g.derived_actual_status, 'unknown') AS actual_status,
    COALESCE(g.static_header_status, 'unknown') AS declared_status,
    COALESCE(g.is_status_drifted, 0) AS status_drifted,
    COALESCE(g.task_total_count, 0) AS task_total_count,
    COALESCE(g.task_done_count, 0) AS task_done_count,
    COALESCE(g.task_blocked_count, 0) AS task_blocked_count,
    COALESCE(e.event_count, 0) AS event_count,
    COALESCE(r.receipt_count, 0) AS receipt_count
FROM dim_goal AS g
LEFT JOIN (
    SELECT goal_uid, COUNT(*) AS event_count
    FROM fact_gtt_event
    GROUP BY goal_uid
) AS e ON e.goal_uid = g.goal_uid
LEFT JOIN (
    SELECT goal_uid, COUNT(*) AS receipt_count
    FROM fact_gtt_task_run
    GROUP BY goal_uid
) AS r ON r.goal_uid = g.goal_uid
ORDER BY status_drifted DESC, goal_id;
