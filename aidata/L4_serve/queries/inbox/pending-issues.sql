-- inbox/pending-issues — multica & linear TIA issues awaiting action (类1 计划的活 + 类3 blocked + triage).
-- Feeds the '需要处理什么' action inbox. blocked = stuck (higher urgency),
-- triage = awaiting approval/decision, todo/in_review = planned work. Excludes
-- done/cancelled/backlog. Orders blocked and triage first, then by issue priority,
-- so the most urgent surface on top.
SELECT
    identifier,
    title,
    status,
    COALESCE(NULLIF(priority, 'none'), 'medium')    AS priority
FROM fact_issue
WHERE status IN ('blocked', 'triage', 'in_review', 'todo', 'in_progress')
ORDER BY
    CASE WHEN workspace_id LIKE 'linear:%' THEN 0 ELSE 1 END,
    CASE status WHEN 'blocked' THEN 0 WHEN 'triage' THEN 1
                WHEN 'in_progress' THEN 2 WHEN 'in_review' THEN 3 ELSE 4 END,
    CASE COALESCE(NULLIF(priority,'none'),'medium')
         WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
    COALESCE(updated_at, '') DESC,
    identifier;
