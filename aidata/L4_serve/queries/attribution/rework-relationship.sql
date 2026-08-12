-- attribution/rework-relationship — WHERE rework concentrates, on two axes.
--
-- `attribution/rework-by-workspace` splits rework by workspace and stops there;
-- `health/failure-rootcause` splits failures by cause and stops there. Neither
-- answers the question that actually decides where to look: is one workspace's
-- rework one recurring infrastructure fault, or many unrelated ones? That needs
-- both axes at once, which is what makes this a `relationship` rather than a
-- second ranking.
--
-- REWORK DEFINITION — deliberately identical to health/rework-rate and
-- attribution/rework-by-workspace: an issue whose multica_run history contains
-- BOTH a cancelled run and a completed run, i.e. work thrown away and redone.
-- Keeping one definition means this query drills into that number instead of
-- inventing a second, subtly different one.
--
-- ONE ISSUE, ONE CELL (the correctness rule this query exists to hold).
-- An issue's runs can fail for several different reasons, so the obvious
-- implementation — group (issue, root_cause) pairs — puts that issue's tokens
-- in two cells and inflates every total, while still rendering as a convincing
-- heatmap. A wrong number that looks right is worse than a missing one, so each
-- issue is assigned exactly ONE dominant root cause first (most tokens burned
-- under that cause; ties broken alphabetically for determinism), and only then
-- aggregated. Column totals therefore sum to the true rework total.
--
-- ROOT-CAUSE CLASSIFICATION mirrors health/failure-rootcause's prefix mapping,
-- with one addition: a redone issue whose runs recorded no error still belongs
-- on the matrix as 'unclassified'. Dropping it would understate rework — the
-- number the card exists to report.
--
-- WORKSPACE IS A UUID HERE, ON PURPOSE — same reason as
-- attribution/rework-by-workspace: friendly names live in
-- config.MULTICA_WORKSPACES, which is gitignored because workspace ids are
-- account-specific. L5 does the lookup.
--
-- Bind :since as a CST date 'YYYY-MM-DD' (inclusive); NULL = all time.
WITH per_issue AS (
    SELECT t.issue_id,
           i.workspace_id,
           min(date(t.ts_start, '+8 hours'))                       AS first_day,
           max(CASE WHEN t.status = 'cancelled' THEN 1 ELSE 0 END) AS has_cancelled,
           max(CASE WHEN t.status = 'completed' THEN 1 ELSE 0 END) AS has_completed,
           sum(COALESCE(t.tokens, 0))                              AS tokens
    FROM fact_task t
    JOIN fact_issue i ON i.issue_id = t.issue_id
    WHERE t.source = 'multica_run'
      AND t.issue_id IS NOT NULL
      AND t.ts_start IS NOT NULL
      AND i.workspace_id IS NOT NULL
    GROUP BY t.issue_id, i.workspace_id
),
rework AS (
    SELECT * FROM per_issue
    WHERE has_cancelled = 1
      AND has_completed = 1
      AND (:since IS NULL OR first_day >= :since)
),
-- Tokens burned per (issue, cause), used only to pick each issue's dominant
-- cause below. Never summed into the output — that is the double count.
issue_cause AS (
    SELECT t.issue_id,
           CASE
               WHEN t.error LIKE 'runtime went offline%'    THEN 'runtime-offline'
               WHEN t.error LIKE 'task expired%'            THEN 'queue-timeout'
               WHEN t.error LIKE 'codex initialize failed%' THEN 'codex-init-fail'
               WHEN t.error LIKE 'daemon restarted%'        THEN 'daemon-restart'
               WHEN t.error LIKE '%model_not_supported%'
                 OR t.error LIKE '%model_not_available%'    THEN 'model-config'
               WHEN t.error LIKE 'Missing environment%'     THEN 'env-missing'
               ELSE 'other'
           END                                              AS root_cause,
           sum(COALESCE(t.tokens, 0))                       AS cause_tokens
    FROM fact_task t
    JOIN rework r ON r.issue_id = t.issue_id
    WHERE t.source = 'multica_run'
      AND t.error IS NOT NULL
      AND t.error != ''
    GROUP BY t.issue_id, root_cause
),
-- One row per issue: its single dominant cause. No window functions —
-- serve.py runs on stdlib sqlite, so the pick is a correlated subquery.
dominant AS (
    SELECT ic.issue_id,
           ic.root_cause
    FROM issue_cause ic
    WHERE ic.cause_tokens = (
              SELECT max(x.cause_tokens) FROM issue_cause x
              WHERE x.issue_id = ic.issue_id
          )
      AND ic.root_cause = (
              SELECT min(y.root_cause) FROM issue_cause y
              WHERE y.issue_id = ic.issue_id
                AND y.cause_tokens = (
                        SELECT max(z.cause_tokens) FROM issue_cause z
                        WHERE z.issue_id = ic.issue_id
                    )
          )
),
labeled AS (
    SELECT r.workspace_id,
           COALESCE(d.root_cause, 'unclassified') AS root_cause,
           r.tokens,
           r.first_day
    FROM rework r
    LEFT JOIN dominant d ON d.issue_id = r.issue_id
)
SELECT workspace_id                                    AS workspace_id,
       root_cause                                      AS root_cause,
       count(*)                                        AS issues,
       sum(tokens)                                     AS rework_tokens,
       -- Evidence the card must carry (constitution §Relationship
       -- visualization): total rework issues behind the whole matrix, and the
       -- observed CST window. Scalar subqueries so every row agrees.
       (SELECT count(*) FROM labeled)                  AS sample_size,
       (SELECT min(first_day) FROM labeled)            AS window_start,
       (SELECT max(first_day) FROM labeled)            AS window_end
FROM labeled
GROUP BY workspace_id, root_cause
ORDER BY rework_tokens DESC, workspace_id ASC, root_cause ASC;
