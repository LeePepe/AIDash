-- health/rework-rate — DORA 2024 rework trend: the SHARE of issues that needed
-- rework, bucketed by CST week. Complementary to (not a duplicate of)
-- rework-loops.sql and rework-threads.sql, which are per-issue CLINIC LISTS;
-- this is the aggregate RATE over time (rework_issues / total_issues per week),
-- the DORA "rework rate" trend line.
--
-- Rework definition (same proxy as rework-loops): an issue whose multica_run
-- history contains BOTH a cancelled run and a completed run — work that was
-- thrown away and redone. Each issue is bucketed by the CST week of its FIRST
-- run (min ts_start), so an issue counts once.
--
-- NOTE: this one keeps the inline `+8 hours` on purpose. fact_task.cst_day is a
-- per-ROW generated column, but the bucket key here is min(ts_start) computed
-- ACROSS rows — an aggregate result, which no stored column can carry. Taking
-- min(cst_day) would coincide only because both are monotonic in ts_start;
-- converting the aggregate keeps the intent explicit. strftime %Y-%W then gives
-- the ISO-ish week key. NULLIF guards the per-week denominator (degrade-safe).
WITH per_issue AS (
  SELECT issue_id,
         min(ts_start)                                       AS first_ts,
         max(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS has_cancelled,
         max(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS has_completed
  FROM fact_task
  WHERE source = 'multica_run' AND issue_id IS NOT NULL AND ts_start IS NOT NULL
  GROUP BY issue_id
),
bucketed AS (
  SELECT strftime('%Y-W%W', date(first_ts, '+8 hours'))     AS week,
         CASE WHEN has_cancelled = 1 AND has_completed = 1
              THEN 1 ELSE 0 END                              AS is_rework
  FROM per_issue
)
SELECT week,
       count(*)                                              AS total_issues,
       sum(is_rework)                                        AS rework_issues,
       round(100.0 * sum(is_rework) / NULLIF(count(*), 0), 1) AS rework_rate_pct
FROM bucketed
GROUP BY week
ORDER BY week DESC;
