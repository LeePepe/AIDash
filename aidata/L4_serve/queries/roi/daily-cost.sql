-- roi/daily-cost — per-day token spend + notional USD cost across all tools.
-- Source: fact_request (raven). Cost derived via dim_model; NULL-token rows
-- (mostly errors) contribute 0 cost. CST bucket via explicit +8h (ADR-22),
-- matching trend/daily-cost — never `localtime` (machine-timezone dependent).
SELECT
    date(ts / 1000, 'unixepoch', '+8 hours')       AS day,
    count(*)                                        AS requests,
    sum(COALESCE(input_tokens, 0))                  AS input_tokens,
    sum(COALESCE(output_tokens, 0))                 AS output_tokens,
    round(sum(COALESCE(cost_usd, 0)), 2)            AS cost_usd,
    sum(status = 'error')                           AS errors
FROM fact_request
GROUP BY day
ORDER BY day DESC
LIMIT 30;
