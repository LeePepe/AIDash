-- Skill effectiveness & efficiency ROI diagnostics (observed L1-L3 facts).
-- Auxiliary facts are queried directly at their source grain; no CTE shadows a
-- warehouse table name and no session-wide fallback is copied to unrelated skills.
WITH anchor AS (
    SELECT COALESCE((SELECT MAX(cst_day) FROM fact_turn),
                    (SELECT MAX(cst_day) FROM fact_gtt_task_run),
                    date('now', '+8 hours')) AS max_day
),
turn_skills_raw AS (
    SELECT turn_uuid, session_id, cst_day,
           CASE WHEN attribution_skill = 'goal-target-task' THEN 'team-lead' ELSE attribution_skill END AS skill,
           COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0) + COALESCE(cache_read, 0) AS tokens,
           CASE WHEN tool_calls LIKE '%"Bash"%' OR tool_calls LIKE '%"execute_code"%' OR tool_calls LIKE '%"terminal"%' THEN 1 ELSE 0 END AS has_script_exec,
           CASE WHEN tool_calls IS NULL THEN 0 ELSE
             (length(tool_calls) - length(replace(tool_calls, '"Read"', ''))) / 6 END AS read_calls,
           CASE WHEN tool_calls IS NULL THEN 0 ELSE
             (length(tool_calls) - length(replace(tool_calls, '"Edit"', ''))) / 6
             + (length(tool_calls) - length(replace(tool_calls, '"Write"', ''))) / 7
             + (length(tool_calls) - length(replace(tool_calls, '"MultiEdit"', ''))) / 11
             + (length(tool_calls) - length(replace(tool_calls, '"apply_patch"', ''))) / 13
             + (length(tool_calls) - length(replace(tool_calls, '"create"', ''))) / 8 END AS file_edit_calls
    FROM fact_turn
    WHERE attribution_skill IS NOT NULL AND attribution_skill != ''
    UNION
    SELECT t.turn_uuid, t.session_id, t.cst_day,
           CASE WHEN json_each.value = 'goal-target-task' THEN 'team-lead' ELSE CAST(json_each.value AS TEXT) END AS skill,
           COALESCE(t.input_tokens, 0) + COALESCE(t.output_tokens, 0) + COALESCE(t.cache_read, 0) AS tokens,
           CASE WHEN t.tool_calls LIKE '%"Bash"%' OR t.tool_calls LIKE '%"execute_code"%' OR t.tool_calls LIKE '%"terminal"%' THEN 1 ELSE 0 END AS has_script_exec,
           CASE WHEN t.tool_calls IS NULL THEN 0 ELSE
             (length(t.tool_calls) - length(replace(t.tool_calls, '"Read"', ''))) / 6 END AS read_calls,
           CASE WHEN t.tool_calls IS NULL THEN 0 ELSE
             (length(t.tool_calls) - length(replace(t.tool_calls, '"Edit"', ''))) / 6
             + (length(t.tool_calls) - length(replace(t.tool_calls, '"Write"', ''))) / 7
             + (length(t.tool_calls) - length(replace(t.tool_calls, '"MultiEdit"', ''))) / 11
             + (length(t.tool_calls) - length(replace(t.tool_calls, '"apply_patch"', ''))) / 13
             + (length(t.tool_calls) - length(replace(t.tool_calls, '"create"', ''))) / 8 END AS file_edit_calls
    FROM fact_turn AS t, json_each(t.skill_names)
    WHERE t.skill_names IS NOT NULL AND json_each.value != ''
),
session_skill_base AS (
    SELECT ts.skill, ts.session_id,
           SUM(CASE WHEN ts.cst_day > date(anchor.max_day, '-7 days') THEN 1 ELSE 0 END) AS turn_loads_7d,
           SUM(CASE WHEN ts.cst_day > date(anchor.max_day, '-30 days') THEN 1 ELSE 0 END) AS turn_loads_30d,
           SUM(ts.tokens) AS session_tokens,
           MAX(ts.has_script_exec) AS session_script_exec,
           SUM(ts.file_edit_calls) AS file_edit_calls
    FROM turn_skills_raw ts CROSS JOIN anchor
    WHERE ts.skill IS NOT NULL AND ts.skill != ''
    GROUP BY ts.skill, ts.session_id
),
session_skills AS (
    SELECT DISTINCT session_id, skill FROM session_skill_base
),
reference_events AS (
    SELECT session_id, skill, reference_path, byte_len
    FROM reference_hits
    WHERE reference_path IS NOT NULL AND skill IS NOT NULL
    UNION ALL
    SELECT h.session_id, s.skill, h.reference_path, h.byte_len
    FROM reference_hits h
    JOIN session_skills s ON s.session_id = h.session_id
    WHERE h.reference_path IS NOT NULL AND h.skill IS NULL
),
reference_rollup AS (
    SELECT session_id, skill, COUNT(DISTINCT reference_path) AS reference_hit_count,
           SUM(COALESCE(byte_len, 0)) AS reference_bytes
    FROM reference_events
    GROUP BY session_id, skill
),
script_events AS (
    SELECT session_id, skill, script_path, exit_code, duration_ms
    FROM script_call
    WHERE script_path IS NOT NULL AND skill IS NOT NULL
    UNION ALL
    SELECT c.session_id, s.skill, c.script_path, c.exit_code, c.duration_ms
    FROM script_call c
    JOIN session_skills s ON s.session_id = c.session_id
    WHERE c.script_path IS NOT NULL AND c.skill IS NULL
),
script_session_rollup AS (
    SELECT session_id, skill, COUNT(*) AS script_count,
           SUM(CASE WHEN exit_code IS NOT NULL THEN 1 ELSE 0 END) AS script_exit_count,
           SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) AS script_success_count,
           SUM(CASE WHEN duration_ms IS NOT NULL THEN 1 ELSE 0 END) AS duration_count,
           SUM(duration_ms) AS duration_sum
    FROM script_events
    GROUP BY session_id, skill
),
script_latency_ranked AS (
    SELECT skill, duration_ms,
           ROW_NUMBER() OVER (PARTITION BY skill ORDER BY duration_ms ASC) AS rn,
           COUNT(*) OVER (PARTITION BY skill) AS cnt
    FROM script_events
    WHERE duration_ms IS NOT NULL
),
script_skill_stats AS (
    SELECT skill, AVG(duration_ms) AS avg_script_duration_ms,
           MAX(CASE WHEN rn = MAX(1, CAST((cnt * 95 + 99) / 100 AS INTEGER)) THEN duration_ms END) AS p95_ms
    FROM script_latency_ranked
    GROUP BY skill
),
session_skill_rollup AS (
    SELECT b.skill, b.session_id, b.turn_loads_7d, b.turn_loads_30d,
           b.session_tokens, b.session_script_exec, b.file_edit_calls,
           COALESCE(r.reference_hit_count, 0) AS reference_hit_count,
           COALESCE(s.script_count, 0) AS script_count,
           COALESCE(s.script_exit_count, 0) AS script_exit_count,
           COALESCE(s.script_success_count, 0) AS script_success_count,
           s.duration_count, s.duration_sum
    FROM session_skill_base b
    LEFT JOIN reference_rollup r ON r.session_id = b.session_id AND r.skill = b.skill
    LEFT JOIN script_session_rollup s ON s.session_id = b.session_id AND s.skill = b.skill
),
usage_agg AS (
    SELECT skill, SUM(turn_loads_7d) AS loads_7d, SUM(turn_loads_30d) AS loads_30d,
           COUNT(DISTINCT session_id) AS session_count,
           SUM(CASE WHEN script_count > 0 THEN 1 ELSE 0 END) AS script_exec_sessions,
           SUM(CASE WHEN reference_hit_count = 0 THEN 1 ELSE 0 END) AS l0_only_sessions,
           SUM(CASE WHEN reference_hit_count BETWEEN 1 AND 2 THEN 1 ELSE 0 END) AS l1_selective_sessions,
           SUM(CASE WHEN reference_hit_count >= 3 THEN 1 ELSE 0 END) AS l1_greedy_sessions,
           SUM(CASE WHEN reference_hit_count = 0 AND script_count = 0 AND file_edit_calls = 0 THEN 1 ELSE 0 END) AS empty_load_sessions,
           SUM(reference_hit_count) AS reference_hit_count,
           SUM(script_success_count) AS script_success_count,
           SUM(script_exit_count) AS script_exit_count,
           SUM(script_count) AS script_count,
           CAST(ROUND(AVG(session_tokens), 0) AS INTEGER) AS avg_context_tokens
    FROM session_skill_rollup GROUP BY skill
),
review_source AS (
    SELECT goal_id, task_id, role_name, round_no, v5_verdict, status, skills_used
    FROM fact_gtt_task_run
    WHERE role_name IN ('reviewer', 'code_reviewer', 'planner_reviewer')
),
review_explicit AS (
    SELECT CASE WHEN json_each.value = 'goal-target-task' THEN 'team-lead' ELSE CAST(json_each.value AS TEXT) END AS skill,
           round_no, UPPER(COALESCE(v5_verdict, '')) AS v5_verdict, LOWER(COALESCE(status, '')) AS status
    FROM review_source, json_each(
        CASE WHEN json_valid(skills_used) AND json_type(skills_used) = 'array'
             AND json_array_length(skills_used) > 0 THEN skills_used ELSE '[]' END
    )
),
review_fallback AS (
    SELECT CASE
             WHEN lower(goal_id) LIKE '%design%' OR lower(goal_id) LIKE '%ui%' OR lower(goal_id) LIKE '%feel%' OR lower(goal_id) LIKE '%glass%' THEN 'my-designer'
             WHEN lower(goal_id) LIKE '%ingest%' OR lower(goal_id) LIKE '%palette%' OR lower(goal_id) LIKE '%motion%' THEN 'design-studio'
             WHEN lower(goal_id) LIKE '%retro%' OR lower(goal_id) LIKE '%telemetry%' OR lower(goal_id) LIKE '%roi%' OR lower(goal_id) LIKE '%aidash%' THEN 'retro-loop'
             WHEN lower(goal_id) LIKE '%learn%' OR lower(goal_id) LIKE '%digest%' OR lower(goal_id) LIKE '%blog%' OR lower(goal_id) LIKE '%vault%' THEN 'knowledge-digest'
             WHEN lower(goal_id) LIKE '%skill%' OR lower(goal_id) LIKE '%contract%' THEN 'skill-contract'
             WHEN lower(goal_id) LIKE '%m2%' OR lower(goal_id) LIKE '%herdr%' OR lower(goal_id) LIKE '%dispatch%' THEN 'm2-dispatcher'
             ELSE 'team-lead' END AS skill,
           round_no, UPPER(COALESCE(v5_verdict, '')) AS v5_verdict, LOWER(COALESCE(status, '')) AS status
    FROM review_source
    WHERE NOT (json_valid(skills_used) AND json_type(skills_used) = 'array' AND json_array_length(skills_used) > 0)
),
review_inferred AS (
    SELECT * FROM review_explicit
    UNION ALL
    SELECT * FROM review_fallback
),
review_agg AS (
    SELECT skill, SUM(CASE WHEN round_no = 1 THEN 1 ELSE 0 END) AS r1_total,
           SUM(CASE WHEN round_no = 1 AND v5_verdict IN ('PASS', 'CONCERNS', 'WAIVED') AND status != 'failed' THEN 1 ELSE 0 END) AS r1_pass,
           SUM(CASE WHEN round_no = 1 AND (v5_verdict = 'FAIL' OR status = 'failed') THEN 1 ELSE 0 END) AS r1_fail,
           SUM(CASE WHEN round_no >= 2 THEN 1 ELSE 0 END) AS rework_rounds
    FROM review_inferred GROUP BY skill
),
eval_effect AS (
    SELECT CASE WHEN lower(goal_id) LIKE '%design%' OR lower(goal_id) LIKE '%ui%' OR lower(goal_id) LIKE '%feel%' THEN 'my-designer' ELSE 'team-lead' END AS skill,
           eval_case,
           COALESCE(interception, 0) AS interception,
           COALESCE("escape", 0) AS escape_flag,
           CASE WHEN upper(COALESCE(note_preview, '')) LIKE '%SPEC_GAP%' OR evt_type IN ('RULING', 'CHANGE_REQUEST') THEN 1 ELSE 0 END AS spec_gap_flag
    FROM fact_gtt_event
),
eval_agg AS (
    SELECT skill, SUM(interception) AS interception, SUM(escape_flag) AS escape_count,
           SUM(spec_gap_flag) AS spec_gap_count,
           SUM(interception) + SUM(escape_flag) AS eval_effect
    FROM eval_effect GROUP BY skill
),
all_skills AS (
    SELECT skill FROM usage_agg
    UNION SELECT skill FROM review_agg
    UNION SELECT skill FROM eval_agg
    UNION SELECT skill FROM reference_rollup
    UNION SELECT skill FROM script_session_rollup
    UNION SELECT skill FROM script_skill_stats
)
SELECT s.skill,
       COALESCE(u.loads_7d, 0) AS loads_7d,
       COALESCE(u.loads_30d, COALESCE(r.r1_total, 0)) AS loads_30d,
       COALESCE(u.session_count, COALESCE(r.r1_total, 0)) AS session_count,
       COALESCE(u.script_exec_sessions, 0) AS script_exec_count,
       ROUND(CASE WHEN COALESCE(u.session_count, 0) > 0 THEN 1.0 * COALESCE(u.script_exec_sessions, 0) / u.session_count ELSE NULL END, 4) AS script_touch_rate,
       ROUND(CASE WHEN COALESCE(u.session_count, 0) > 0 THEN 1.0 - 1.0 * COALESCE(u.script_exec_sessions, 0) / u.session_count ELSE NULL END, 4) AS unpracticed_rate,
       COALESCE(u.l0_only_sessions, 0) AS l0_only_sessions,
       COALESCE(u.l1_selective_sessions, 0) AS l1_selective_sessions,
       COALESCE(u.l1_greedy_sessions, 0) AS l1_greedy_sessions,
       COALESCE(u.empty_load_sessions, 0) AS empty_load_sessions,
       ROUND(CASE WHEN COALESCE(u.session_count, 0) > 0 THEN 1.0 * COALESCE(u.empty_load_sessions, 0) / u.session_count ELSE NULL END, 4) AS empty_load_rate,
       COALESCE(u.reference_hit_count, 0) AS reference_hit_count,
       u.avg_context_tokens,
       COALESCE(u.script_success_count, 0) AS script_success_count,
       CASE WHEN COALESCE(u.script_exit_count, 0) > 0 THEN 1.0 * u.script_success_count / u.script_exit_count ELSE NULL END AS script_success_rate,
       stats.avg_script_duration_ms,
       stats.p95_ms,
       stats.p95_ms AS script_latency,
       COALESCE(r.r1_total, 0) AS r1_total, COALESCE(r.r1_pass, 0) AS r1_pass,
       ROUND(CASE WHEN COALESCE(r.r1_total, 0) > 0 THEN 1.0 * r.r1_pass / r.r1_total ELSE NULL END, 4) AS r1_pass_rate,
       COALESCE(r.rework_rounds, 0) AS rework_rounds,
       COALESCE(e.interception, 0) AS interception, COALESCE(e.escape_count, 0) AS "escape",
       COALESCE(e.eval_effect, 0) AS eval_effect,
       COALESCE(e.escape_count, COALESCE(r.r1_fail, 0)) AS impl_bug_count,
       COALESCE(e.spec_gap_count, 0) AS spec_gap_count,
       ROUND(CASE WHEN COALESCE(r.r1_total, 0) > 0 AND u.avg_context_tokens IS NOT NULL THEN (1.0 * r.r1_pass / r.r1_total) / (0.5 + MIN(2.0, u.avg_context_tokens / 10000.0) + COALESCE(r.rework_rounds, 0) * 0.25 + CASE WHEN COALESCE(u.session_count, 0) > 0 THEN 1.0 - 1.0 * u.script_exec_sessions / u.session_count ELSE 0 END * 0.6 + COALESCE(e.escape_count, COALESCE(r.r1_fail, 0)) * 0.2 + COALESCE(e.spec_gap_count, 0) * 0.15) ELSE NULL END, 4) AS roi_score,
       anchor.max_day AS source_as_of,
       date(anchor.max_day, '-6 days') || ' → ' || anchor.max_day AS time_window,
       COALESCE(u.session_count, r.r1_total, 0) AS sample_size,
       CASE WHEN COALESCE(u.session_count, r.r1_total, 0) > 0 THEN 'covered' ELSE 'unknown' END AS coverage_status,
       0 AS estimated
FROM all_skills s CROSS JOIN anchor
LEFT JOIN usage_agg u ON u.skill = s.skill
LEFT JOIN review_agg r ON r.skill = s.skill
LEFT JOIN eval_agg e ON e.skill = s.skill
LEFT JOIN script_skill_stats stats ON stats.skill = s.skill
ORDER BY roi_score ASC, loads_30d DESC, s.skill ASC;
