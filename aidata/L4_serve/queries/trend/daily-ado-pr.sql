-- trend/daily-ado-pr — per-CST-day PRs I opened (by created_date) and merged
-- (by closed_date where status='completed'). created_date/closed_date are ISO
-- text with offset, so bucket with date(col,'+8 hours') (ADR-2), NOT epoch.
-- Reads fact_ado_pr — a SEPARATE table from fact_pr (ADR-13). Feeds the
-- Trending "开PR" arrow and 昨日汇总 "开了 N 个 PR".
WITH days(day) AS (
    SELECT DISTINCT date(created_date, '+8 hours')
    FROM fact_ado_pr WHERE created_date IS NOT NULL
    UNION
    SELECT DISTINCT date(closed_date, '+8 hours')
    FROM fact_ado_pr WHERE closed_date IS NOT NULL AND status = 'completed'
)
SELECT d.day AS day,
       (SELECT count(*) FROM fact_ado_pr
        WHERE date(created_date, '+8 hours') = d.day)                       AS opened,
       (SELECT count(*) FROM fact_ado_pr
        WHERE date(closed_date, '+8 hours') = d.day AND status = 'completed') AS merged
FROM days d
WHERE d.day IS NOT NULL
ORDER BY day DESC;
