-- aidata-tier: explore
SELECT
    repo_key,
    target_platform,
    COUNT(*) AS delivery_count,
    SUM(CASE WHEN delivery_outcome = 'noop_skipped' THEN 1 ELSE 0 END) AS noop_skipped_count,
    SUM(CASE WHEN delivery_outcome IN ('uploaded_verified', 'uploaded_unverified_asc')
             THEN 1 ELSE 0 END) AS upload_attempt_count,
    SUM(CASE WHEN delivery_outcome = 'uploaded_verified' THEN 1 ELSE 0 END) AS verified_upload_count,
    SUM(CASE WHEN delivery_outcome LIKE 'failed_%' OR delivery_outcome = 'cancelled_timeout'
             THEN 1 ELSE 0 END) AS failed_delivery_count,
    AVG(total_duration_sec) AS avg_duration_sec,
    MAX(total_duration_sec) AS max_duration_sec
FROM fact_release_delivery
GROUP BY repo_key, target_platform
ORDER BY repo_key, target_platform;
