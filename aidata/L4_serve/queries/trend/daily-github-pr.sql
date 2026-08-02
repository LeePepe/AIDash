-- trend/daily-github-pr — per-CST-day GitHub PRs I opened (by created_date) and
-- merged (by merged_date). created_date/merged_date are ISO text with offset, so
-- bucket with date(col,'+8 hours') (ADR-2), NOT epoch. Reads fact_github_pr — a
-- SEPARATE table from fact_ado_pr / fact_pr (ADR-13). Unioned with daily-ado-pr
-- upstream to feed the 昨日汇总 "开了 N 个 PR（合并 N 个）" line.
WITH days(day) AS (
    SELECT DISTINCT date(created_date, '+8 hours')
    FROM fact_github_pr WHERE created_date IS NOT NULL
    UNION
    SELECT DISTINCT date(merged_date, '+8 hours')
    FROM fact_github_pr WHERE merged_date IS NOT NULL
)
SELECT d.day AS day,
       (SELECT count(*) FROM fact_github_pr
        WHERE date(created_date, '+8 hours') = d.day)   AS opened,
       (SELECT count(*) FROM fact_github_pr
        WHERE date(merged_date, '+8 hours') = d.day)    AS merged
FROM days d
WHERE d.day IS NOT NULL
ORDER BY day DESC;
