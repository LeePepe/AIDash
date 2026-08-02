-- trend/daily-ado-pr — per-CST-day PRs I opened (by created_date) and merged
-- (by closed_date where status='completed'). Buckets on the generated columns
-- fact_ado_pr.cst_day / .cst_closed_day (see schema) — both indexed.
-- Reads fact_ado_pr — a SEPARATE table from fact_pr (ADR-13). Feeds the
-- Trending "开PR" arrow and 昨日汇总 "开了 N 个 PR".
WITH days(day) AS (
    SELECT DISTINCT cst_day FROM fact_ado_pr WHERE cst_day IS NOT NULL
    UNION
    SELECT DISTINCT cst_closed_day
    FROM fact_ado_pr WHERE cst_closed_day IS NOT NULL AND status = 'completed'
)
SELECT d.day AS day,
       (SELECT count(*) FROM fact_ado_pr WHERE cst_day = d.day)          AS opened,
       (SELECT count(*) FROM fact_ado_pr
        WHERE cst_closed_day = d.day AND status = 'completed')           AS merged
FROM days d
WHERE d.day IS NOT NULL
ORDER BY day DESC;
