-- S12: Top Context-Burning Tools & >10k Token Bloated Output Alert across recent 7-day turns.
WITH anchor AS (
    SELECT COALESCE(
        (SELECT MAX(cst_day) FROM fact_turn),
        date('now', '+8 hours')
    ) AS max_day
),
turn_tools_raw AS (
    SELECT
        t.turn_uuid,
        t.session_id,
        COALESCE(
            NULLIF(t.attribution_skill, ''),
            CASE
                WHEN t.skill_names IS NOT NULL AND t.skill_names != '' AND t.skill_names != '[]'
                THEN json_extract(t.skill_names, '$[0]')
                ELSE 'team-lead'
            END
        ) AS dominant_skill,
        LOWER(CAST(json_each.value AS TEXT)) AS raw_tool,
        COALESCE(t.input_tokens, 0) + COALESCE(t.cache_read, 0) + COALESCE(t.cache_creation, 0) AS turn_ctx_tokens,
        json_array_length(t.tool_calls) AS call_count,
        CAST(json_each.key AS INTEGER) AS tool_ord
    FROM fact_turn AS t, anchor, json_each(t.tool_calls)
    WHERE t.tool_calls IS NOT NULL AND t.tool_calls != '' AND t.tool_calls != '[]'
      AND t.cst_day > date(anchor.max_day, '-7 days')
      AND t.cst_day <= anchor.max_day
      AND json_each.value IS NOT NULL AND json_each.value != ''
),
normalized_calls AS (
    SELECT
        turn_uuid || ':' || COALESCE(tool_ord, 0) AS call_uid,
        turn_uuid,
        session_id,
        CASE
            WHEN dominant_skill = 'goal-target-task' THEN 'team-lead'
            ELSE COALESCE(dominant_skill, 'team-lead')
        END AS skill,
        CASE
            WHEN raw_tool IN ('bash', 'execute_code', 'terminal', 'run_command') THEN 'bash'
            WHEN raw_tool IN ('read', 'view', 'read_file') THEN 'read/view'
            WHEN raw_tool IN ('grep', 'search', 'rg') THEN 'grep'
            WHEN raw_tool IN ('edit', 'apply_patch', 'write', 'create') THEN 'edit/write'
            WHEN raw_tool LIKE '%web%' OR raw_tool LIKE '%fetch%' THEN 'web_fetch'
            WHEN raw_tool LIKE 'mcp%' OR raw_tool LIKE 'linear%' OR raw_tool LIKE 'github%' THEN 'mcp'
            ELSE raw_tool
        END AS tool_name,
        CAST(
            ROUND(
                (1.0 * turn_ctx_tokens * 0.36) / MAX(1, COALESCE(call_count, 1)),
                0
            ) AS INTEGER
        ) AS est_call_tokens
    FROM turn_tools_raw
),
tool_totals AS (
    SELECT SUM(est_call_tokens) AS grand_total_tokens
    FROM normalized_calls
),
tool_agg AS (
    SELECT
        tool_name,
        COUNT(*) AS call_count,
        SUM(est_call_tokens) AS total_tokens,
        SUM(CASE WHEN est_call_tokens > 10000 THEN 1 ELSE 0 END) AS bloated_call_count,
        (
            SELECT nc2.skill
            FROM normalized_calls AS nc2
            WHERE nc2.tool_name = nc1.tool_name
            GROUP BY nc2.skill
            ORDER BY SUM(CASE WHEN nc2.est_call_tokens > 10000 THEN 1 ELSE 0 END) DESC,
                     SUM(nc2.est_call_tokens) DESC,
                     nc2.skill ASC
            LIMIT 1
        ) AS dominant_skill
    FROM normalized_calls AS nc1
    GROUP BY tool_name
),
tool_p95 AS (
    SELECT
        nc.tool_name,
        MIN(nc.est_call_tokens) AS p95_tokens
    FROM (
        SELECT
            tool_name,
            est_call_tokens,
            (
                SELECT COUNT(*)
                FROM normalized_calls AS b
                WHERE b.tool_name = a.tool_name
                  AND (b.est_call_tokens < a.est_call_tokens
                       OR (b.est_call_tokens = a.est_call_tokens AND b.call_uid <= a.call_uid))
            ) AS rn,
            (
                SELECT COUNT(*)
                FROM normalized_calls AS c
                WHERE c.tool_name = a.tool_name
            ) AS cnt
        FROM normalized_calls AS a
    ) AS nc
    WHERE nc.rn >= CAST((nc.cnt * 95 + 99) / 100 AS INTEGER)
    GROUP BY nc.tool_name
)
SELECT
    a.tool_name AS tool_name,
    a.call_count AS call_count,
    a.total_tokens AS total_tokens,
    COALESCE(p.p95_tokens, 0) AS p95_tokens,
    a.bloated_call_count AS bloated_call_count,
    ROUND(
        100.0 * a.total_tokens / NULLIF(t.grand_total_tokens, 0),
        1
    ) AS share_pct,
    COALESCE(a.dominant_skill, 'team-lead') AS dominant_skill
FROM tool_agg AS a
LEFT JOIN tool_p95 AS p ON p.tool_name = a.tool_name
CROSS JOIN tool_totals AS t
ORDER BY a.total_tokens DESC, a.tool_name ASC;
