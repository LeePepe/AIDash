-- aidata-attach: local_git
-- work/commit-by-repo — cross-repo coding OUTPUT: per-repo commit count over a CST
-- window, descending (the barList "跨仓 commit" card). Complementary to the PR
-- trends (trend/daily-*-pr): "PR 是结果、commit 是过程" — this adds the process
-- dimension. Source: local_git.commit_log, a L2-only clean DB ATTACHed directly by
-- serve.py as `local_git` (ADR-13), read directly like daily-automation.sql reads
-- state_db — never the warehouse (local_git is not a MERGE_SOURCE).
--
-- ts is ISO-8601 with a +08:00 offset (SQLite normalizes to UTC first), so
-- date(ts,'+8 hours') gives the correct CST calendar day (ADR-2). Bind :since
-- (inclusive) / :until (exclusive) as CST dates 'YYYY-MM-DD'; NULL → all-time
-- (serve.py auto-binds missing params to NULL, so a bare call is the all-time
-- ranking). insertions/deletions are summed as a secondary context signal. Empty
-- windows yield no rows (degrade-safe: producer omits the card, ADR-23).
SELECT
    repo                                                        AS repo,
    count(*)                                                    AS commits,
    sum(COALESCE(insertions, 0))                                AS insertions,
    sum(COALESCE(deletions, 0))                                 AS deletions
FROM local_git.commit_log
WHERE repo IS NOT NULL AND repo != ''
  AND (:since IS NULL OR date(ts, '+8 hours') >= :since)
  AND (:until IS NULL OR date(ts, '+8 hours') <  :until)
GROUP BY repo
ORDER BY commits DESC, repo ASC;
