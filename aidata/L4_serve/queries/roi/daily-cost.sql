-- roi/daily-cost — per-day token spend + notional USD cost across all tools.
-- Source: fact_request (raven). Cost is SUMmed from the stored cost_usd, which
-- is derived once at L2 by adapters/raven.py::_cost() via dim_model — never
-- re-derive tokens × price here. NULL-token rows (mostly errors) contribute 0.
-- Buckets on cst_day, the schema's single CST-day definition (ADR-22).
SELECT
    cst_day                                         AS day,
    count(*)                                        AS requests,
    sum(COALESCE(input_tokens, 0))                  AS input_tokens,
    sum(COALESCE(output_tokens, 0))                 AS output_tokens,
    round(sum(COALESCE(cost_usd, 0)), 2)            AS cost_usd,
    sum(status = 'error')                           AS errors
FROM fact_request
GROUP BY cst_day
ORDER BY day DESC
LIMIT 30;
