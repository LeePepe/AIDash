-- cost/by-model-window — cost per model within a date window (CST).
-- Parameterized slice of spend by model_canon for a single day (or any range),
-- so the digest's "值不值" card can show yesterday's model mix rather than the
-- all-time pareto. Bind :since and :until as CST date strings 'YYYY-MM-DD'
-- (inclusive since, exclusive until). Falls back to all-time if params NULL.
SELECT model_canon                                          AS model,
       count(*)                                             AS requests,
       round(sum(COALESCE(cost_usd, 0)), 2)                 AS cost_usd,
       round(sum(COALESCE(output_tokens, 0)) / 1000.0, 1)   AS out_ktok
FROM fact_request
WHERE (:since IS NULL OR date(ts/1000, 'unixepoch', '+8 hours') >= :since)
  AND (:until IS NULL OR date(ts/1000, 'unixepoch', '+8 hours') <  :until)
  AND cost_usd IS NOT NULL
GROUP BY model_canon
ORDER BY cost_usd DESC;
