-- trend/daily-cost — per-CST-day requests / tokens / notional cost (raven).
-- Buckets on fact_request.cst_day, the schema's single CST-day definition
-- (indexed; see the CST note in schema/warehouse.sql). Feeds the Trending
-- section's cost & token arrows.
-- Cost is SUMmed from the stored cost_usd — the pricing math lives ONLY in
-- adapters/raven.py::_cost() at L2. Never re-derive tokens × price here.
SELECT cst_day                                                  AS day,
       count(*)                                                 AS requests,
       sum(COALESCE(input_tokens,0) + COALESCE(output_tokens,0)) AS tokens,
       round(sum(COALESCE(cost_usd,0)), 2)                      AS cost_usd
FROM fact_request
GROUP BY cst_day
ORDER BY day DESC;
