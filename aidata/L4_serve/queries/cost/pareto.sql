-- cost/pareto — spend concentration by model (STRONG: full $ coverage).
-- Shows each model's share and the running cumulative share, so you can read
-- "top N models = X% of spend" directly. Uses model_canon so dotted/hyphen
-- spellings are merged.
WITH per_model AS (
  SELECT model_canon AS model,
         round(sum(cost_usd), 2) AS cost_usd,
         count(*)                AS requests
  FROM fact_request
  WHERE cost_usd IS NOT NULL
  GROUP BY model_canon
),
totals AS (
  SELECT sum(cost_usd) AS total_cost FROM per_model
),
ranked AS (
  SELECT pm.model, pm.cost_usd, pm.requests,
         sum(pm2.cost_usd) AS cum_cost
  FROM per_model pm
  JOIN per_model pm2 ON pm2.cost_usd >= pm.cost_usd
  GROUP BY pm.model, pm.cost_usd, pm.requests
)
SELECT r.model, r.cost_usd, r.requests,
       round(100.0 * r.cost_usd / t.total_cost, 1) AS pct_of_spend,
       round(100.0 * r.cum_cost / t.total_cost, 1) AS cumulative_pct
FROM ranked r, totals t
ORDER BY r.cost_usd DESC;
