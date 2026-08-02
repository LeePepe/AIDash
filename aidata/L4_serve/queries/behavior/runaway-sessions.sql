-- aidata-tier: explore
-- behavior/runaway-sessions — the long tail of huge sessions. dim_session is
-- claude-cli-only (session_uuid reliable there), so this covers claude-cli
-- spend. Duration from first_ts/last_ts (epoch ms) -> minutes.
SELECT session_id,
       client,
       request_count,
       total_tokens,
       round(total_cost_usd, 2)                          AS cost_usd,
       round((last_ts - first_ts) / 60000.0, 1)          AS duration_min
FROM dim_session
WHERE total_tokens > 5000000            -- runaway threshold: >5M tokens
ORDER BY total_tokens DESC
LIMIT 50;
