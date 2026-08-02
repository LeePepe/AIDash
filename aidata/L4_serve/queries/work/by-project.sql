-- work/by-project — "做了什么": effort per project over a window (CST).
-- Answers the dashboard's ① goal (M2): where did I actually spend effort.
-- Source: fact_turn (assistant turns carry project / git_branch / skill).
-- turns = assistant turns, out_ktok = output tokens (thousands), sessions =
-- distinct working sessions. Bind :since (inclusive) / :until (exclusive) as
-- CST dates 'YYYY-MM-DD'; NULL → all-time. fact_turn.ts is ISO-8601 UTC, so
-- CST bucket via datetime(ts,'+8 hours') (ADR-2), NOT /1000 (that's epoch-ms).
SELECT
    project,
    count(*)                                        AS turns,
    round(sum(COALESCE(output_tokens, 0)) / 1000.0, 1) AS out_ktok,
    count(DISTINCT session_id)                      AS sessions
FROM fact_turn
WHERE role = 'assistant'
  AND project IS NOT NULL AND project != ''
  AND (:since IS NULL OR date(datetime(ts, '+8 hours')) >= :since)
  AND (:until IS NULL OR date(datetime(ts, '+8 hours')) <  :until)
GROUP BY project
ORDER BY turns DESC;
