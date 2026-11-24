-- aidata-tier: explore
-- Agent role division, review round distribution (r1/r2/r3+), stage duration
-- (median/p90), and model token split across the 8 canonical workflow roles.
WITH role_catalog(role_key, role_label, sort_order) AS (
    VALUES
        ('m3',         '总控协调',             1),
        ('m2',         '话题编排',             2),
        ('m1',         'Goal 主控 (TL)',       3),
        ('designer',   '视觉设计 (Designer)',   4),
        ('writer',     '编码实现 (Writer)',     5),
        ('reviewer',   '独立审查 (Reviewer)',   6),
        ('explorer',   '代码探查 (Explorer)',   7),
        ('pr_monitor', '交付监控 (PR Monitor)', 8)
),
normalized_runs AS (
    SELECT
        receipt_uid,
        goal_uid,
        COALESCE(NULLIF(task_id, ''), receipt_uid) AS task_key,
        CASE
            WHEN lower(role_name) IN ('m3', 'm3_assistant', 'personal-m2-assistant') THEN 'm3'
            WHEN lower(role_name) IN ('m2', 'm2_dispatcher', 'dispatcher') THEN 'm2'
            WHEN lower(role_name) IN ('steering', 'm1_steering', 'm1', 'planner', 'team_lead', 'goal_tl')
              OR lower(role_name) LIKE '%steering%'
              OR lower(role_name) LIKE '%goal_tl%'
              OR lower(role_name) LIKE '%team_lead%' THEN 'm1'
            WHEN lower(role_name) LIKE '%designer%' THEN 'designer'
            WHEN lower(role_name) IN ('reviewer', 'code_reviewer', 'planner_reviewer')
              OR lower(role_name) LIKE '%reviewer%' THEN 'reviewer'
            WHEN lower(role_name) LIKE '%explorer%' THEN 'explorer'
            WHEN lower(role_name) IN ('pr_monitor', 'prmon')
              OR lower(role_name) LIKE '%pr monitor%'
              OR lower(role_name) LIKE '%pr_monitor%'
              OR lower(role_name) LIKE '%pr merge monitor%' THEN 'pr_monitor'
            ELSE 'writer'
        END AS role_key,
        CASE
            WHEN round_no IS NULL OR round_no < 1 THEN 1
            -- Receipt naming convention *-r10.md denotes R10 receipt format, not round 10.
            WHEN round_no = 10 THEN 1
            ELSE round_no
        END AS effective_round,
        UPPER(COALESCE(v5_verdict, '')) AS verdict_upper,
        LOWER(COALESCE(status, '')) AS status_lower
    FROM fact_gtt_task_run
),
synthetic_supervision_runs AS (
    -- Synthesize M3 / M2 / M1 activity from supervision & goal ledger events
    -- so coordination tiers remain observable even when they do not emit leaf R10s.
    SELECT
        'm3:' || session_id || ':' || turn_uuid AS run_id,
        COALESCE(session_id, turn_uuid) AS goal_uid,
        turn_uuid AS task_key,
        'm3' AS role_key,
        1 AS effective_round,
        'PASS' AS verdict_upper,
        'completed' AS status_lower
    FROM fact_turn
    WHERE attribution_skill = 'personal-m2-assistant'
       OR COALESCE(skill_names, '') LIKE '%"personal-m2-assistant"%'
    UNION ALL
    SELECT
        'm2:' || supervision_uid AS run_id,
        'm2:' || goal_id AS goal_uid,
        goal_id || ':' || action_kind AS task_key,
        'm2' AS role_key,
        1 AS effective_round,
        'PASS' AS verdict_upper,
        LOWER(COALESCE(status, 'completed')) AS status_lower
    FROM fact_bot_tl_supervision
    UNION ALL
    SELECT
        'm1:' || event_uid AS run_id,
        goal_uid,
        COALESCE(NULLIF(task_id, ''), event_id) AS task_key,
        'm1' AS role_key,
        1 AS effective_round,
        'PASS' AS verdict_upper,
        'completed' AS status_lower
    FROM fact_gtt_event
    WHERE evt_type IN ('RULING', 'GOAL_DONE', 'WAVE_DONE', 'TL_STARTED', 'GOAL_START')
),
all_role_runs AS (
    SELECT receipt_uid AS run_id, goal_uid, task_key, role_key, effective_round, verdict_upper, status_lower
    FROM normalized_runs
    UNION ALL
    SELECT run_id, goal_uid, task_key, role_key, effective_round, verdict_upper, status_lower
    FROM synthetic_supervision_runs
),
role_task_rounds AS (
    SELECT
        role_key,
        goal_uid,
        task_key,
        MAX(effective_round) AS max_round,
        MAX(CASE WHEN effective_round = 1 AND (verdict_upper = 'FAIL' OR status_lower = 'failed') THEN 1 ELSE 0 END) AS had_r1_fail
    FROM all_role_runs
    GROUP BY role_key, goal_uid, task_key
),
role_counts AS (
    SELECT
        r.role_key,
        COUNT(*) AS runs_count,
        COUNT(DISTINCT r.goal_uid) AS goals_count,
        COUNT(DISTINCT r.goal_uid || ':' || r.task_key) AS tasks_count
    FROM all_role_runs AS r
    GROUP BY r.role_key
),
role_round_agg AS (
    SELECT
        role_key,
        SUM(CASE WHEN max_round = 1 AND had_r1_fail = 0 THEN 1 ELSE 0 END) AS r1_count,
        SUM(CASE WHEN max_round = 2 OR (max_round = 1 AND had_r1_fail = 1) THEN 1 ELSE 0 END) AS r2_count,
        SUM(CASE WHEN max_round >= 3 THEN 1 ELSE 0 END) AS r3_plus_count,
        COUNT(*) AS evaluated_tasks
    FROM role_task_rounds
    GROUP BY role_key
),
task_event_spans AS (
    SELECT
        goal_uid,
        task_id AS task_key,
        MIN(CASE WHEN evt_type IN ('READY', 'DISPATCHED', 'DISPATCH', 'START') THEN julianday(ts) END) AS start_jd,
        MIN(CASE WHEN evt_type IN ('IN_REVIEW', 'REVIEW', 'REVIEW_PASS', 'REVIEW_FAIL') THEN julianday(ts) END) AS review_jd,
        MAX(CASE WHEN evt_type IN ('DONE', 'TASK_DONE', 'REVIEW_PASS', 'PR_MERGED', 'GOAL_DONE') THEN julianday(ts) END) AS end_jd
    FROM fact_gtt_event
    WHERE task_id IS NOT NULL AND task_id != '' AND julianday(ts) IS NOT NULL
    GROUP BY goal_uid, task_id
),
goal_event_spans AS (
    SELECT
        goal_uid,
        MIN(julianday(ts)) AS start_jd,
        MAX(julianday(ts)) AS end_jd
    FROM fact_gtt_event
    WHERE julianday(ts) IS NOT NULL
    GROUP BY goal_uid
),
role_durations_raw AS (
    -- Task-linked leaf roles use task dispatch-to-completion / review spans (1s..86400s).
    SELECT
        tr.role_key,
        CASE
            WHEN tr.role_key = 'reviewer' AND s.review_jd IS NOT NULL AND s.end_jd >= s.review_jd
                 AND (s.end_jd - s.review_jd) * 86400.0 >= 5.0
                THEN (s.end_jd - s.review_jd) * 86400.0
            ELSE (s.end_jd - s.start_jd) * 86400.0
        END AS duration_sec
    FROM (SELECT DISTINCT role_key, goal_uid, task_key FROM normalized_runs) AS tr
    JOIN task_event_spans AS s
      ON s.goal_uid = tr.goal_uid AND s.task_key = tr.task_key
    WHERE s.start_jd IS NOT NULL
      AND s.end_jd IS NOT NULL
      AND s.end_jd > s.start_jd
      AND (s.end_jd - s.start_jd) * 86400.0 BETWEEN 1.0 AND 86400.0
    UNION ALL
    -- Goal-level steering spans (bounded to <= 86400s active goal lifecycle).
    SELECT
        'm1' AS role_key,
        (g.end_jd - g.start_jd) * 86400.0 AS duration_sec
    FROM goal_event_spans AS g
    WHERE g.start_jd IS NOT NULL
      AND g.end_jd IS NOT NULL
      AND g.end_jd > g.start_jd
      AND (g.end_jd - g.start_jd) * 86400.0 BETWEEN 5.0 AND 86400.0
    UNION ALL
    -- Request-level latency fallback (in seconds) for M2/M3 interactive turns when GTT spans are absent.
    SELECT
        CASE
            WHEN client LIKE 'codex-tui%' OR client LIKE 'codex_cli%' THEN 'm2'
            ELSE 'm3'
        END AS role_key,
        latency_ms / 1000.0 AS duration_sec
    FROM fact_request
    WHERE latency_ms IS NOT NULL
      AND latency_ms > 100
      AND (client LIKE 'codex-tui%' OR client LIKE 'codex_cli%' OR model_canon = 'microsoft-decision-1')
),
ranked_durations AS (
    SELECT
        role_key,
        duration_sec,
        ROW_NUMBER() OVER (PARTITION BY role_key ORDER BY duration_sec ASC) AS rn,
        COUNT(*) OVER (PARTITION BY role_key) AS cnt
    FROM role_durations_raw
    WHERE duration_sec IS NOT NULL AND duration_sec > 0
),
role_duration_percentiles AS (
    SELECT
        role_key,
        ROUND(AVG(CASE WHEN rn IN ((cnt + 1) / 2, (cnt + 2) / 2) THEN duration_sec END), 1) AS median_duration_sec,
        ROUND(MAX(CASE WHEN rn = MAX(1, CAST((cnt * 90 + 99) / 100 AS INTEGER)) THEN duration_sec END), 1) AS p90_duration_sec
    FROM ranked_durations
    GROUP BY role_key
),
request_anchor AS (
    SELECT COALESCE(MAX(cst_day), date('now', '+8 hours')) AS max_day
    FROM fact_request
),
request_role_tokens AS (
    SELECT
        CASE
            WHEN r.model_canon = 'microsoft-decision-1' THEN 'm3'
            WHEN r.client LIKE 'codex-tui%' OR r.client LIKE 'codex_cli%' THEN 'm2'
            WHEN r.client LIKE 'claude%' THEN 'm1'
            WHEN r.model_canon LIKE '%flash%' THEN 'explorer'
            WHEN r.model_canon LIKE 'gemini-4-argon%' AND r.client = 'magpie' THEN 'reviewer'
            WHEN r.model_canon LIKE 'gemini-4-carbon%' THEN 'designer'
            ELSE 'writer'
        END AS role_key,
        SUM(COALESCE(r.total_tokens, COALESCE(r.input_tokens, 0) + COALESCE(r.output_tokens, 0) + COALESCE(r.cache_read, 0) + COALESCE(r.cache_write, 0))) AS observed_tokens
    FROM fact_request AS r
    CROSS JOIN request_anchor AS a
    WHERE r.cst_day > date(a.max_day, '-14 days')
    GROUP BY 1
),
token_totals AS (
    SELECT COALESCE(SUM(observed_tokens), 0) AS grand_tokens FROM request_role_tokens
)
SELECT
    c.role_key,
    c.role_label,
    COALESCE(rc.runs_count, 0) AS runs_count,
    COALESCE(rc.goals_count, 0) AS goals_count,
    COALESCE(rc.tasks_count, 0) AS tasks_count,
    COALESCE(rr.r1_count, 0) AS r1_count,
    COALESCE(rr.r2_count, 0) AS r2_count,
    COALESCE(rr.r3_plus_count, 0) AS r3_plus_count,
    CASE
        WHEN COALESCE(rr.evaluated_tasks, 0) > 0
            THEN ROUND(1.0 * COALESCE(rr.r1_count, 0) / rr.evaluated_tasks, 4)
        ELSE NULL
    END AS r1_pass_rate,
    dp.median_duration_sec,
    dp.p90_duration_sec,
    COALESCE(rt.observed_tokens, 0) AS estimated_tokens,
    CASE
        WHEN tt.grand_tokens > 0
            THEN ROUND(100.0 * COALESCE(rt.observed_tokens, 0) / tt.grand_tokens, 2)
        ELSE 0.0
    END AS token_share_pct
FROM role_catalog AS c
LEFT JOIN role_counts AS rc ON rc.role_key = c.role_key
LEFT JOIN role_round_agg AS rr ON rr.role_key = c.role_key
LEFT JOIN role_duration_percentiles AS dp ON dp.role_key = c.role_key
LEFT JOIN request_role_tokens AS rt ON rt.role_key = c.role_key
CROSS JOIN token_totals AS tt
ORDER BY c.sort_order ASC;
