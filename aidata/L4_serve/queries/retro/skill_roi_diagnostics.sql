-- Skill effectiveness & efficiency ROI diagnostics (S4 + S6-S10) across turns, GTT reviews, and events.
WITH anchor AS (
    SELECT COALESCE(
        (SELECT MAX(cst_day) FROM fact_turn),
        (SELECT MAX(cst_day) FROM fact_gtt_task_run),
        date('now', '+8 hours')
    ) AS max_day
),
turn_skills AS (
    SELECT
        session_id,
        cst_day,
        CASE
            WHEN attribution_skill = 'goal-target-task' THEN 'team-lead'
            ELSE attribution_skill
        END AS skill,
        COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0) + COALESCE(cache_read, 0) AS tokens,
        CASE
            WHEN tool_calls LIKE '%"Bash"%'
              OR tool_calls LIKE '%"execute_code"%'
              OR tool_calls LIKE '%"terminal"%'
            THEN 1
            ELSE 0
        END AS has_script_exec,
        (
            length(COALESCE(tool_calls, ''))
            - length(replace(COALESCE(tool_calls, ''), '"Read"', ''))
        ) / 6 AS read_calls
    FROM fact_turn
    WHERE attribution_skill IS NOT NULL AND attribution_skill != ''
    UNION ALL
    SELECT
        t.session_id,
        t.cst_day,
        CASE
            WHEN json_each.value = 'goal-target-task' THEN 'team-lead'
            ELSE CAST(json_each.value AS TEXT)
        END AS skill,
        COALESCE(t.input_tokens, 0) + COALESCE(t.output_tokens, 0) + COALESCE(t.cache_read, 0) AS tokens,
        CASE
            WHEN t.tool_calls LIKE '%"Bash"%'
              OR t.tool_calls LIKE '%"execute_code"%'
              OR t.tool_calls LIKE '%"terminal"%'
            THEN 1
            ELSE 0
        END AS has_script_exec,
        (
            length(COALESCE(t.tool_calls, ''))
            - length(replace(COALESCE(t.tool_calls, ''), '"Read"', ''))
        ) / 6 AS read_calls
    FROM fact_turn AS t, json_each(t.skill_names)
    WHERE t.skill_names IS NOT NULL AND json_each.value != ''
),
session_skill_rollup AS (
    SELECT
        ts.skill,
        ts.session_id,
        MAX(CASE WHEN ts.cst_day > date(anchor.max_day, '-7 days') THEN 1 ELSE 0 END) AS in_7d,
        MAX(CASE WHEN ts.cst_day > date(anchor.max_day, '-30 days') THEN 1 ELSE 0 END) AS in_30d,
        COUNT(*) AS turn_loads,
        SUM(ts.tokens) AS session_tokens,
        MAX(ts.has_script_exec) AS session_script_exec,
        SUM(ts.read_calls) AS session_read_calls
    FROM turn_skills AS ts, anchor
    WHERE ts.skill IS NOT NULL AND ts.skill != ''
    GROUP BY ts.skill, ts.session_id
),
usage_agg AS (
    SELECT
        skill,
        SUM(CASE WHEN in_7d = 1 THEN turn_loads ELSE 0 END) AS loads_7d,
        SUM(CASE WHEN in_30d = 1 THEN turn_loads ELSE 0 END) AS loads_30d,
        COUNT(DISTINCT session_id) AS session_count,
        SUM(session_script_exec) AS script_exec_sessions,
        SUM(CASE WHEN session_read_calls <= 1 THEN 1 ELSE 0 END) AS l0_only_sessions,
        SUM(CASE WHEN session_read_calls BETWEEN 2 AND 3 THEN 1 ELSE 0 END) AS l1_selective_sessions,
        SUM(CASE WHEN session_read_calls >= 4 THEN 1 ELSE 0 END) AS l1_greedy_sessions,
        CAST(ROUND(AVG(session_tokens), 0) AS INTEGER) AS avg_context_tokens
    FROM session_skill_rollup
    GROUP BY skill
),
review_inferred AS (
    SELECT
        CASE
            WHEN lower(goal_id) LIKE '%design%' OR lower(goal_id) LIKE '%ui%'
              OR lower(goal_id) LIKE '%feel%' OR lower(goal_id) LIKE '%glass%'
            THEN 'my-designer'
            WHEN lower(goal_id) LIKE '%ingest%' OR lower(goal_id) LIKE '%palette%'
              OR lower(goal_id) LIKE '%motion%'
            THEN 'design-studio'
            WHEN lower(goal_id) LIKE '%retro%' OR lower(goal_id) LIKE '%telemetry%'
              OR lower(goal_id) LIKE '%roi%' OR lower(goal_id) LIKE '%aidash%'
            THEN 'retro-loop'
            WHEN lower(goal_id) LIKE '%learn%' OR lower(goal_id) LIKE '%digest%'
              OR lower(goal_id) LIKE '%blog%' OR lower(goal_id) LIKE '%vault%'
            THEN 'knowledge-digest'
            WHEN lower(goal_id) LIKE '%skill%' OR lower(goal_id) LIKE '%contract%'
            THEN 'skill-contract'
            WHEN lower(goal_id) LIKE '%m2%' OR lower(goal_id) LIKE '%herdr%'
              OR lower(goal_id) LIKE '%dispatch%'
            THEN 'm2-dispatcher'
            ELSE 'team-lead'
        END AS skill,
        round_no,
        UPPER(COALESCE(v5_verdict, '')) AS v5_verdict,
        LOWER(COALESCE(status, '')) AS status
    FROM fact_gtt_task_run
    WHERE role_name IN ('reviewer', 'code_reviewer', 'planner_reviewer')
),
review_agg AS (
    SELECT
        skill,
        SUM(CASE WHEN round_no = 1 THEN 1 ELSE 0 END) AS r1_total,
        SUM(
            CASE
                WHEN round_no = 1
                 AND v5_verdict IN ('PASS', 'CONCERNS', 'WAIVED')
                 AND status != 'failed'
                THEN 1
                ELSE 0
            END
        ) AS r1_pass,
        SUM(
            CASE
                WHEN round_no = 1
                 AND (v5_verdict = 'FAIL' OR status = 'failed')
                THEN 1
                ELSE 0
            END
        ) AS r1_fail,
        SUM(CASE WHEN round_no >= 2 THEN 1 ELSE 0 END) AS rework_rounds
    FROM review_inferred
    GROUP BY skill
),
escape_inferred AS (
    SELECT
        CASE
            WHEN lower(goal_id) LIKE '%design%' OR lower(goal_id) LIKE '%ui%'
              OR lower(goal_id) LIKE '%feel%' OR lower(goal_id) LIKE '%glass%'
            THEN 'my-designer'
            WHEN lower(goal_id) LIKE '%retro%' OR lower(goal_id) LIKE '%telemetry%'
              OR lower(goal_id) LIKE '%roi%' OR lower(goal_id) LIKE '%aidash%'
            THEN 'retro-loop'
            ELSE 'team-lead'
        END AS skill,
        evt_type,
        UPPER(COALESCE(note_preview, '')) AS note_upper
    FROM fact_gtt_event
    WHERE evt_type IN ('REVIEW_FAIL', 'RULING', 'CHANGE_REQUEST')
),
escape_agg AS (
    SELECT
        skill,
        SUM(
            CASE
                WHEN note_upper LIKE '%IMPL_BUG%'
                  OR (evt_type = 'REVIEW_FAIL' AND note_upper NOT LIKE '%SPEC_GAP%')
                THEN 1
                ELSE 0
            END
        ) AS impl_bug_count,
        SUM(
            CASE
                WHEN note_upper LIKE '%SPEC_GAP%'
                  OR evt_type IN ('RULING', 'CHANGE_REQUEST')
                THEN 1
                ELSE 0
            END
        ) AS spec_gap_count
    FROM escape_inferred
    GROUP BY skill
),
all_skills AS (
    SELECT skill FROM usage_agg
    UNION
    SELECT skill FROM review_agg
    UNION
    SELECT skill FROM escape_agg
)
SELECT
    s.skill AS skill,
    COALESCE(u.loads_7d, 0) AS loads_7d,
    COALESCE(u.loads_30d, COALESCE(r.r1_total, 0)) AS loads_30d,
    COALESCE(u.session_count, COALESCE(r.r1_total, 0)) AS session_count,
    COALESCE(u.script_exec_sessions, 0) AS script_exec_count,
    ROUND(
        CASE
            WHEN COALESCE(u.session_count, 0) > 0
            THEN 1.0 * COALESCE(u.script_exec_sessions, 0) / u.session_count
            ELSE 1.0
        END,
        4
    ) AS script_touch_rate,
    ROUND(
        CASE
            WHEN COALESCE(u.session_count, 0) > 0
            THEN 1.0 - (1.0 * COALESCE(u.script_exec_sessions, 0) / u.session_count)
            ELSE 0.0
        END,
        4
    ) AS unpracticed_rate,
    COALESCE(u.l0_only_sessions, 0) AS l0_only_sessions,
    COALESCE(u.l1_selective_sessions, 0) AS l1_selective_sessions,
    COALESCE(u.l1_greedy_sessions, 0) AS l1_greedy_sessions,
    COALESCE(u.avg_context_tokens, 1200) AS avg_context_tokens,
    COALESCE(r.r1_total, 0) AS r1_total,
    COALESCE(r.r1_pass, 0) AS r1_pass,
    ROUND(
        CASE
            WHEN COALESCE(r.r1_total, 0) > 0
            THEN 1.0 * COALESCE(r.r1_pass, 0) / r.r1_total
            ELSE 1.0
        END,
        4
    ) AS r1_pass_rate,
    COALESCE(r.rework_rounds, 0) AS rework_rounds,
    COALESCE(e.impl_bug_count, COALESCE(r.r1_fail, 0)) AS impl_bug_count,
    COALESCE(e.spec_gap_count, 0) AS spec_gap_count,
    ROUND(
        (
            CASE
                WHEN COALESCE(r.r1_total, 0) > 0
                THEN 1.0 * COALESCE(r.r1_pass, 0) / r.r1_total
                ELSE 1.0
            END
        ) / (
            0.5
            + MIN(2.0, MAX(0.2, COALESCE(u.avg_context_tokens, 1200) / 10000.0))
            + (COALESCE(r.rework_rounds, 0) * 0.25)
            + (
                CASE
                    WHEN COALESCE(u.session_count, 0) > 0
                    THEN (1.0 - (1.0 * COALESCE(u.script_exec_sessions, 0) / u.session_count)) * 0.6
                    ELSE 0.0
                END
            )
            + (COALESCE(e.impl_bug_count, COALESCE(r.r1_fail, 0)) * 0.2)
            + (COALESCE(e.spec_gap_count, 0) * 0.15)
        ),
        4
    ) AS roi_score
FROM all_skills AS s
LEFT JOIN usage_agg AS u ON u.skill = s.skill
LEFT JOIN review_agg AS r ON r.skill = s.skill
LEFT JOIN escape_agg AS e ON e.skill = s.skill
ORDER BY roi_score ASC, loads_30d DESC, s.skill ASC;
