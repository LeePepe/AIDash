-- trend/daily-github-pr — per-CST-day GitHub PRs I opened (by created_date) and
-- merged (by merged_date). Buckets on the generated columns
-- fact_github_pr.cst_day / .cst_merged_day (see schema) — both indexed.
-- Reads fact_github_pr — a SEPARATE table from fact_ado_pr / fact_pr (ADR-13).
-- Unioned with daily-ado-pr upstream to feed the 昨日汇总
-- "开了 N 个 PR（合并 N 个）" line.
WITH days(day) AS (
    SELECT DISTINCT cst_day FROM fact_github_pr WHERE cst_day IS NOT NULL
    UNION
    SELECT DISTINCT cst_merged_day
    FROM fact_github_pr WHERE cst_merged_day IS NOT NULL
)
SELECT d.day AS day,
       (SELECT count(*) FROM fact_github_pr WHERE cst_day = d.day)        AS opened,
       (SELECT count(*) FROM fact_github_pr WHERE cst_merged_day = d.day) AS merged
FROM days d
WHERE d.day IS NOT NULL
ORDER BY day DESC;
