-- trend/daily-behavior — per-CST-day distinct claude-cli sessions + avg tokens
-- per request. session_uuid reliable only for claude-cli (has_session=1).
SELECT date(ts/1000,'unixepoch','+8 hours')                      AS day,
       count(DISTINCT session_uuid)                              AS sessions,
       round(avg(COALESCE(input_tokens,0)+COALESCE(output_tokens,0)), 0) AS avg_tokens
FROM fact_request
WHERE has_session = 1 AND session_uuid IS NOT NULL
GROUP BY day
ORDER BY day DESC;
