-- aidata-attach: multica_comment
-- health/planner-gap — issues an Engineer worked but no Planner ever touched
-- (signal ①: work that should have gone through spec/planning skipped it).
-- Source: multica_comment.comment (L2-only clean DB ATTACHed by serve.py as
-- `multica_comment`, read directly like daily-automation.sql reads state_db).
-- fact_issue lives in warehouse.db (the main DB serve opens), so a cross-DB
-- LEFT JOIN enriches each gap issue with identifier/status/priority; the join is
-- LEFT + degrades to NULLs if an issue is absent from the warehouse (ADR-23).
SELECT
    c.issue_id,
    i.identifier,
    i.status,
    i.priority,
    c.engineer_comments,
    c.total_comments
FROM (
    SELECT
        issue_id,
        max(CASE WHEN mention_role = 'Fullstack Engineer' THEN 1 ELSE 0 END) AS has_eng,
        max(CASE WHEN mention_role = 'Planner Lead'       THEN 1 ELSE 0 END) AS has_planner,
        sum(CASE WHEN mention_role = 'Fullstack Engineer' THEN 1 ELSE 0 END) AS engineer_comments,
        count(*)                                                             AS total_comments
    FROM multica_comment.comment
    WHERE issue_id IS NOT NULL
    GROUP BY issue_id
) c
LEFT JOIN fact_issue i ON i.issue_id = c.issue_id
WHERE c.has_eng = 1 AND c.has_planner = 0
ORDER BY c.engineer_comments DESC, c.total_comments DESC
LIMIT 50;
