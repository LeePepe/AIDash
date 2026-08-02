-- cost/model-downgrade — Opus (or any pricey model) used for tiny outputs.
-- Flags requests on opus-tier models that produced <20 output tokens: trivial
-- completions that a cheaper model would serve. Sum the cost to see the prize.
SELECT model_canon                                   AS model,
       count(*)                                      AS tiny_output_requests,
       round(sum(cost_usd), 2)                       AS wasted_usd,
       round(avg(input_tokens), 0)                   AS avg_input_tokens
FROM fact_request
WHERE model_canon LIKE 'claude-opus-%'
  AND output_tokens IS NOT NULL AND output_tokens < 20
  AND cost_usd IS NOT NULL
GROUP BY model_canon
ORDER BY wasted_usd DESC;
