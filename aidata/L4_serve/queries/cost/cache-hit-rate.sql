-- aidata-attach: state_db
-- cost/cache-hit-rate — per-CST-day prompt-cache effectiveness from Hermes
-- state.db sessions. state.db is an L2-only source (ADR-13): read directly from
-- the ATTACHed clean DB (state_db.session), never the warehouse — same access
-- pattern as trend/daily-automation.sql. Chosen over claude_jsonl.turn because
-- state_db is fully backfilled (13k+ sessions, cache_read populated on ~8k),
-- while jsonl only spans the retained transcript window.
--
-- Cache hit rate = cache_read / (cache_read + input): the share of fresh prompt
-- context served from cache instead of re-billed as full input. Cache reads are
-- billed at ~10% of the input rate, so cache_savings_pct approximates the % of
-- the (input + cache_read) bill avoided by caching = 0.9 * hit_rate.
-- started_at is epoch SECONDS (float) → date(...,'unixepoch','+8 hours') (ADR-2).
-- Guarded denominators keep degrade-safe (no divide-by-zero on empty days).
SELECT date(started_at, 'unixepoch', '+8 hours')             AS day,
       count(*)                                              AS sessions,
       sum(COALESCE(input_tokens, 0))                        AS input_tokens,
       sum(COALESCE(cache_read_tokens, 0))                   AS cache_read_tokens,
       round(
         100.0 * sum(COALESCE(cache_read_tokens, 0)) / NULLIF(
           sum(COALESCE(cache_read_tokens, 0)) + sum(COALESCE(input_tokens, 0)), 0
         ), 1)                                               AS cache_hit_pct,
       round(
         90.0 * sum(COALESCE(cache_read_tokens, 0)) / NULLIF(
           sum(COALESCE(cache_read_tokens, 0)) + sum(COALESCE(input_tokens, 0)), 0
         ), 1)                                               AS cache_savings_pct
FROM state_db.session
GROUP BY day
ORDER BY day DESC;
