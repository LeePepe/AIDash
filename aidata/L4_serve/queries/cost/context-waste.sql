-- aidata-tier: explore
-- cost/context-waste — huge input, near-empty output. Paying to stuff big
-- contexts (>50k input) for <20 output tokens: prompt bloat or misfires.
SELECT count(*)                        AS requests,
       round(avg(input_tokens), 0)     AS avg_input_tokens,
       round(sum(cost_usd), 2)         AS total_usd,
       round(max(input_tokens), 0)     AS max_input_tokens
FROM fact_request
WHERE input_tokens IS NOT NULL AND input_tokens > 50000
  AND output_tokens IS NOT NULL AND output_tokens < 20
  AND cost_usd IS NOT NULL;
