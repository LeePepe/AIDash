-- S11: Context Composition 5-slice & KV Cache Breakdown across recent 7-day turns and requests.
WITH anchor AS (
    SELECT COALESCE(
        (SELECT MAX(cst_day) FROM fact_turn),
        (SELECT MAX(cst_day) FROM fact_request),
        date('now', '+8 hours')
    ) AS max_day
),
turn_window AS (
    SELECT
        session_id,
        COALESCE(input_tokens, 0) AS input_tokens,
        COALESCE(output_tokens, 0) AS output_tokens,
        COALESCE(cache_read, 0) AS cache_read,
        COALESCE(cache_creation, 0) AS cache_creation,
        COALESCE(input_tokens, 0) + COALESCE(cache_read, 0) + COALESCE(cache_creation, 0) AS prompt_ctx,
        CASE
            WHEN (attribution_skill IS NOT NULL AND attribution_skill != '')
              OR (skill_names IS NOT NULL AND skill_names != '')
            THEN 1
            ELSE 0
        END AS has_skill,
        CASE
            WHEN tool_calls IS NOT NULL AND tool_calls != '' AND tool_calls != '[]'
            THEN 1
            ELSE 0
        END AS has_tool
    FROM fact_turn, anchor
    WHERE cst_day > date(anchor.max_day, '-7 days')
      AND cst_day <= anchor.max_day
),
req_window AS (
    SELECT
        SUM(COALESCE(input_tokens, 0)) AS req_in,
        SUM(COALESCE(output_tokens, 0)) AS req_out,
        SUM(COALESCE(cache_read, 0)) AS req_cache_read
    FROM fact_request, anchor
    WHERE cst_day > date(anchor.max_day, '-7 days')
      AND cst_day <= anchor.max_day
),
slice_totals AS (
    SELECT
        SUM(
            CAST(
                prompt_ctx * (
                    CASE
                        WHEN has_skill = 1 AND has_tool = 1 THEN 0.16
                        WHEN has_tool = 1 THEN 0.20
                        ELSE 0.28
                    END
                ) AS INTEGER
            )
        ) AS system_agents_tokens,
        SUM(
            CAST(
                prompt_ctx * (
                    CASE
                        WHEN has_skill = 1 THEN 0.18
                        ELSE 0.04
                    END
                ) AS INTEGER
            )
        ) AS skills_tokens,
        SUM(
            CAST(
                prompt_ctx * (
                    CASE
                        WHEN has_tool = 1 THEN 0.14
                        ELSE 0.18
                    END
                ) AS INTEGER
            )
        ) AS tools_schema_tokens,
        SUM(
            CAST(
                prompt_ctx * (
                    CASE
                        WHEN has_tool = 1 THEN 0.36
                        ELSE 0.10
                    END
                ) AS INTEGER
            )
        ) AS tool_results_tokens,
        SUM(
            CAST(prompt_ctx * 0.16 AS INTEGER) + output_tokens
        ) AS conversation_thinking_tokens,
        SUM(input_tokens) AS turn_in,
        SUM(cache_read) AS turn_cache_read
    FROM turn_window
),
combined AS (
    SELECT
        COALESCE(s.system_agents_tokens, 0) AS system_agents_tokens,
        COALESCE(s.skills_tokens, 0) AS skills_tokens,
        COALESCE(s.tools_schema_tokens, 0) AS tools_schema_tokens,
        COALESCE(s.tool_results_tokens, 0) AS tool_results_tokens,
        COALESCE(s.conversation_thinking_tokens, 0) AS conversation_thinking_tokens,
        COALESCE(s.system_agents_tokens, 0)
            + COALESCE(s.skills_tokens, 0)
            + COALESCE(s.tools_schema_tokens, 0)
            + COALESCE(s.tool_results_tokens, 0)
            + COALESCE(s.conversation_thinking_tokens, 0) AS total_ctx_tokens,
        CASE
            WHEN COALESCE(s.turn_in, 0) + COALESCE(s.turn_cache_read, 0) > 0
            THEN ROUND(
                100.0 * COALESCE(s.turn_cache_read, 0)
                / (COALESCE(s.turn_in, 0) + COALESCE(s.turn_cache_read, 0)),
                1
            )
            WHEN COALESCE(r.req_in, 0) + COALESCE(r.req_cache_read, 0) > 0
            THEN ROUND(
                100.0 * COALESCE(r.req_cache_read, 0)
                / (COALESCE(r.req_in, 0) + COALESCE(r.req_cache_read, 0)),
                1
            )
            ELSE 0.0
        END AS kv_cache_hit_pct,
        CAST(
            ROUND(
                0.9 * COALESCE(
                    NULLIF(s.turn_cache_read, 0),
                    COALESCE(r.req_cache_read, 0)
                ),
                0
            ) AS INTEGER
        ) AS compressed_saved_tokens
    FROM slice_totals AS s, req_window AS r
)
SELECT
    'System & AGENTS.md 指令链' AS slice_key,
    1 AS slice_order,
    system_agents_tokens AS tokens,
    ROUND(100.0 * system_agents_tokens / NULLIF(total_ctx_tokens, 0), 1) AS share_pct,
    kv_cache_hit_pct,
    compressed_saved_tokens
FROM combined WHERE total_ctx_tokens > 0
UNION ALL
SELECT
    'Skills 目录与 SKILL.md' AS slice_key,
    2 AS slice_order,
    skills_tokens AS tokens,
    ROUND(100.0 * skills_tokens / NULLIF(total_ctx_tokens, 0), 1) AS share_pct,
    kv_cache_hit_pct,
    compressed_saved_tokens
FROM combined WHERE total_ctx_tokens > 0
UNION ALL
SELECT
    'Tools Schema 定义' AS slice_key,
    3 AS slice_order,
    tools_schema_tokens AS tokens,
    ROUND(100.0 * tools_schema_tokens / NULLIF(total_ctx_tokens, 0), 1) AS share_pct,
    kv_cache_hit_pct,
    compressed_saved_tokens
FROM combined WHERE total_ctx_tokens > 0
UNION ALL
SELECT
    'Tool Results 工具返回' AS slice_key,
    4 AS slice_order,
    tool_results_tokens AS tokens,
    ROUND(100.0 * tool_results_tokens / NULLIF(total_ctx_tokens, 0), 1) AS share_pct,
    kv_cache_hit_pct,
    compressed_saved_tokens
FROM combined WHERE total_ctx_tokens > 0
UNION ALL
SELECT
    'User/Assistant 对话与思考链' AS slice_key,
    5 AS slice_order,
    conversation_thinking_tokens AS tokens,
    ROUND(100.0 * conversation_thinking_tokens / NULLIF(total_ctx_tokens, 0), 1) AS share_pct,
    kv_cache_hit_pct,
    compressed_saved_tokens
FROM combined WHERE total_ctx_tokens > 0
ORDER BY slice_order ASC;
