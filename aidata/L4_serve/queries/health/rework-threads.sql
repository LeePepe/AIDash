-- aidata-attach: multica_comment
-- health/rework-threads — per-issue Engineer<->Reviewer back-and-forth from the
-- comment thread graph. A truer rework signal than run-count (rework-loops.sql):
-- it counts who was @-mentioned across the conversation, not just retries.
-- Source: multica_comment.comment — an L2-only clean DB ATTACHed by serve.py as
-- `multica_comment` (in SOURCES, NOT in MERGE_SOURCES), so we read it directly,
-- exactly like daily-automation.sql reads state_db.session (ADR-13).
-- reviewer_mentions/engineer_mentions gate the rows to real review loops; issues
-- with only one side (or none) are dropped by the HAVING.
SELECT
    issue_id,
    sum(CASE WHEN mention_role IN ('AI Reviewer', 'Code Review Lead')
             THEN 1 ELSE 0 END)                          AS reviewer_mentions,
    sum(CASE WHEN mention_role = 'Fullstack Engineer'
             THEN 1 ELSE 0 END)                          AS engineer_mentions,
    count(*)                                             AS total_comments
FROM multica_comment.comment
WHERE issue_id IS NOT NULL
GROUP BY issue_id
HAVING reviewer_mentions > 0 AND engineer_mentions > 0
ORDER BY (reviewer_mentions + engineer_mentions) DESC,
         total_comments DESC
LIMIT 50;
