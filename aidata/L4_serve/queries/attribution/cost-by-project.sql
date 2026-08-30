-- aidata-tier: production
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
WITH request_totals AS (
    SELECT sum(COALESCE(cost_usd, 0)) AS day_total,
           sum(COALESCE(total_tokens, 0)) AS day_tokens,
           count(*) AS day_requests,
           count(DISTINCT CASE WHEN session_uuid IS NOT NULL THEN session_uuid END) AS day_sessions
    FROM fact_request
    WHERE (:day IS NULL OR cst_day = :day)
),
session_cost AS (
    SELECT session_uuid          AS sid,
           sum(COALESCE(cost_usd, 0)) AS cost,
           sum(COALESCE(total_tokens, 0)) AS tokens,
           count(*)              AS requests
    FROM fact_request
    WHERE session_uuid IS NOT NULL
      AND (:day IS NULL OR cst_day = :day)
    GROUP BY session_uuid
),
-- Each session's turn mix, as weights summing to 1.0 per session. Blank/null
-- project labels stay in the session's denominator so they remain visible as
-- residual spend instead of being silently folded into a valid project.
project_weight AS (
    SELECT session_id AS sid,
           NULLIF(TRIM(project), '') AS project,
           count(*) * 1.0
             / sum(count(*)) OVER (PARTITION BY session_id) AS weight
    FROM fact_turn
    WHERE (:day IS NULL OR cst_day = :day)
    GROUP BY session_id, NULLIF(TRIM(project), '')
),
allocated AS (
    SELECT w.project,
           'project' AS bucket,
           sum(c.cost * w.weight)     AS cost_usd,
           sum(c.tokens * w.weight)   AS tokens,
           sum(c.requests * w.weight) AS requests,
           count(DISTINCT c.sid)      AS sessions
    FROM session_cost c
    JOIN project_weight w ON w.sid = c.sid
    WHERE w.project IS NOT NULL
    GROUP BY w.project
),
allocated_totals AS (
    SELECT sum(cost_usd) AS attributed_total,
           sum(tokens) AS attributed_tokens,
           sum(requests) AS attributed_requests,
           sum(sessions) AS attributed_sessions
    FROM allocated
),
residual_sessions AS (
    SELECT count(DISTINCT sid) AS residual_sessions
    FROM (
        SELECT s.sid,
               MAX(CASE
                       WHEN EXISTS (
                           SELECT 1
                           FROM fact_turn t
                           WHERE t.session_id = s.sid
                             AND NULLIF(TRIM(t.project), '') IS NULL
                       ) THEN 1
                       ELSE 0
                   END) AS has_unmapped_turn,
               COALESCE(sum(CASE WHEN w.project IS NOT NULL THEN w.weight ELSE 0 END), 0) AS valid_project_weight
        FROM session_cost s
        LEFT JOIN project_weight w ON w.sid = s.sid
        GROUP BY s.sid
    ) attributed_sessions
    WHERE has_unmapped_turn = 1
       OR valid_project_weight < 1.0 - 1e-9
),
day_summary AS (
    SELECT r.day_total,
           r.day_tokens,
           r.day_requests,
           r.day_sessions,
           COALESCE(a.attributed_total, 0) AS attributed_total,
           COALESCE(a.attributed_tokens, 0) AS attributed_tokens,
           COALESCE(a.attributed_requests, 0) AS attributed_requests,
           COALESCE(a.attributed_sessions, 0) AS attributed_sessions,
           COALESCE(rs.residual_sessions, 0) AS residual_sessions
    FROM request_totals r
    LEFT JOIN allocated_totals a ON 1 = 1
    LEFT JOIN residual_sessions rs ON 1 = 1
),
unattributed AS (
    SELECT 'unattributed' AS project,
           'residual' AS bucket,
           round((SELECT day_total FROM day_summary) -
                 (SELECT attributed_total FROM day_summary), 2) AS cost_usd,
           round(100.0 * (
                 (SELECT day_total FROM day_summary) -
                 (SELECT attributed_total FROM day_summary)
           ) / NULLIF((SELECT day_total FROM day_summary), 0), 1) AS cost_pct,
           round(((SELECT day_tokens FROM day_summary) -
                  (SELECT attributed_tokens FROM day_summary)) / 1000.0, 1) AS ktokens,
           round((SELECT day_requests FROM day_summary) -
                 (SELECT attributed_requests FROM day_summary)) AS requests,
           (SELECT residual_sessions FROM day_summary) AS sessions,
           round((SELECT day_total FROM day_summary), 2) AS day_total,
           round((SELECT attributed_total FROM day_summary), 2) AS attributed_total
    FROM day_summary
    WHERE (SELECT day_total FROM day_summary) > 0
      AND ((SELECT day_total FROM day_summary) -
           (SELECT attributed_total FROM day_summary)) > 0
)
SELECT project,
       bucket,
       round(cost_usd, 2) AS cost_usd,
       round(100.0 * cost_usd / NULLIF((SELECT day_total FROM day_summary), 0), 1) AS cost_pct,
       round(tokens / 1000.0, 1) AS ktokens,
       round(requests) AS requests,
       sessions,
       round((SELECT day_total FROM day_summary), 2) AS day_total,
       round((SELECT attributed_total FROM day_summary), 2) AS attributed_total
FROM allocated
UNION ALL
SELECT project,
       bucket,
       cost_usd,
       cost_pct,
       ktokens,
       requests,
       sessions,
       day_total,
       attributed_total
FROM unattributed
ORDER BY cost_usd DESC;
