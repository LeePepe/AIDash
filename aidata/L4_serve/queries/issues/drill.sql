-- issues/drill — everything about one issue. Pass --param id=MY-1213.
-- Joins runs, the raven token bridge (via run.session_id), and PR outcome.
SELECT
    i.identifier,
    i.status                                    AS issue_status,
    t.task_id,
    t.status                                    AS run_status,
    t.attempt || '/' || t.max_attempts          AS attempt,
    t.tokens                                    AS issue_tokens,
    t.session_id,
    (SELECT count(*) FROM fact_request r WHERE r.session_uuid = t.session_id)
                                                AS raven_requests,
    (SELECT sum(COALESCE(r.total_tokens,0)) FROM fact_request r
      WHERE r.session_uuid = t.session_id)      AS raven_tokens,
    t.pr_url,
    p.state                                     AS pr_state
FROM fact_issue i
LEFT JOIN fact_task t ON t.issue_id = i.issue_id
LEFT JOIN fact_pr p   ON p.pr_url = t.pr_url
WHERE i.identifier = :id
ORDER BY t.ts_start;
