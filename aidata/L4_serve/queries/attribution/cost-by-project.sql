-- attribution/cost-by-project — WHERE the day's spend actually went.
--
-- This answers the question the dashboard could not: "cost is up 968%" tells
-- you nothing actionable, "AIDash 41% / VitalStride 24%" tells you where to
-- look. It is the ⑤「为什么」(attribution) layer from the 2026-07-17 layered
-- metrics design — every other trend card is single-dimension.
--
-- HOW THE JOIN WORKS. Spend lives in fact_request (raven), project lives in
-- fact_turn (claude transcripts). They meet on session:
--   fact_turn.session_id -> fact_request.session_uuid   (measured 99.99%)
-- This is the warehouse's strongest bridge — see the honest-keys table in
-- docs/specs/2026-08-02-warehouse-audit.md. The two weak bridges
-- (fact_task.pr_url at 0.03%, fact_task.session_id at 13%) are deliberately
-- NOT used here.
--
-- WHY THE COST IS WEIGHTED, NOT SUMMED. A session touches 1.68 projects on
-- average (measured: 53 sessions, 89 project attachments on 2026-08-02).
-- Attributing a session's full cost to each project it touched would
-- double-count — the naive version summed to 200%+ of the real total. So each
-- session's spend is split across its projects in proportion to how many turns
-- landed in each. Verified conservative: allocated total == attributable total
-- exactly (3748.77 == 3748.77 on the sample day).
--
-- HONEST COVERAGE. Only sessions with BOTH a resolvable session_uuid and a
-- project are attributable; on the sample day that is 98.4% of spend
-- (3748.77 of 3809.59). Requests from codex/multica carry no conversation id
-- (raven records none), so their spend is out of scope here rather than
-- silently folded into an arbitrary project.
--
-- Bind :day as a CST date 'YYYY-MM-DD'; NULL falls back to the whole history.
WITH session_cost AS (
    SELECT session_uuid          AS sid,
           sum(COALESCE(cost_usd, 0)) AS cost,
           sum(COALESCE(total_tokens, 0)) AS tokens,
           count(*)              AS requests
    FROM fact_request
    WHERE session_uuid IS NOT NULL
      AND (:day IS NULL OR cst_day = :day)
    GROUP BY session_uuid
),
-- The day's TOTAL spend (all requests, whether attributable or not).
-- This is the denominator readers expect when they see a percentage on a cost
-- card: "41% of what I spent today", not "41% of the portion we could trace".
day_total AS (
    SELECT COALESCE(sum(COALESCE(cost_usd, 0)), 0) AS total
    FROM fact_request
    WHERE :day IS NULL OR cst_day = :day
),
-- Each session's turn mix, as weights summing to 1.0 per session.
project_weight AS (
    SELECT session_id AS sid,
           project,
           count(*) * 1.0
             / sum(count(*)) OVER (PARTITION BY session_id) AS weight
    FROM fact_turn
    WHERE project IS NOT NULL AND project != ''
      AND (:day IS NULL OR cst_day = :day)
    GROUP BY session_id, project
),
allocated AS (
    SELECT w.project,
           sum(c.cost * w.weight)     AS cost_usd,
           sum(c.tokens * w.weight)   AS tokens,
           sum(c.requests * w.weight) AS requests,
           count(DISTINCT c.sid)      AS sessions
    FROM session_cost c
    JOIN project_weight w ON w.sid = c.sid
    GROUP BY w.project
), rows AS (
    SELECT project                                              AS project,
           round(cost_usd, 2)                                   AS cost_usd,
           round(100.0 * cost_usd
                 / NULLIF((SELECT total FROM day_total), 0), 1) AS cost_pct,
           round(tokens / 1000.0, 1)                            AS ktokens,
           round(requests)                                      AS requests,
           sessions                                             AS sessions,
           round((SELECT total FROM day_total), 2)              AS day_total,
           round((SELECT sum(cost_usd) FROM allocated), 2)      AS attributed_total
    FROM allocated

    UNION ALL

    SELECT NULL AS project,
           0.0 AS cost_usd,
           0.0 AS cost_pct,
           0.0 AS ktokens,
           0 AS requests,
           0 AS sessions,
           round((SELECT total FROM day_total), 2) AS day_total,
           0.0 AS attributed_total
    FROM day_total
    WHERE NOT EXISTS (SELECT 1 FROM allocated)
)
SELECT project,
       cost_usd,
       cost_pct,
       ktokens,
       requests,
       sessions,
       day_total,
       attributed_total
FROM rows
WHERE project IS NOT NULL OR (SELECT total FROM day_total) > 0
ORDER BY cost_usd DESC;
