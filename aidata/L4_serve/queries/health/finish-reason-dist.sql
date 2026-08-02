-- health/finish-reason-dist — per-CST-day distribution of assistant-turn finish
-- reasons, with the truncation (max_tokens) share broken out as a quality signal.
-- Source: fact_turn.finish_reason (= claude_jsonl message.stop_reason, wired
-- through L3). fact_turn is a MERGED source, so we read the warehouse table
-- directly — NOT an ATTACHed clean DB (claude_jsonl is in MERGE_SOURCES, so
-- serve.py does not attach clean/claude_jsonl.db). Turns with a NULL
-- finish_reason (streaming/control frames) are excluded from the rate so the
-- percentages describe only turns that actually reported a reason.
--
-- max_tokens = the model hit its output cap and was truncated → the response is
-- likely incomplete: max_tokens_pct trending up is a degradation signal.
-- Buckets on fact_turn.cst_day (generated from ts; see schema).
SELECT cst_day                                               AS day,
       count(*)                                              AS turns_with_reason,
       sum(CASE WHEN finish_reason = 'end_turn'  THEN 1 ELSE 0 END) AS end_turn,
       sum(CASE WHEN finish_reason = 'tool_use'  THEN 1 ELSE 0 END) AS tool_use,
       sum(CASE WHEN finish_reason = 'max_tokens' THEN 1 ELSE 0 END) AS max_tokens,
       sum(CASE WHEN finish_reason NOT IN ('end_turn', 'tool_use', 'max_tokens')
                THEN 1 ELSE 0 END)                           AS other,
       round(100.0 * sum(CASE WHEN finish_reason = 'max_tokens' THEN 1 ELSE 0 END)
             / NULLIF(count(*), 0), 2)                       AS max_tokens_pct
FROM fact_turn
WHERE finish_reason IS NOT NULL
GROUP BY cst_day
ORDER BY day DESC;
