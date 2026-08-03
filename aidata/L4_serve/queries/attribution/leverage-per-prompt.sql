-- attribution/leverage-per-prompt — what one thing I typed actually costs.
-- aidata-attach: claude_prompts
--
-- The human/machine ratio. Every other card measures the machine in isolation
-- (spend, tokens, requests); this divides that by the ONE input that is
-- entirely mine — the prompts I actually typed. It answers "how much work does
-- one sentence of mine set in motion", which nothing else here can.
--
-- Measured on 2026-08-02: 86 typed prompts -> $3310 and ~46 API requests each.
-- A rising cost-per-prompt means each instruction is pulling more machine work
-- (deeper agentic loops); a falling one means shallower turns. Neither is
-- inherently good — the point is that the number was previously invisible.
--
-- THE BRIDGE, AND ITS HONEST COVERAGE. claude_prompts.session_id is the same
-- Claude session id as fact_turn.session_id, so it joins fact_request on
-- session_uuid. Measured: 171 of 196 typed sessions resolve (87%). The other
-- 13% are sessions raven never recorded a conversation id for. They are
-- excluded rather than counted at zero cost, which would deflate the ratio.
--
-- ONLY `source_kind='typed'` COUNTS. That column exists precisely because 93%
-- of "user" lines are tool results, slash-command expansions, and harness
-- injections — counting those as things I said would make the denominator
-- meaningless (see adapters/claude_prompts.py).
--
-- Bind :day as a CST date 'YYYY-MM-DD'; NULL falls back to the whole history.
WITH mine AS (
    SELECT session_id       AS sid,
           count(*)         AS prompts,
           sum(text_len)    AS typed_chars
    FROM claude_prompts.prompt
    WHERE source_kind = 'typed'
      AND (:day IS NULL OR day = :day)
    GROUP BY session_id
),
machine AS (
    SELECT session_uuid                    AS sid,
           sum(COALESCE(cost_usd, 0))      AS cost,
           count(*)                        AS requests,
           sum(COALESCE(output_tokens, 0)) AS out_tokens
    FROM fact_request
    WHERE session_uuid IS NOT NULL
      AND (:day IS NULL OR cst_day = :day)
    GROUP BY session_uuid
)
SELECT sum(m.prompts)                                   AS prompts,
       count(*)                                         AS sessions,
       round(sum(a.cost), 2)                            AS cost_usd,
       -- The headline: one thing I typed, priced.
       round(sum(a.cost) / NULLIF(sum(m.prompts), 0), 2) AS usd_per_prompt,
       round(sum(a.requests) * 1.0
             / NULLIF(sum(m.prompts), 0), 1)            AS requests_per_prompt,
       round(sum(a.out_tokens) / 1000.0
             / NULLIF(sum(m.prompts), 0), 1)            AS out_ktok_per_prompt,
       -- How long my instructions were, for context on the ratio above.
       round(sum(m.typed_chars) * 1.0
             / NULLIF(sum(m.prompts), 0))               AS avg_prompt_chars
FROM mine m
JOIN machine a ON a.sid = m.sid;
