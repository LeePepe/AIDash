-- Bot/TL supervision counts with the latest PR monitor heartbeat summary.
-- aidata-tier: explore
SELECT
    machine_alias,
    action_kind,
    status,
    COUNT(*) AS action_count,
    (SELECT ts FROM fact_prmon_heartbeat ORDER BY ts DESC LIMIT 1) AS latest_heartbeat_ts,
    (SELECT checked_pr_count FROM fact_prmon_heartbeat ORDER BY ts DESC LIMIT 1) AS latest_checked_pr_count,
    (SELECT stuck_pr_count FROM fact_prmon_heartbeat ORDER BY ts DESC LIMIT 1) AS latest_stuck_pr_count,
    (SELECT repair_queued_count FROM fact_prmon_heartbeat ORDER BY ts DESC LIMIT 1) AS latest_repair_queued_count,
    (SELECT status FROM fact_prmon_heartbeat ORDER BY ts DESC LIMIT 1) AS latest_heartbeat_status
FROM fact_bot_tl_supervision
GROUP BY machine_alias, action_kind, status
ORDER BY machine_alias, action_kind, status;
