-- attribution/tool-cross — which tools cost the most, and who runs them.
-- aidata-attach: hermes_messages state_db
--
-- `hermes_tools` has sat at L2 with no consumer because a bare "terminal was
-- called 2577 times" answers nothing. This crosses tool usage with the two
-- dimensions that make it mean something:
--
--   1. TOKENS PER CALL — magnitude. Measured: execute_code averages 11.9 Ktok
--      per call versus write_file's 4.8, so a handful of code executions can
--      outweigh thousands of file writes.
--   2. AUTOMATED SHARE — who is driving. Measured: write_file is 86% automated
--      while execute_code is 0%. That difference says which parts of the
--      workflow have actually been handed off and which still need a human.
--
-- WHY NOT `hermes_tools`. That source aggregates to (day, tool_name) and drops
-- session_id, so it cannot be joined to anything — the grain destroys the very
-- key a cross needs. `hermes_messages` (collected later) keeps session_id, so
-- it is read instead. hermes_tools remains a cheap daily rollup.
--
-- THE JOIN. hermes_messages.session_id -> state_db.session.session_id resolves
-- for 4,018 of 4,035 tool-bearing sessions (measured: 100%, both being Hermes's
-- own ids). Note this is NOT joinable to fact_request: Hermes ids look like
-- `20260520_152023_176329` while raven's are UUIDs — different namespaces, zero
-- overlap. So this stays inside the Hermes world by necessity, not by choice.
--
-- TOKENS, NOT DOLLARS. state_db.estimated_cost_usd is present on 11,896 rows
-- but sums to exactly 0.0, and actual_cost_usd is entirely NULL — Hermes never
-- populates them. Tokens are fully populated (790M), so magnitude is expressed
-- in tokens. Do not "fix" this by pricing tokens here: cost derivation is
-- adapters/raven.py::_cost()'s job and raven has no visibility into these
-- sessions.
--
-- ALLOCATION. A session's tokens are split across its tools in proportion to
-- call counts — the same weighting rule used by attribution/cost-by-project,
-- and for the same reason: a session uses several tools, so attributing its
-- full token count to each would multiply the total.
--
-- Bind :since as a CST date 'YYYY-MM-DD' (inclusive); NULL = all time.
WITH per_session_tool AS (
    SELECT m.session_id      AS sid,
           m.tool_name       AS tool,
           count(*)          AS calls
    FROM hermes_messages.message m
    WHERE m.tool_name IS NOT NULL
      AND (:since IS NULL OR m.day >= :since)
    GROUP BY m.session_id, m.tool_name
),
session_total AS (
    SELECT sid, sum(calls) AS total_calls
    FROM per_session_tool
    GROUP BY sid
)
SELECT p.tool                                                   AS tool,
       sum(p.calls)                                             AS calls,
       count(DISTINCT p.sid)                                    AS sessions,
       round(sum((COALESCE(s.input_tokens, 0) + COALESCE(s.output_tokens, 0))
                 * p.calls / NULLIF(t.total_calls, 0)) / 1e6, 2) AS mtokens,
       -- The headline: what one call of this tool actually drags along.
       round(sum((COALESCE(s.input_tokens, 0) + COALESCE(s.output_tokens, 0))
                 * p.calls / NULLIF(t.total_calls, 0))
             / NULLIF(sum(p.calls), 0) / 1000.0, 1)             AS ktok_per_call,
       round(100.0 * sum(CASE WHEN s.is_automated = 1 THEN p.calls ELSE 0 END)
             / NULLIF(sum(p.calls), 0), 0)                      AS automated_pct
FROM per_session_tool p
JOIN session_total t ON t.sid = p.sid
JOIN state_db.session s ON s.session_id = p.sid
GROUP BY p.tool
ORDER BY calls DESC;
