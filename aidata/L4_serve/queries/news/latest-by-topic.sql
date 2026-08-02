-- aidata-attach: news
-- news/latest-by-topic — the newest N headlines per topic from the latest news
-- snapshot (the trending "新闻雷达" card, grouped by topic). Source:
-- news.news_item, a L2-only clean DB ATTACHed directly by serve.py as `news`
-- (ADR-13), read directly like daily-automation.sql reads state_db — news has no
-- warehouse table (not a MERGE_SOURCE).
--
-- "Latest" ordering: published_at is stored in MIXED formats across feeds
-- (RFC-2822 "Sun, 26 Jul 2026 …" from Google News vs ISO-8601 "…Z" from Hacker
-- News), so a lexical/date sort across topics is NOT reliable and there are no
-- date-parsing UDFs on stdlib sqlite. Feeds present items newest-first, and the
-- normalize step inserts in feed order, so a SMALLER rowid = earlier in the feed
-- = newer within a topic. We therefore rank by rowid ascending as the robust
-- recency proxy and keep the top `per_topic` (3) of each topic. No window
-- functions (stdlib sqlite): the per-topic rank is a correlated COUNT of
-- same-topic rows with a smaller rowid. snapshot is pinned to the max
-- snapshot_date so only the freshest pull shows. Empty → no rows (degrade-safe:
-- the producer omits the card, ADR-23).
SELECT
    n.topic                                                     AS topic,
    n.title                                                     AS title,
    n.url                                                       AS url,
    n.source_name                                               AS source_name,
    n.published_at                                              AS published_at
FROM news_item n
WHERE n.snapshot_date = (SELECT max(snapshot_date) FROM news_item)
  AND n.title IS NOT NULL AND n.title != ''
  AND (
        SELECT count(*)
        FROM news_item m
        WHERE m.snapshot_date = n.snapshot_date
          AND m.topic = n.topic
          AND m.title IS NOT NULL AND m.title != ''
          AND m.rowid < n.rowid
      ) < 3
ORDER BY n.topic ASC, n.rowid ASC;
