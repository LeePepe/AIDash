-- aidata-attach: gecko
-- time/app-focus — where attention went: per-app focus MINUTES over a CST window,
-- descending (the barList "app 焦点时长" card). Source: gecko.focus_session, a
-- L2-only clean DB ATTACHed directly by serve.py as `gecko` (ADR-13), same access
-- pattern as daily-automation.sql reads state_db — never the warehouse (gecko is
-- not a MERGE_SOURCE). Answers "注意力去哪了", a dimension no other source carries.
--
-- ts is ISO-8601 with a +08:00 offset (SQLite normalizes it to UTC before the
-- modifier), so date(ts,'+8 hours') is the correct CST calendar day (ADR-2) — the
-- same +8h form works whether the stored offset is +08:00 or Z. duration_sec is a
-- REAL per-sample dwell time; sum/60 → minutes, rounded to 0.1. Bind :since
-- (inclusive) / :until (exclusive) as CST dates 'YYYY-MM-DD'; NULL → all-time
-- (serve.py auto-binds missing params to NULL). Empty windows yield no rows
-- (degrade-safe: the producer then omits the card, ADR-23).
SELECT
    app_name                                                    AS app,
    round(sum(COALESCE(duration_sec, 0)) / 60.0, 1)             AS minutes,
    count(*)                                                    AS samples
FROM gecko.focus_session
WHERE app_name IS NOT NULL AND app_name != ''
  AND (:since IS NULL OR date(ts, '+8 hours') >= :since)
  AND (:until IS NULL OR date(ts, '+8 hours') <  :until)
GROUP BY app_name
HAVING sum(COALESCE(duration_sec, 0)) > 0
ORDER BY minutes DESC;
