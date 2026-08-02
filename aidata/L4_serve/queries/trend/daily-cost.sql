-- trend/daily-cost — per-CST-day requests / tokens / notional cost (raven).
-- CST bucket via +8h (ADR-2). Feeds the Trending section's cost & token arrows.
SELECT date(ts/1000,'unixepoch','+8 hours')                     AS day,
       count(*)                                                 AS requests,
       sum(COALESCE(input_tokens,0) + COALESCE(output_tokens,0)) AS tokens,
       round(sum(COALESCE(cost_usd,0)), 2)                      AS cost_usd
FROM fact_request
GROUP BY day
ORDER BY day DESC;
