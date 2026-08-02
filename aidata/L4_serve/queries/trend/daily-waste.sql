-- trend/daily-waste — per-CST-day wasted spend (raven). Two patterns:
--   (a) opus-tier model producing <20 output tokens (over-provisioned model)
--   (b) any request with >50k input but <20 output (context bloat / misfire)
-- Feeds the Trending "浪费额" arrow.
SELECT date(ts/1000,'unixepoch','+8 hours')  AS day,
       round(sum(COALESCE(cost_usd,0)), 2)   AS waste_usd,
       count(*)                              AS waste_requests
FROM fact_request
WHERE cost_usd IS NOT NULL
  AND output_tokens IS NOT NULL AND output_tokens < 20
  AND (
        model_canon LIKE 'claude-opus-%'
     OR (input_tokens IS NOT NULL AND input_tokens > 50000)
      )
GROUP BY day
ORDER BY day DESC;
