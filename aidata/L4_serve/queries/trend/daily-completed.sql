-- trend/daily-completed — per-CST-day count of issues COMPLETED, per workspace.
-- "Completed" ≈ status='done' with the edit (updated_at) landing on that CST day.
-- Buckets on fact_issue.cst_day (generated from updated_at; see schema).
-- Count is APPROXIMATE: updated_at moves on any edit, not only completion
-- (ADR-19) — the digest labels it 近似. Grouped by workspace so the digest can
-- degrade project-level breakdown to per-workspace (EXT-1/ADR-22).
SELECT cst_day                       AS day,
       workspace_id                  AS workspace_id,
       count(*)                      AS completed
FROM fact_issue
WHERE status = 'done' AND updated_at IS NOT NULL
GROUP BY cst_day, workspace_id
ORDER BY day DESC, completed DESC;
