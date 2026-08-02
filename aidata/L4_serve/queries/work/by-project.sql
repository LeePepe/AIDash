-- work/by-project — "做了什么": effort per project over a window (CST).
-- Answers the dashboard's ① goal (M2): where did I actually spend effort.
-- Source: fact_turn (assistant turns carry project / git_branch / skill).
-- turns = assistant turns, out_ktok = output tokens (thousands), sessions =
-- distinct working sessions. Bind :since (inclusive) / :until (exclusive) as
-- CST dates 'YYYY-MM-DD'; NULL → all-time. Filters on fact_turn.cst_day, the
-- schema's single CST-day definition (indexed; see schema/warehouse.sql).
SELECT
    project,
    count(*)                                        AS turns,
    round(sum(COALESCE(output_tokens, 0)) / 1000.0, 1) AS out_ktok,
    count(DISTINCT session_id)                      AS sessions
FROM fact_turn
WHERE role = 'assistant'
  AND project IS NOT NULL AND project != ''
  AND (:since IS NULL OR cst_day >= :since)
  AND (:until IS NULL OR cst_day <  :until)
GROUP BY project
ORDER BY turns DESC;
