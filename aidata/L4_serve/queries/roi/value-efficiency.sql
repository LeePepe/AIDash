-- roi/value-efficiency — research-backed "值不值/效率" metrics over a window.
-- NOT a naive cost-per-issue ratio (misleads: output is nearly free, LOC tracks
-- token spend not value — research 2026-07-18). Two computable signals:
--   cost_per_completed_task = Σcost(ALL requests, incl. failed-task spend)
--                             / count(completed tasks)   ← true per-task cost
--   output_share_pct        = output_tokens / total_tokens ← low ⇒ input/context
--                             -dominated spend (agentic cost is input-driven)
-- Bind :since as a CST date 'YYYY-MM-DD' (inclusive). Defaults to all-time.
-- cache-read ratio (the 3rd recommended metric) is intentionally omitted:
-- raven does not capture cache tokens (data gap, see research doc).
WITH cost AS (
  SELECT
    round(sum(COALESCE(cost_usd, 0)), 2)                         AS total_cost,
    round(100.0 * sum(COALESCE(output_tokens, 0))
          / NULLIF(sum(COALESCE(total_tokens, 0)), 0), 2)        AS output_share_pct
  FROM fact_request
  WHERE (:since IS NULL OR date(ts/1000, 'unixepoch', '+8 hours') >= :since)
),
tasks AS (
  SELECT count(*) AS completed_tasks
  FROM fact_task
  WHERE status = 'completed'
    AND (:since IS NULL OR date(substr(ts_end, 1, 10)) >= :since)
)
SELECT
  c.total_cost,
  t.completed_tasks,
  CASE WHEN t.completed_tasks > 0
       THEN round(c.total_cost / t.completed_tasks, 2)
       ELSE NULL END                                             AS cost_per_completed_task,
  c.output_share_pct
FROM cost c, tasks t;
