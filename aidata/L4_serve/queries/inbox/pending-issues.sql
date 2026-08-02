-- inbox/pending-issues — multica issues awaiting action (类1 计划的活 + 类3 blocked).
-- Feeds the '需要处理什么' action inbox. blocked = stuck (higher urgency),
-- todo/in_review = planned work. Excludes done/cancelled/backlog. Orders
-- blocked first, then by issue priority, so the most urgent surface on top.
SELECT
    identifier,
    title,
    status,
    COALESCE(NULLIF(priority, 'none'), 'medium')    AS priority
FROM fact_issue
WHERE status IN ('blocked', 'in_review', 'todo', 'in_progress')
ORDER BY
    CASE status WHEN 'blocked' THEN 0 WHEN 'in_progress' THEN 1
                WHEN 'in_review' THEN 2 ELSE 3 END,
    CASE COALESCE(NULLIF(priority,'none'),'medium')
         WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
    identifier;
