-- trend/daily-pr — per-CST-day PRs I opened and merged, ACROSS BOTH HOSTS.
--
-- This is the single definition of the "开了 N 个 PR（合并 M 个）" metric. It
-- replaces an L5-side Python union (sources.py::_sum_series over two separate
-- queries), which split one metric's definition across three files — two .sql
-- files plus a Python adder. That split had already caused a real bug: the
-- golden test froze `fetch_ado_pr_trends` but not the combined seam the digest
-- actually calls, so the fixture leaked live data (see tech-context.md 坑 ①).
--
-- Both hosts are read from the warehouse's separate PR tables — they stay
-- separate at rest (ADR-13: different shapes) and are unioned only here, at the
-- metric layer, which is where a composite metric belongs.
--
-- Merge signal differs by host and that asymmetry is deliberate:
--   ADO    — closed_date + status='completed' (ADO has no explicit merge date)
--   GitHub — merged_date (explicit; a CLOSED-unmerged PR must not count)
-- Both bucket on the schema's generated cst_* columns (indexed), never an
-- inline +8h.
WITH opened AS (
    SELECT cst_day AS day, count(*) AS n FROM fact_ado_pr
    WHERE cst_day IS NOT NULL GROUP BY cst_day
    UNION ALL
    SELECT cst_day AS day, count(*) AS n FROM fact_github_pr
    WHERE cst_day IS NOT NULL GROUP BY cst_day
),
merged AS (
    SELECT cst_closed_day AS day, count(*) AS n FROM fact_ado_pr
    WHERE cst_closed_day IS NOT NULL AND status = 'completed'
    GROUP BY cst_closed_day
    UNION ALL
    SELECT cst_merged_day AS day, count(*) AS n FROM fact_github_pr
    WHERE cst_merged_day IS NOT NULL GROUP BY cst_merged_day
),
-- A day appears if EITHER host saw an open or a merge on it.
days(day) AS (
    SELECT day FROM opened UNION SELECT day FROM merged
)
SELECT d.day                                                        AS day,
       COALESCE((SELECT sum(n) FROM opened o WHERE o.day = d.day), 0) AS opened,
       COALESCE((SELECT sum(n) FROM merged m WHERE m.day = d.day), 0) AS merged
FROM days d
ORDER BY day DESC;
