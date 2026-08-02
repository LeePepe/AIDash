-- aidata-attach: hermes_tools
-- tools/usage-rank — tool-call volume ranked by tool, descending (feeds a barList
-- if surfaced, and the "工具调用分布" signal). Source: hermes_tools.tool_day, a
-- L2-only clean DB ATTACHed directly by serve.py as `hermes_tools` (ADR-13), read
-- directly like daily-automation.sql reads state_db — not a MERGE_SOURCE, no
-- warehouse table.
--
-- tool_day is already a per-(day, tool_name) rollup with n = call count, so this
-- query just re-aggregates across the window into a per-tool total. day is a plain
-- CST date string 'YYYY-MM-DD' (the adapter already bucketed to CST), so bind
-- :since (inclusive) / :until (exclusive) as CST dates and compare directly — NO
-- '+8 hours' shift here (day is not a timestamp). NULL → all-time (serve.py
-- auto-binds missing params to NULL). Ordered calls-desc; the ≥9-category "Other"
-- fold is done in the L5 producer (top N + Other), NOT here, so this stays a clean
-- full ranking. Empty → no rows (degrade-safe: producer omits the card, ADR-23).
SELECT
    tool_name                                                   AS tool,
    sum(COALESCE(n, 0))                                         AS calls,
    count(DISTINCT day)                                         AS active_days
FROM hermes_tools.tool_day
WHERE tool_name IS NOT NULL AND tool_name != ''
  AND (:since IS NULL OR day >= :since)
  AND (:until IS NULL OR day <  :until)
GROUP BY tool_name
HAVING sum(COALESCE(n, 0)) > 0
ORDER BY calls DESC, tool ASC;
