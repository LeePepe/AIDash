-- attribution/model-by-project — which project burns which model.
--
-- The second attribution axis. `cost-by-project` says WHERE the money went;
-- this says WHAT it was spent on, so "opus is 71% of spend" becomes "AIDash is
-- running opus-5 for $1293 while VitalStride's opus spend is half that".
-- Together they turn a single-dimension trend arrow into a cause.
--
-- Same session bridge and same turn-weighted allocation as
-- `attribution/cost-by-project` — see that file's header for why the weighting
-- is required (a session averages 1.68 projects; naive attribution
-- double-counts) and for the honest coverage caveat.
--
-- Cost is SUMmed from the stored cost_usd. The pricing math lives ONLY in
-- adapters/raven.py::_cost() at L2 — never re-derive tokens x price here.
--
-- Bind :day as a CST date 'YYYY-MM-DD'; NULL falls back to the whole history.
WITH project_weight AS (
    SELECT session_id AS sid,
           project,
           count(*) * 1.0
             / sum(count(*)) OVER (PARTITION BY session_id) AS weight
    FROM fact_turn
    WHERE project IS NOT NULL AND project != ''
      AND (:day IS NULL OR cst_day = :day)
    GROUP BY session_id, project
),
allocated AS (
    SELECT w.project,
           r.model_canon                       AS model,
           sum(COALESCE(r.cost_usd, 0) * w.weight) AS cost_usd,
           sum(COALESCE(r.output_tokens, 0) * w.weight) AS out_tokens
    FROM fact_request r
    JOIN project_weight w ON w.sid = r.session_uuid
    WHERE r.model_canon IS NOT NULL
      AND (:day IS NULL OR r.cst_day = :day)
    GROUP BY w.project, r.model_canon
)
SELECT project                                   AS project,
       model                                     AS model,
       round(cost_usd, 2)                        AS cost_usd,
       -- Share of THIS project's spend, so a project running one expensive
       -- model stands out regardless of its absolute size.
       round(100.0 * cost_usd
             / NULLIF(sum(cost_usd) OVER (PARTITION BY project), 0), 1)
                                                 AS pct_of_project,
       round(out_tokens / 1000.0, 1)             AS out_ktok
FROM allocated
WHERE cost_usd > 0
ORDER BY cost_usd DESC;
