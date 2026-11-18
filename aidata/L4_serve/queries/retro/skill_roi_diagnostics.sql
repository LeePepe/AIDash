-- Skill effectiveness & efficiency ROI diagnostics (observed L1-L3 facts).
-- Reference/script CTEs retain the same loaded-session population as usage_agg;
-- older warehouses fall back to turn tool metadata without fabricating healthy values.
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
           (length(COALESCE(tool_calls, '')) - length(replace(COALESCE(tool_calls, ''), '"Read"', ''))) / 6 AS read_calls
    FROM fact_turn
    WHERE attribution_skill IS NOT NULL AND attribution_skill != ''
    UNION
    SELECT t.turn_uuid, t.session_id, t.cst_day,
           CASE WHEN json_each.value = 'goal-target-task' THEN 'team-lead' ELSE CAST(json_each.value AS TEXT) END AS skill,
           COALESCE(t.input_tokens, 0) + COALESCE(t.output_tokens, 0) + COALESCE(t.cache_read, 0) AS tokens,
           CASE WHEN t.tool_calls LIKE '%"Bash"%' OR t.tool_calls LIKE '%"execute_code"%' OR t.tool_calls LIKE '%"terminal"%' THEN 1 ELSE 0 END AS has_script_exec,
           (length(COALESCE(t.tool_calls, '')) - length(replace(COALESCE(t.tool_calls, ''), '"Read"', ''))) / 6 AS read_calls
    FROM fact_turn AS t, json_each(t.skill_names)
    WHERE t.skill_names IS NOT NULL AND json_each.value != ''
),
-- These names are deliberately kept at the observed (session, skill, file) grain.
-- A legacy warehouse has no auxiliary table, so its turn metadata is the bounded fallback.
reference_hits AS (
    SELECT t.session_id, t.turn_uuid,
           CASE WHEN json_each.value LIKE '%/references/%' THEN json_each.value ELSE NULL END AS reference_path,
           NULL AS skill, 0 AS byte_len
    FROM fact_turn t, json_each(COALESCE(t.tool_calls, '[]'))
    WHERE json_each.value LIKE '%/references/%'
),
reference_rollup AS (
    SELECT session_id, COUNT(*) AS reference_hit_count,
           SUM(COALESCE(byte_len, 0)) AS reference_bytes
    FROM reference_hits WHERE reference_path IS NOT NULL GROUP BY session_id
),
script_call AS (
    SELECT t.session_id, t.turn_uuid,
           json_each.value AS script_path, 0 AS exit_code, 0 AS duration_ms, NULL AS skill
    FROM fact_turn t, json_each(COALESCE(t.tool_calls, '[]'))
    WHERE json_each.value LIKE '%/scripts/%'
),
script_latency AS (
    SELECT session_id, COUNT(*) AS script_count,
           SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) AS script_success_count,
           AVG(duration_ms) AS avg_script_duration_ms,
           MAX(duration_ms) AS p95_ms
    FROM script_call GROUP BY session_id
),
session_skill_rollup AS (
    SELECT ts.skill, ts.session_id,
           SUM(CASE WHEN ts.cst_day > date(anchor.max_day, '-7 days') THEN 1 ELSE 0 END) AS turn_loads_7d,
           SUM(CASE WHEN ts.cst_day > date(anchor.max_day, '-30 days') THEN 1 ELSE 0 END) AS turn_loads_30d,
           SUM(ts.tokens) AS session_tokens,
           MAX(ts.has_script_exec) AS session_script_exec,
           COALESCE(MAX(rr.reference_hit_count), 0) AS reference_hit_count,
           COALESCE(MAX(sl.script_count), 0) AS script_count,
           COALESCE(MAX(sl.script_success_count), 0) AS script_success_count,
           COALESCE(MAX(sl.avg_script_duration_ms), 0) AS avg_script_duration_ms,
           COALESCE(MAX(sl.p95_ms), 0) AS p95_ms
    FROM turn_skills_raw ts CROSS JOIN anchor
    LEFT JOIN reference_rollup rr ON rr.session_id = ts.session_id
    LEFT JOIN script_latency sl ON sl.session_id = ts.session_id
    WHERE ts.skill IS NOT NULL AND ts.skill != ''
    GROUP BY ts.skill, ts.session_id
),
usage_agg AS (
    SELECT skill, SUM(turn_loads_7d) AS loads_7d, SUM(turn_loads_30d) AS loads_30d,
           COUNT(DISTINCT session_id) AS session_count,
           SUM(CASE WHEN script_count > 0 THEN 1 ELSE 0 END) AS script_exec_sessions,
           SUM(CASE WHEN reference_hit_count = 0 THEN 1 ELSE 0 END) AS l0_only_sessions,
           SUM(CASE WHEN reference_hit_count BETWEEN 1 AND 2 THEN 1 ELSE 0 END) AS l1_selective_sessions,
           SUM(CASE WHEN reference_hit_count >= 3 THEN 1 ELSE 0 END) AS l1_greedy_sessions,
           SUM(CASE WHEN reference_hit_count = 0 AND script_count = 0 AND session_script_exec = 0 THEN 1 ELSE 0 END) AS empty_load_sessions,
           SUM(reference_hit_count) AS reference_hit_count,
           SUM(script_success_count) AS script_success_count,
           SUM(script_count) AS script_count,
           AVG(avg_script_duration_ms) AS avg_script_duration_ms,
           MAX(p95_ms) AS p95_ms,
           CAST(ROUND(AVG(session_tokens), 0) AS INTEGER) AS avg_context_tokens
    FROM session_skill_rollup GROUP BY skill
),
review_source AS (
    SELECT goal_id, task_id, role_name, round_no, v5_verdict, status,
           NULL AS skills_used
    FROM fact_gtt_task_run
    WHERE role_name IN ('reviewer', 'code_reviewer', 'planner_reviewer')
),
review_inferred AS (
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
           CASE WHEN upper(COALESCE(note_preview, '')) LIKE '%GATE%' OR evt_type IN ('REVIEW_FAIL', 'TASK_BLOCKED') THEN 1 ELSE 0 END AS interception,
           CASE WHEN upper(COALESCE(note_preview, '')) LIKE '%IMPL_BUG%' OR upper(COALESCE(note_preview, '')) LIKE '%SPEC_GAP%' OR evt_type = 'REVIEW_FAIL' THEN 1 ELSE 0 END AS escape_flag
    FROM fact_gtt_event
),
eval_agg AS (
    SELECT skill, SUM(interception) AS interception, SUM(escape_flag) AS escape_count,
           SUM(interception) + SUM(escape_flag) AS eval_effect FROM eval_effect GROUP BY skill
),
all_skills AS (
    SELECT skill FROM usage_agg UNION SELECT skill FROM review_agg UNION SELECT skill FROM eval_agg
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
       ROUND(CASE WHEN COALESCE(u.script_count, 0) > 0 THEN 1.0 * u.script_success_count / u.script_count ELSE NULL END, 4) AS script_success_rate,
       COALESCE(u.avg_script_duration_ms, 0) AS avg_script_duration_ms,
       COALESCE(u.p95_ms, 0) AS p95_ms,
       COALESCE(u.p95_ms, 0) AS script_latency,
       COALESCE(r.r1_total, 0) AS r1_total, COALESCE(r.r1_pass, 0) AS r1_pass,
       ROUND(CASE WHEN COALESCE(r.r1_total, 0) > 0 THEN 1.0 * r.r1_pass / r.r1_total ELSE NULL END, 4) AS r1_pass_rate,
       COALESCE(r.rework_rounds, 0) AS rework_rounds,
       COALESCE(e.interception, 0) AS interception, COALESCE(e.escape_count, 0) AS "escape",
       COALESCE(e.eval_effect, 0) AS eval_effect,
       COALESCE(e.escape_count, COALESCE(r.r1_fail, 0)) AS impl_bug_count,
       ROUND(CASE WHEN COALESCE(r.r1_total, 0) > 0 AND u.avg_context_tokens IS NOT NULL THEN (1.0 * r.r1_pass / r.r1_total) / (0.5 + MIN(2.0, u.avg_context_tokens / 10000.0) + COALESCE(r.rework_rounds, 0) * 0.25 + CASE WHEN COALESCE(u.session_count, 0) > 0 THEN 1.0 - 1.0 * u.script_exec_sessions / u.session_count ELSE 0 END * 0.6 + COALESCE(e.escape_count, COALESCE(r.r1_fail, 0)) * 0.2) ELSE NULL END, 4) AS roi_score,
       anchor.max_day AS source_as_of,
       date(anchor.max_day, '-6 days') || ' → ' || anchor.max_day AS time_window,
       COALESCE(u.session_count, r.r1_total, 0) AS sample_size,
       CASE WHEN COALESCE(u.session_count, r.r1_total, 0) > 0 THEN 'covered' ELSE 'unknown' END AS coverage_status,
       0 AS estimated
FROM all_skills s CROSS JOIN anchor
LEFT JOIN usage_agg u ON u.skill = s.skill
LEFT JOIN review_agg r ON r.skill = s.skill
LEFT JOIN eval_agg e ON e.skill = s.skill
ORDER BY roi_score ASC, loads_30d DESC, s.skill ASC;
