-- aidata-attach: state_db
-- trend/daily-automation — per-CST-day automation ratio from Hermes state.db
-- sessions. state.db is an L2-only source (ADR-13): read directly from the
-- ATTACHed clean DB (state_db.session), never the warehouse. started_at is epoch
-- SECONDS (float) → date(started_at,'unixepoch','+8 hours') (ADR-2). automated =
-- cron/subagent (is_automated=1); manual = everything else. Feeds the Trending
-- automation arrow and 昨日汇总 "自动化占比".
SELECT date(started_at, 'unixepoch', '+8 hours')          AS day,
       sum(is_automated)                                  AS automated,
       sum(CASE WHEN is_automated = 0 THEN 1 ELSE 0 END)  AS manual,
       count(*)                                           AS total,
       round(sum(is_automated) * 1.0 / count(*), 3)       AS automation_ratio
FROM state_db.session
GROUP BY day
ORDER BY day DESC;
