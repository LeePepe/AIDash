-- aidata-attach: memory_claude
-- memory/claude-inventory — Claude Code memory notes, grouped by type.
-- Reads the un-merged clean source directly (memory does NOT enter warehouse).
SELECT
    type,
    count(*)        AS notes,
    group_concat(name, ' | ') AS names
FROM memory_claude.mem
GROUP BY type
ORDER BY notes DESC;
