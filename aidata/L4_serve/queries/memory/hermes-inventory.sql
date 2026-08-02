-- aidata-attach: memory_hermes_db
-- memory/hermes-inventory — Hermes fact store, grouped by category, with a
-- dead-asset proxy. NOTE: retrieval_count/helpful_count are non-functional in
-- this runtime (counters_functional = 0), so dead-asset detection FALLS BACK to
-- age (days since created). Reads the un-merged clean source directly.
SELECT
    category,
    count(*)                                    AS facts,
    min(created_at)                             AS oldest,
    max(updated_at)                             AS newest,
    -- proxy: facts never updated since creation, older than 30d, are "stale"
    sum(julianday('now') - julianday(created_at) > 30
        AND created_at = updated_at)            AS stale_gt30d,
    max(counters_functional)                    AS counters_usable
FROM memory_hermes_db.fact
GROUP BY category
ORDER BY facts DESC;
