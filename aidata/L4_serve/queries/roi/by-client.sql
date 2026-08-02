-- aidata-tier: explore
-- roi/by-client — compare tools (claude-cli vs codex vs multica vs …) on
-- volume, tokens, notional cost, latency, error rate. Source: fact_request.
SELECT
    client,
    count(*)                                    AS requests,
    sum(COALESCE(total_tokens, 0))              AS total_tokens,
    round(sum(COALESCE(cost_usd, 0)), 2)        AS cost_usd,
    round(avg(latency_ms), 0)                   AS avg_latency_ms,
    round(100.0 * sum(status = 'error') / count(*), 2) AS error_pct
FROM fact_request
WHERE client != ''
GROUP BY client
ORDER BY requests DESC;
