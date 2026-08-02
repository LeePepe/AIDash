-- inbox/stalled-prs — ADO PRs stuck open past a staleness threshold (类3 卡顿).
-- Feeds the '需要处理什么' action inbox: an open PR aging past :max_hours is a
-- blockage the user should notice. Bind :max_hours (default 168 = 7 days).
-- Ordered oldest-first (most stuck on top). Draft PRs are excluded.
SELECT
    pr_id,
    title,
    round(age_hours, 0)         AS age_hours,
    source_branch,
    repo
FROM fact_ado_pr
WHERE status = 'active'
  AND is_draft = 0
  AND age_hours > COALESCE(:max_hours, 168)
ORDER BY age_hours DESC;
