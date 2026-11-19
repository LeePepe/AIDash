-- aidata-tier: explore
-- Daily CST (14-day) agent efficiency series: completed goals/tasks, review
-- round distribution (r1/r2/r3+), median/p90 task duration, blockers, and tokens.
WITH RECURSIVE anchor AS (
    SELECT COALESCE(
        :until_day,
        (SELECT MAX(cst_day) FROM fact_gtt_event WHERE cst_day IS NOT NULL),
        (SELECT MAX(cst_day) FROM fact_request WHERE cst_day IS NOT NULL),
        date('now', '+8 hours')
    ) AS end_day
),
days(idx, cst_day) AS (
    SELECT 0, date(end_day, '-13 days') FROM anchor
    UNION ALL
    SELECT idx + 1, date(cst_day, '+1 day')
    FROM days
    WHERE idx < 13
),
daily_events AS (
    SELECT
        cst_day,
        COUNT(DISTINCT CASE WHEN evt_type IN ('GOAL_DONE', 'PR_MERGED') THEN goal_uid END) AS goals_completed,
        COUNT(DISTINCT CASE WHEN evt_type IN ('DONE', 'TASK_DONE', 'REVIEW_PASS') AND task_id IS NOT NULL AND task_id != '' THEN goal_uid || ':' || task_id END) AS tasks_completed,
        SUM(CASE WHEN evt_type IN ('TASK_BLOCKED', 'INPUT_BLOCKED', 'NEED_GO', 'NEED_OWNER_DECISION', 'REVIEW_FAIL') THEN 1 ELSE 0 END) AS blocked_events
    FROM fact_gtt_event
    WHERE cst_day IS NOT NULL
    GROUP BY cst_day
),
task_completion_days AS (
    SELECT
        goal_uid,
        task_id AS task_key,
        MAX(CASE WHEN evt_type IN ('DONE', 'TASK_DONE', 'REVIEW_PASS', 'PR_MERGED', 'GOAL_DONE') THEN cst_day END) AS done_day,
        MIN(CASE WHEN evt_type IN ('READY', 'DISPATCHED', 'DISPATCH', 'START') THEN julianday(ts) END) AS start_jd,
        MAX(CASE WHEN evt_type IN ('DONE', 'TASK_DONE', 'REVIEW_PASS', 'PR_MERGED', 'GOAL_DONE') THEN julianday(ts) END) AS end_jd
    FROM fact_gtt_event
    WHERE task_id IS NOT NULL AND task_id != ''
    GROUP BY goal_uid, task_id
),
receipt_task_rounds AS (
    SELECT
        r.goal_uid,
        r.task_id AS task_key,
        COALESCE(r.cst_day, tcd.done_day) AS bucket_day,
        MAX(CASE WHEN r.round_no IS NULL OR r.round_no < 1 OR r.round_no = 10 THEN 1 ELSE r.round_no END) AS max_round,
        MAX(CASE WHEN (r.round_no = 1 OR r.round_no = 10) AND (UPPER(COALESCE(r.v5_verdict, '')) = 'FAIL' OR LOWER(COALESCE(r.status, '')) = 'failed') THEN 1 ELSE 0 END) AS had_r1_fail
    FROM fact_gtt_task_run AS r
    LEFT JOIN task_completion_days AS tcd
      ON tcd.goal_uid = r.goal_uid AND tcd.task_key = r.task_id
    WHERE r.task_id IS NOT NULL AND r.task_id != ''
    GROUP BY r.goal_uid, r.task_id, COALESCE(r.cst_day, tcd.done_day)
),
event_review_rounds AS (
    SELECT
        goal_uid,
        task_id AS task_key,
        MAX(cst_day) AS bucket_day,
        1 + SUM(CASE WHEN evt_type IN ('REVIEW_FAIL', 'CHANGES_REQUESTED', 'CHANGE_REQUEST') THEN 1 ELSE 0 END) AS inferred_round,
        MAX(CASE WHEN evt_type IN ('REVIEW_FAIL', 'CHANGES_REQUESTED', 'CHANGE_REQUEST') THEN 1 ELSE 0 END) AS had_fail
    FROM fact_gtt_event
    WHERE task_id IS NOT NULL AND task_id != '' AND cst_day IS NOT NULL
      AND evt_type IN ('DONE', 'TASK_DONE', 'REVIEW_PASS', 'REVIEW_FAIL', 'CHANGES_REQUESTED', 'CHANGE_REQUEST')
    GROUP BY goal_uid, task_id
),
combined_daily_tasks AS (
    SELECT
        COALESCE(rtr.bucket_day, err.bucket_day) AS cst_day,
        COALESCE(rtr.goal_uid, err.goal_uid) AS goal_uid,
        COALESCE(rtr.task_key, err.task_key) AS task_key,
        MAX(COALESCE(rtr.max_round, 1), COALESCE(err.inferred_round, 1)) AS final_round,
        MAX(COALESCE(rtr.had_r1_fail, 0), COALESCE(err.had_fail, 0)) AS had_fail
    FROM event_review_rounds AS err
    LEFT JOIN receipt_task_rounds AS rtr
      ON rtr.goal_uid = err.goal_uid AND rtr.task_key = err.task_key
    UNION ALL
    SELECT
        rtr.bucket_day AS cst_day,
        rtr.goal_uid,
        rtr.task_key,
        rtr.max_round AS final_round,
        rtr.had_r1_fail AS had_fail
    FROM receipt_task_rounds AS rtr
    WHERE NOT EXISTS (
        SELECT 1 FROM event_review_rounds AS err
        WHERE err.goal_uid = rtr.goal_uid AND err.task_key = rtr.task_key
    )
),
daily_rounds AS (
    SELECT
        cst_day,
        SUM(CASE WHEN final_round = 1 AND had_fail = 0 THEN 1 ELSE 0 END) AS r1_count,
        SUM(CASE WHEN final_round = 2 OR (final_round = 1 AND had_fail = 1) THEN 1 ELSE 0 END) AS r2_count,
        SUM(CASE WHEN final_round >= 3 THEN 1 ELSE 0 END) AS r3_plus_count,
        COUNT(*) AS evaluated_tasks
    FROM combined_daily_tasks
    WHERE cst_day IS NOT NULL
    GROUP BY cst_day
),
daily_durations_ranked AS (
    SELECT
        done_day AS cst_day,
        (end_jd - start_jd) * 86400.0 AS duration_sec,
        ROW_NUMBER() OVER (PARTITION BY done_day ORDER BY (end_jd - start_jd) * 86400.0 ASC) AS rn,
        COUNT(*) OVER (PARTITION BY done_day) AS cnt
    FROM task_completion_days
    WHERE done_day IS NOT NULL
      AND start_jd IS NOT NULL
      AND end_jd IS NOT NULL
      AND end_jd > start_jd
      AND (end_jd - start_jd) * 86400.0 BETWEEN 1.0 AND 86400.0
),
daily_duration_percentiles AS (
    SELECT
        cst_day,
        ROUND(AVG(CASE WHEN rn IN ((cnt + 1) / 2, (cnt + 2) / 2) THEN duration_sec END), 1) AS median_duration_sec,
        ROUND(MAX(CASE WHEN rn = MAX(1, CAST((cnt * 90 + 99) / 100 AS INTEGER)) THEN duration_sec END), 1) AS p90_duration_sec
    FROM daily_durations_ranked
    GROUP BY cst_day
),
daily_tokens AS (
    SELECT
        cst_day,
        SUM(CASE
            WHEN client LIKE 'claude%' OR client LIKE 'codex-tui%' OR client LIKE 'codex_cli%' OR model_canon = 'microsoft-decision-1'
            THEN COALESCE(total_tokens, COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0) + COALESCE(cache_read, 0) + COALESCE(cache_write, 0))
            ELSE 0
        END) AS steering_tokens,
        SUM(CASE
            WHEN NOT (client LIKE 'claude%' OR client LIKE 'codex-tui%' OR client LIKE 'codex_cli%' OR model_canon = 'microsoft-decision-1')
            THEN COALESCE(total_tokens, COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0) + COALESCE(cache_read, 0) + COALESCE(cache_write, 0))
            ELSE 0
        END) AS coding_tokens,
        SUM(COALESCE(total_tokens, COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0) + COALESCE(cache_read, 0) + COALESCE(cache_write, 0))) AS total_tokens
    FROM fact_request
    WHERE cst_day IS NOT NULL
    GROUP BY cst_day
)
SELECT
    d.cst_day,
    COALESCE(de.goals_completed, 0) AS goals_completed,
    MAX(COALESCE(de.tasks_completed, 0), COALESCE(dr.evaluated_tasks, 0)) AS tasks_completed,
    COALESCE(dr.r1_count, 0) AS r1_count,
    COALESCE(dr.r2_count, 0) AS r2_count,
    COALESCE(dr.r3_plus_count, 0) AS r3_plus_count,
    CASE
        WHEN COALESCE(dr.evaluated_tasks, 0) > 0
            THEN ROUND(1.0 * COALESCE(dr.r1_count, 0) / dr.evaluated_tasks, 4)
        ELSE NULL
    END AS r1_pass_rate,
    ddp.median_duration_sec,
    ddp.p90_duration_sec,
    COALESCE(de.blocked_events, 0) AS blocked_events,
    COALESCE(dt.steering_tokens, 0) AS steering_tokens,
    COALESCE(dt.coding_tokens, 0) AS coding_tokens,
    COALESCE(dt.total_tokens, 0) AS total_tokens
FROM days AS d
LEFT JOIN daily_events AS de ON de.cst_day = d.cst_day
LEFT JOIN daily_rounds AS dr ON dr.cst_day = d.cst_day
LEFT JOIN daily_duration_percentiles AS ddp ON ddp.cst_day = d.cst_day
LEFT JOIN daily_tokens AS dt ON dt.cst_day = d.cst_day
ORDER BY d.cst_day ASC;
