-- issues/trend — the ordered view: as issues progress (by issue_number ==
-- creation order), how do token spend / run count / failure & retry rates move?
-- Spine: fact_issue ⋈ fact_task (per-issue tokens live on the multica runs).
SELECT
    i.issue_number,
    i.identifier,
    i.status,
    count(t.task_id)                                          AS runs,
    max(t.tokens)                                             AS issue_tokens,
    sum(t.status = 'cancelled')                              AS cancelled,
    sum(t.status = 'failed')                                 AS failed,
    max(COALESCE(t.attempt, 1))                              AS max_attempt
FROM fact_issue i
LEFT JOIN fact_task t
       ON t.issue_id = i.issue_id AND t.source = 'multica_run'
GROUP BY i.issue_id
ORDER BY i.issue_number ASC;
