-- aidata-tier: explore
-- Rolling CST window (default 14 days) session-work stream & goal-level rollups:
-- joins fact_session_work_summary with dim_goal, fact_gtt_task_run, reference_hits,
-- script_call, and fact_agent_retro_finding to serve per-session receipts alongside
-- per-goal aggregated totals, latest CST day, and skill-version watermark summaries.
WITH anchor AS (
    SELECT COALESCE(
        :until_day,
        (SELECT MAX(s.cst_day) FROM fact_session_work_summary AS s WHERE s.cst_day IS NOT NULL),
        date('now', '+8 hours')
    ) AS end_day,
    MAX(1, CAST(COALESCE(:days, 14) AS INTEGER)) AS win_days
),
bounds AS (
    SELECT
        COALESCE(:since_day, date(a.end_day, '-' || (a.win_days - 1) || ' days')) AS start_day,
        a.end_day AS end_day,
        a.win_days AS win_days
    FROM anchor AS a
),
windowed_sessions AS (
    SELECT
        s.session_uid,
        s.source,
        s.session_id_short,
        COALESCE(NULLIF(s.goal_id, ''), 'unassigned-daily') AS effective_goal_id,
        CASE WHEN s.goal_id IS NULL OR s.goal_id = '' THEN 1 ELSE 0 END AS is_unassigned_bucket,
        s.repo_name,
        s.branch_name,
        s.role_key,
        s.model_id,
        s.summary_label,
        s.started_at,
        s.ended_at,
        COALESCE(s.duration_sec, 0.0) AS duration_sec,
        COALESCE(s.turn_count, 0) AS turn_count,
        COALESCE(s.total_tokens, 0) AS total_tokens,
        COALESCE(s.skills_json, '[]') AS skills_json,
        COALESCE(s.search_read_calls, 0) AS search_read_calls,
        COALESCE(s.code_edit_calls, 0) AS code_edit_calls,
        COALESCE(s.verify_script_calls, 0) AS verify_script_calls,
        COALESCE(s.spin_rework_calls, 0) AS spin_rework_calls,
        COALESCE(s.files_changed_count, 0) AS files_changed_count,
        COALESCE(s.commits_count, 0) AS commits_count,
        s.pr_number,
        COALESCE(s.slow_or_failed_scripts_json, '[]') AS slow_or_failed_scripts_json,
        s.cst_day
    FROM fact_session_work_summary AS s
    CROSS JOIN bounds AS b
    WHERE s.cst_day BETWEEN b.start_day AND b.end_day
),
latest_goals AS (
    SELECT
        g.goal_id,
        g.title,
        COALESCE(NULLIF(g.derived_actual_status, ''), NULLIF(g.static_header_status, ''), 'active') AS goal_status,
        g.last_event_at,
        ROW_NUMBER() OVER (
            PARTITION BY g.goal_id
            ORDER BY COALESCE(g.last_event_at, '') DESC, g.goal_uid DESC
        ) AS rn
    FROM dim_goal AS g
),
goal_review_rounds AS (
    SELECT
        tr.goal_id,
        MAX(
            CASE
                WHEN tr.round_no IS NULL OR tr.round_no < 1 THEN 1
                -- Receipt naming convention *-r10.md denotes R10 receipt format, not round 10.
                WHEN tr.round_no = 10 THEN 1
                ELSE tr.round_no
            END
        ) AS max_round,
        MAX(
            CASE
                WHEN (tr.round_no IS NULL OR tr.round_no IN (1, 10))
                 AND (UPPER(COALESCE(tr.v5_verdict, '')) = 'FAIL' OR LOWER(COALESCE(tr.status, '')) = 'failed')
                THEN 1 ELSE 0
            END
        ) AS had_r1_fail
    FROM fact_gtt_task_run AS tr
    WHERE tr.goal_id IS NOT NULL AND tr.goal_id != ''
    GROUP BY tr.goal_id
),
session_ref_touches AS (
    SELECT
        LOWER(SUBSTR(r.session_id, 1, 8)) AS session_id_short,
        COUNT(DISTINCT r.hit_uid) AS ref_hit_count,
        GROUP_CONCAT(DISTINCT r.skill) AS ref_skills_csv
    FROM reference_hits AS r
    CROSS JOIN bounds AS b
    WHERE r.session_id IS NOT NULL
      AND LENGTH(r.session_id) >= 8
      AND (r.cst_day IS NULL OR r.cst_day BETWEEN b.start_day AND b.end_day)
    GROUP BY LOWER(SUBSTR(r.session_id, 1, 8))
),
session_script_touches AS (
    SELECT
        LOWER(SUBSTR(sc.session_id, 1, 8)) AS session_id_short,
        COUNT(DISTINCT sc.call_uid) AS script_call_count,
        SUM(CASE WHEN sc.exit_code IS NOT NULL AND sc.exit_code != 0 THEN 1 ELSE 0 END) AS failed_script_count,
        GROUP_CONCAT(DISTINCT sc.skill) AS script_skills_csv
    FROM script_call AS sc
    CROSS JOIN bounds AS b
    WHERE sc.session_id IS NOT NULL
      AND LENGTH(sc.session_id) >= 8
      AND (sc.cst_day IS NULL OR sc.cst_day BETWEEN b.start_day AND b.end_day)
    GROUP BY LOWER(SUBSTR(sc.session_id, 1, 8))
),
enriched_sessions AS (
    SELECT
        ws.session_uid,
        ws.source,
        ws.session_id_short,
        ws.effective_goal_id AS goal_id,
        ws.is_unassigned_bucket,
        ws.repo_name,
        ws.branch_name,
        ws.role_key,
        ws.model_id,
        ws.summary_label,
        ws.started_at,
        ws.ended_at,
        ws.duration_sec,
        ws.turn_count,
        ws.total_tokens,
        ws.skills_json,
        MAX(ws.search_read_calls, COALESCE(srt.ref_hit_count, 0)) AS search_read_calls,
        ws.code_edit_calls,
        MAX(ws.verify_script_calls, COALESCE(sst.script_call_count, 0)) AS verify_script_calls,
        MAX(ws.spin_rework_calls, COALESCE(sst.failed_script_count, 0)) AS spin_rework_calls,
        ws.files_changed_count,
        ws.commits_count,
        ws.pr_number,
        ws.slow_or_failed_scripts_json,
        COALESCE(srt.ref_hit_count, 0) AS ref_hit_count,
        COALESCE(sst.script_call_count, 0) AS script_call_count,
        srt.ref_skills_csv,
        sst.script_skills_csv,
        ws.cst_day
    FROM windowed_sessions AS ws
    LEFT JOIN session_ref_touches AS srt ON srt.session_id_short = ws.session_id_short
    LEFT JOIN session_script_touches AS sst ON sst.session_id_short = ws.session_id_short
),
goal_retro_watermarks AS (
    SELECT
        f.goal_id,
        SUM(CASE WHEN f.is_post_fix = 1 THEN f.occurrence_count ELSE 0 END) AS goal_post_fix_findings_count,
        SUM(CASE WHEN f.is_post_fix = 0 THEN f.occurrence_count ELSE 0 END) AS goal_pre_fix_findings_count,
        GROUP_CONCAT(
            DISTINCT f.skill || '|' || COALESCE(f.skill_version, '') || '|' || CAST(f.is_post_fix AS TEXT)
        ) AS goal_retro_watermarks_csv
    FROM fact_agent_retro_finding AS f
    CROSS JOIN bounds AS b
    WHERE f.goal_id IS NOT NULL
      AND f.goal_id != ''
      AND (f.cst_day IS NULL OR f.cst_day BETWEEN b.start_day AND b.end_day)
    GROUP BY f.goal_id
),
goal_rollups AS (
    SELECT
        es.goal_id,
        COUNT(*) AS goal_session_count,
        ROUND(SUM(es.duration_sec), 1) AS goal_duration_sec,
        SUM(es.total_tokens) AS goal_total_tokens,
        SUM(es.search_read_calls) AS goal_search_read_calls,
        SUM(es.code_edit_calls) AS goal_code_edit_calls,
        SUM(es.verify_script_calls) AS goal_verify_script_calls,
        SUM(es.spin_rework_calls) AS goal_spin_rework_calls,
        SUM(es.files_changed_count) AS goal_files_changed_count,
        SUM(es.commits_count) AS goal_commits_count,
        MAX(es.pr_number) AS goal_pr_number,
        SUM(es.ref_hit_count) AS goal_ref_hit_count,
        SUM(es.script_call_count) AS goal_script_call_count,
        MAX(es.repo_name) AS goal_repo_name,
        MAX(COALESCE(es.ended_at, es.started_at)) AS goal_latest_ts,
        MAX(es.cst_day) AS goal_latest_day
    FROM enriched_sessions AS es
    GROUP BY es.goal_id
),
population AS (
    SELECT
        COUNT(*) AS total_sessions,
        MAX(es.cst_day) AS latest_day
    FROM enriched_sessions AS es
)
SELECT
    es.session_uid,
    es.source,
    es.session_id_short,
    es.goal_id,
    es.is_unassigned_bucket,
    CASE
        WHEN es.is_unassigned_bucket = 1 THEN '日常独立会话（未绑定独立 Goal）'
        ELSE COALESCE(NULLIF(lg.title, ''), es.goal_id)
    END AS goal_title,
    COALESCE(es.repo_name, gr.goal_repo_name) AS repo_name,
    es.branch_name,
    CASE
        WHEN es.is_unassigned_bucket = 1 THEN 'daily'
        ELSE COALESCE(lg.goal_status, 'active')
    END AS goal_status,
    CASE
        WHEN es.is_unassigned_bucket = 1 OR grr.max_round IS NULL THEN NULL
        WHEN grr.max_round >= 3 THEN 'R3+'
        WHEN grr.max_round = 2 OR grr.had_r1_fail = 1 THEN 'R2'
        ELSE 'R1'
    END AS review_round_badge,
    es.role_key,
    es.model_id,
    es.summary_label,
    es.started_at,
    es.ended_at,
    es.duration_sec,
    es.turn_count,
    es.total_tokens,
    es.skills_json,
    es.search_read_calls,
    es.code_edit_calls,
    es.verify_script_calls,
    es.spin_rework_calls,
    es.files_changed_count,
    es.commits_count,
    es.pr_number,
    es.slow_or_failed_scripts_json,
    es.ref_hit_count,
    es.script_call_count,
    es.ref_skills_csv,
    es.script_skills_csv,
    CASE
        WHEN es.code_edit_calls > 0 THEN ROUND(1.0 * es.search_read_calls / es.code_edit_calls, 2)
        ELSE NULL
    END AS session_search_to_edit_ratio,
    gr.goal_session_count,
    gr.goal_duration_sec,
    gr.goal_total_tokens,
    gr.goal_search_read_calls,
    gr.goal_code_edit_calls,
    gr.goal_verify_script_calls,
    gr.goal_spin_rework_calls,
    gr.goal_files_changed_count,
    gr.goal_commits_count,
    gr.goal_pr_number,
    gr.goal_ref_hit_count,
    gr.goal_script_call_count,
    CASE
        WHEN gr.goal_code_edit_calls > 0 THEN ROUND(1.0 * gr.goal_search_read_calls / gr.goal_code_edit_calls, 2)
        ELSE NULL
    END AS goal_search_to_edit_ratio,
    gr.goal_latest_ts,
    gr.goal_latest_day,
    COALESCE(grw.goal_post_fix_findings_count, 0) AS goal_post_fix_findings_count,
    COALESCE(grw.goal_pre_fix_findings_count, 0) AS goal_pre_fix_findings_count,
    grw.goal_retro_watermarks_csv,
    es.cst_day,
    b.start_day AS window_start,
    b.end_day AS window_end,
    b.win_days || 'd' AS window_cst,
    p.latest_day AS source_as_of,
    p.total_sessions AS sample_size
FROM enriched_sessions AS es
JOIN goal_rollups AS gr ON gr.goal_id = es.goal_id
LEFT JOIN latest_goals AS lg ON lg.goal_id = es.goal_id AND lg.rn = 1
LEFT JOIN goal_review_rounds AS grr ON grr.goal_id = es.goal_id
LEFT JOIN goal_retro_watermarks AS grw ON grw.goal_id = es.goal_id
CROSS JOIN bounds AS b
CROSS JOIN population AS p
ORDER BY gr.goal_latest_ts DESC, es.is_unassigned_bucket ASC, COALESCE(es.ended_at, es.started_at) DESC, es.session_uid ASC;
