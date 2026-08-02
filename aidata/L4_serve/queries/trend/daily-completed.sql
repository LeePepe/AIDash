-- trend/daily-completed — per-CST-day count of issues COMPLETED, per workspace.
-- "Completed" ≈ status='done' with the edit (updated_at) landing on that CST day.
-- updated_at is ISO text (e.g. 2026-07-10T20:01:53Z) so bucket with
-- date(updated_at,'+8 hours') — NOT the epoch-ms CST_DAY_EXPR (ADR-2/19).
-- Count is APPROXIMATE: updated_at moves on any edit, not only completion
-- (ADR-19) — the digest labels it 近似. Grouped by workspace so the digest can
-- degrade project-level breakdown to per-workspace (EXT-1/ADR-22).
SELECT date(updated_at, '+8 hours')  AS day,
       workspace_id                  AS workspace_id,
       count(*)                      AS completed
FROM fact_issue
WHERE status = 'done' AND updated_at IS NOT NULL
GROUP BY day, workspace_id
ORDER BY day DESC, completed DESC;
