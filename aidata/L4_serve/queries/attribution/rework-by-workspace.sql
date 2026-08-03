-- attribution/rework-by-workspace — WHERE the rework is, not just how much.
--
-- `health/rework-rate` reports one number for the whole pipeline ("9.1% of
-- issues needed rework"). That tells you the cost exists but not where to look.
-- Splitting it by workspace makes it actionable: one workspace running at 2x
-- the other's rework rate is a place to investigate, a single global average is
-- not.
--
-- REWORK DEFINITION (same proxy as health/rework-rate, deliberately): an issue
-- whose multica_run history contains BOTH a cancelled run and a completed run
-- — work that was thrown away and redone. Keeping the definition identical
-- means this query drills into that number rather than inventing a second,
-- subtly different one.
--
-- WORKSPACE IS A UUID HERE, ON PURPOSE. The friendly names live in
-- config.MULTICA_WORKSPACES, which is gitignored (config_local.py) because
-- workspace ids are account-specific. Mapping them in SQL would either hardcode
-- private identifiers into a public repo or break on a fresh clone; L5 does the
-- lookup instead.
--
-- Bind :since as a CST date 'YYYY-MM-DD' (inclusive); NULL = all time.
WITH per_issue AS (
    SELECT t.issue_id,
           i.workspace_id,
           min(t.ts_start)                                       AS first_ts,
           max(CASE WHEN t.status = 'cancelled' THEN 1 ELSE 0 END) AS has_cancelled,
           max(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) AS has_completed,
           sum(COALESCE(t.tokens, 0))                            AS tokens
    FROM fact_task t
    JOIN fact_issue i ON i.issue_id = t.issue_id
    WHERE t.source = 'multica_run'
      AND t.issue_id IS NOT NULL
      AND t.ts_start IS NOT NULL
      AND i.workspace_id IS NOT NULL
    GROUP BY t.issue_id, i.workspace_id
),
scoped AS (
    SELECT * FROM per_issue
    WHERE :since IS NULL OR date(first_ts, '+8 hours') >= :since
)
SELECT workspace_id                                            AS workspace_id,
       count(*)                                                AS issues,
       sum(CASE WHEN has_cancelled = 1 AND has_completed = 1
                THEN 1 ELSE 0 END)                             AS rework_issues,
       round(100.0 * sum(CASE WHEN has_cancelled = 1 AND has_completed = 1
                              THEN 1 ELSE 0 END)
             / NULLIF(count(*), 0), 1)                         AS rework_pct,
       -- Tokens burned on issues that had to be redone: the price of the rate
       -- above, so a high percentage on tiny issues is not mistaken for a
       -- high percentage on expensive ones.
       round(sum(CASE WHEN has_cancelled = 1 AND has_completed = 1
                      THEN tokens ELSE 0 END) / 1000.0)         AS rework_ktok
FROM scoped
GROUP BY workspace_id
ORDER BY rework_issues DESC;
