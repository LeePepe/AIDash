-- aidata-tier: explore
-- Rolling CST window (default 14 days) 6-layer agent trajectory health:
-- pre-fix vs post-fix anomaly counts, role/skill attributions, and latest vN@sha watermark.
WITH anchor AS (
    SELECT COALESCE(
        :until_day,
        (SELECT MAX(f.cst_day) FROM fact_agent_retro_finding AS f WHERE f.cst_day IS NOT NULL),
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
layer_catalog(layer_key, sort_order) AS (
    VALUES
        ('role',     1),
        ('handoff',  2),
        ('invoke',   3),
        ('exec',     4),
        ('friction', 5),
        ('horizon',  6)
),
windowed_findings AS (
    SELECT
        f.finding_uid,
        f.session_id,
        f.goal_id,
        f.role_key,
        f.skill,
        f.layer_key,
        f.finding_code,
        f.severity,
        f.skill_version,
        f.is_post_fix,
        f.occurrence_count,
        f.ts,
        f.cst_day
    FROM fact_agent_retro_finding AS f
    CROSS JOIN bounds AS b
    WHERE f.cst_day BETWEEN b.start_day AND b.end_day
),
population AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(DISTINCT wf.session_id) AS total_sessions,
        MAX(wf.cst_day) AS latest_day
    FROM windowed_findings AS wf
),
layer_totals AS (
    SELECT
        wf.layer_key,
        COUNT(*) AS finding_rows,
        COUNT(DISTINCT wf.session_id) AS affected_sessions,
        SUM(CASE WHEN wf.is_post_fix = 0 THEN wf.occurrence_count ELSE 0 END) AS pre_fix_count,
        SUM(CASE WHEN wf.is_post_fix = 1 THEN wf.occurrence_count ELSE 0 END) AS post_fix_count,
        SUM(wf.occurrence_count) AS total_occurrences,
        SUM(CASE WHEN wf.severity IN ('critical', 'high') AND wf.is_post_fix = 1 THEN wf.occurrence_count ELSE 0 END) AS high_severity_post_fix_count,
        MAX(wf.cst_day) AS layer_as_of
    FROM windowed_findings AS wf
    GROUP BY wf.layer_key
),
role_ranks AS (
    SELECT
        wf.layer_key,
        wf.role_key,
        SUM(wf.occurrence_count) AS occ_sum,
        ROW_NUMBER() OVER (
            PARTITION BY wf.layer_key
            ORDER BY SUM(wf.occurrence_count) DESC, wf.role_key ASC
        ) AS rn
    FROM windowed_findings AS wf
    GROUP BY wf.layer_key, wf.role_key
),
skill_ranks AS (
    SELECT
        wf.layer_key,
        wf.skill,
        MAX(wf.skill_version) AS latest_skill_version,
        SUM(wf.occurrence_count) AS occ_sum,
        ROW_NUMBER() OVER (
            PARTITION BY wf.layer_key
            ORDER BY SUM(CASE WHEN wf.is_post_fix = 1 THEN wf.occurrence_count ELSE 0 END) DESC,
                     SUM(wf.occurrence_count) DESC,
                     wf.skill ASC
        ) AS rn
    FROM windowed_findings AS wf
    GROUP BY wf.layer_key, wf.skill
)
SELECT
    c.layer_key,
    c.sort_order,
    COALESCE(lt.finding_rows, 0) AS finding_rows,
    COALESCE(lt.affected_sessions, 0) AS affected_sessions,
    COALESCE(lt.pre_fix_count, 0) AS pre_fix_count,
    COALESCE(lt.post_fix_count, 0) AS post_fix_count,
    COALESCE(lt.total_occurrences, 0) AS total_occurrences,
    COALESCE(lt.high_severity_post_fix_count, 0) AS high_severity_post_fix_count,
    rr.role_key AS top_role_key,
    sr.skill AS top_skill,
    sr.latest_skill_version AS top_skill_version,
    b.start_day AS window_start,
    b.end_day AS window_end,
    b.win_days || 'd' AS window_cst,
    p.latest_day AS source_as_of,
    COALESCE(p.total_sessions, 0) AS sample_size,
    CASE
        WHEN COALESCE(p.total_rows, 0) > 0 THEN 'covered'
        ELSE 'unknown'
    END AS coverage_status
FROM layer_catalog AS c
CROSS JOIN bounds AS b
CROSS JOIN population AS p
LEFT JOIN layer_totals AS lt ON lt.layer_key = c.layer_key
LEFT JOIN role_ranks AS rr ON rr.layer_key = c.layer_key AND rr.rn = 1
LEFT JOIN skill_ranks AS sr ON sr.layer_key = c.layer_key AND sr.rn = 1
ORDER BY c.sort_order ASC;
