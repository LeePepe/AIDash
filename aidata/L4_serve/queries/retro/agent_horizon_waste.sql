-- aidata-tier: explore
-- Rolling CST window (default 14 days) long-horizon waste aggregation by category, role, and skill.
WITH anchor AS (
    SELECT COALESCE(
        :until_day,
        (SELECT MAX(w.cst_day) FROM fact_agent_horizon_waste AS w WHERE w.cst_day IS NOT NULL),
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
windowed_waste AS (
    SELECT
        w.waste_uid,
        w.session_id,
        w.role_key,
        w.skill,
        w.horizon_code,
        w.category_key,
        w.wasted_turns,
        w.wasted_tokens,
        w.duration_sec,
        w.cst_day
    FROM fact_agent_horizon_waste AS w
    CROSS JOIN bounds AS b
    WHERE w.cst_day BETWEEN b.start_day AND b.end_day
),
totals AS (
    SELECT
        COALESCE(SUM(ww.wasted_turns), 0) AS grand_wasted_turns,
        COALESCE(SUM(ww.wasted_tokens), 0) AS grand_wasted_tokens,
        COUNT(DISTINCT ww.session_id) AS total_sessions,
        MAX(ww.cst_day) AS latest_day
    FROM windowed_waste AS ww
)
SELECT
    ww.category_key,
    ww.role_key,
    ww.skill,
    COUNT(*) AS event_count,
    COUNT(DISTINCT ww.session_id) AS affected_sessions,
    SUM(ww.wasted_turns) AS wasted_turns,
    SUM(ww.wasted_tokens) AS wasted_tokens,
    ROUND(SUM(ww.duration_sec), 1) AS duration_sec,
    CASE
        WHEN t.grand_wasted_tokens > 0
            THEN ROUND(100.0 * SUM(ww.wasted_tokens) / t.grand_wasted_tokens, 2)
        ELSE 0.0
    END AS token_share_pct,
    b.start_day AS window_start,
    b.end_day AS window_end,
    b.win_days || 'd' AS window_cst,
    t.latest_day AS source_as_of,
    t.total_sessions AS sample_size
FROM windowed_waste AS ww
CROSS JOIN bounds AS b
CROSS JOIN totals AS t
GROUP BY ww.category_key, ww.role_key, ww.skill, b.start_day, b.end_day, b.win_days, t.grand_wasted_tokens, t.latest_day, t.total_sessions
ORDER BY SUM(ww.wasted_tokens) DESC, SUM(ww.wasted_turns) DESC, ww.category_key ASC, ww.skill ASC;
