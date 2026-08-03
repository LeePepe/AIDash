-- aidata-attach: aidash_events
-- behavior/card-interest — spec 005 (star every card) US5: which card TYPES the
-- user whole-card-stars most, over a rolling window (default caller-side 7
-- CST days, ADR-22). Source: aidash_events.user_event, a L2-only clean DB
-- ATTACHed directly by serve.py as `aidash_events` (ADR-13) — this source has
-- no warehouse table (not a MERGE_SOURCE), same access pattern as
-- work/commit-by-repo.sql reading local_git.
--
-- `item_ref IS NULL` is the load-bearing filter (spec 005 D1): a radar card's
-- single-item star carries item_ref = the starred repo URL, while a whole-card
-- star carries item_ref = NULL. Without this filter every single-item star
-- would double-count into its card's whole-card total. card_type IS NOT NULL
-- excludes events from app builds that predate the field (spec 005 D2
-- forward-compat) — they cannot be attributed to a type and would otherwise
-- pollute an "unknown" bucket.
--
-- ts is ISO-8601 ('...Z' or with an offset; SQLite normalizes to UTC first), so
-- date(ts,'+8 hours') is the correct CST calendar day (ADR-2) — same form used
-- by gecko/local_git/state_db (all L2-only sources with no generated cst_day
-- column). Bind :since (inclusive) as a CST date 'YYYY-MM-DD'; NULL -> all-time
-- (serve.py auto-binds a missing param to NULL, matching every other windowed
-- query in this tree). The caller (L5) computes :since = today - 7 days.
--
-- Empty / no matching rows -> empty result set, never an error (ADR-23); the
-- L5 fetcher then degrades the insight card away rather than rendering it
-- empty.
SELECT
    card_type                                                   AS card_type,
    count(*)                                                    AS star_count
FROM aidash_events.user_event
WHERE action = 'star'
  AND item_ref IS NULL
  AND card_type IS NOT NULL
  AND (:since IS NULL OR date(ts, '+8 hours') >= :since)
GROUP BY card_type
ORDER BY star_count DESC, card_type ASC;
