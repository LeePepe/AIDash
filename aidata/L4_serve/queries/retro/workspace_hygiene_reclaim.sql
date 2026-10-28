-- aidata-tier: explore
SELECT
    COALESCE(repo_key, 'unknown') AS repo_key,
    entity_type,
    COUNT(*) AS snapshot_count,
    SUM(CASE WHEN safe_to_reclaim = 1 THEN 1 ELSE 0 END) AS reclaimable_count,
    SUM(CASE WHEN is_dirty = 1 THEN 1 ELSE 0 END) AS dirty_count,
    SUM(CASE WHEN has_active_pane = 1 THEN 1 ELSE 0 END) AS active_pane_count,
    SUM(CASE WHEN is_merged_to_default = 1 THEN 1 ELSE 0 END) AS merged_count
FROM fact_workspace_hygiene_snapshot
GROUP BY repo_key, entity_type
ORDER BY reclaimable_count DESC, repo_key, entity_type;
