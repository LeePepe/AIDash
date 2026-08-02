-- aidata-attach: state_db
-- cost/model-tier-usage — per-model token-mix distribution to catch "big model
-- doing small work". Source: state_db.session (L2-only, ATTACHed like
-- daily-automation.sql). Complementary to — NOT a duplicate of — the existing
-- cost/* queries: pareto and by-model-window measure DOLLARS from raven
-- (fact_request grain), while this measures the TOKEN mix and the per-session
-- output size from Hermes sessions. A model with a large token share but a tiny
-- avg_output_per_session is the tell-tale of an oversized model on trivial tasks
-- (model-downgrade.sql flags the raven request-grain version of the same smell).
--
-- token_share_pct = this model's billable tokens / all models' billable tokens.
-- billable = input + output + cache_read + cache_write (all token movement).
-- NULLIF guards the grand-total denominator (degrade-safe on an empty clean DB).
WITH per_model AS (
  SELECT COALESCE(model, '(unknown)')                        AS model,
         count(*)                                            AS sessions,
         sum(COALESCE(message_count, 0))                     AS messages,
         sum(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)
             + COALESCE(cache_read_tokens, 0)
             + COALESCE(cache_write_tokens, 0))              AS billable_tokens,
         sum(COALESCE(output_tokens, 0))                     AS output_tokens
  FROM state_db.session
  GROUP BY COALESCE(model, '(unknown)')
),
total AS (
  SELECT sum(billable_tokens) AS all_tokens FROM per_model
)
SELECT pm.model,
       pm.sessions,
       pm.billable_tokens,
       round(100.0 * pm.billable_tokens / NULLIF(t.all_tokens, 0), 1)
                                                             AS token_share_pct,
       round(pm.output_tokens * 1.0 / NULLIF(pm.sessions, 0), 0)
                                                             AS avg_output_per_session
FROM per_model pm, total t
ORDER BY pm.billable_tokens DESC;
