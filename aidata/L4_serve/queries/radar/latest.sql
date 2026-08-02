-- radar/latest — the GitHub tool-radar: each watchlist repo's most recent
-- snapshot plus its star delta vs the previous snapshot. Feeds the L5 digest
-- "GitHub 工具雷达" cards (ranked by stars, delta shown as ▲/▼).
--
-- Correlated subqueries, NOT window functions: serve.py runs queries through
-- Python's stdlib sqlite3 (3.19.x here), which predates LAG/OVER (3.25+). This
-- matches the codebase's existing style (see trend/daily-ado-pr.sql).
--
-- star_delta = latest.stars − stars at the most recent EARLIER snapshot for the
-- same repo. On a repo's first-ever snapshot there is no earlier row, so the
-- inner SELECT is NULL and star_delta is NULL — the digest renders that as "—",
-- never a fake 0. Ordered by stars desc so the ranked list needs no re-sort.
SELECT a.repo            AS repo,
       a.snapshot_date   AS snapshot_date,
       a.stars           AS stars,
       a.stars - (
           SELECT p.stars FROM fact_repo_snapshot p
           WHERE p.repo = a.repo
             AND p.snapshot_date = (
                 SELECT MAX(q.snapshot_date) FROM fact_repo_snapshot q
                 WHERE q.repo = a.repo AND q.snapshot_date < a.snapshot_date
             )
       )                 AS star_delta,
       a.forks           AS forks,
       a.description      AS description,
       a.language         AS language,
       a.topics           AS topics,
       a.pushed_at        AS pushed_at,
       a.provenance       AS provenance
FROM fact_repo_snapshot a
WHERE a.snapshot_date = (
    SELECT MAX(b.snapshot_date) FROM fact_repo_snapshot b WHERE b.repo = a.repo
)
ORDER BY a.stars DESC;
