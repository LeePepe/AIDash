-- aidata-tier: explore
-- tokens/by-device — merged token totals and per-device contribution.
-- Grain: one CST day x device. The __all__ row is the merged total; device
-- rows retain source identity and share input+output token contribution.

WITH grouped AS (
    SELECT cst_day, device_id, machine_alias,
           SUM(input_tokens) AS input,
           SUM(output_tokens) AS output,
           SUM(cache_read) AS cache_read,
           SUM(cache_write) AS cache_write,
           SUM(total_tokens) AS total_tokens,
           SUM(invocations) AS invocations
    FROM fact_device_token_daily
    WHERE (:day_from IS NULL OR cst_day >= :day_from)
      AND (:day_to IS NULL OR cst_day <= :day_to)
    GROUP BY cst_day, device_id, machine_alias
), totals AS (
    SELECT cst_day, SUM(input) AS input, SUM(output) AS output,
           SUM(cache_read) AS cache_read, SUM(cache_write) AS cache_write,
           SUM(total_tokens) AS total_tokens, SUM(invocations) AS invocations
    FROM grouped
    GROUP BY cst_day
)
SELECT cst_day, '__all__' AS device_id, 'All devices' AS machine_alias,
       input, output, cache_read, cache_write, total_tokens, invocations,
       100.0 AS share_pct
FROM totals
UNION ALL
SELECT g.cst_day, g.device_id, g.machine_alias,
       g.input, g.output, g.cache_read, g.cache_write,
       g.total_tokens, g.invocations,
       round(100.0 * (g.input + g.output) / NULLIF(t.input + t.output, 0), 2)
FROM grouped g
JOIN totals t ON t.cst_day = g.cst_day
ORDER BY cst_day, device_id;
