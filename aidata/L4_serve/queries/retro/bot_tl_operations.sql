-- Bot/TL supervision counts with the latest PR monitor heartbeat summary.
-- aidata-tier: explore
WITH latest_heartbeat AS MATERIALIZED (
    SELECT ts, checked_pr_count, stuck_pr_count, repair_queued_count, status
    FROM fact_prmon_heartbeat
    ORDER BY ts DESC, heartbeat_uid DESC
    LIMIT 1
), actions AS (
    SELECT machine_alias, action_kind, status, COUNT(*) AS action_count
    FROM fact_bot_tl_supervision
    GROUP BY machine_alias, action_kind, status
)
SELECT
    actions.machine_alias,
    actions.action_kind,
    actions.status,
    actions.action_count,
    heartbeat.ts AS latest_heartbeat_ts,
    heartbeat.checked_pr_count AS latest_checked_pr_count,
    heartbeat.stuck_pr_count AS latest_stuck_pr_count,
    heartbeat.repair_queued_count AS latest_repair_queued_count,
    heartbeat.status AS latest_heartbeat_status
FROM actions
LEFT JOIN latest_heartbeat AS heartbeat ON 1 = 1
ORDER BY actions.machine_alias, actions.action_kind, actions.status;
