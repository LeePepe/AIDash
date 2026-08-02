"""Hermetic unit tests for adapters/news — no live network required.

The HTTP fetch seam (`fetch` param) and the raw/clean IO are monkeypatched, so
these prove the URL building, RSS/HN parsing, collect snapshotting, the
degrade-not-crash paths, and the (topic, url) dedup deterministically off fixed
sample payloads.
"""

import json
import pathlib
import tempfile

import pytest

import adapters.news as news


# ---- fixed sample payloads -------------------------------------------------
_GNEWS_XML = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>人工智能 - Google News</title>
    <item>
      <title>某公司发布新一代人工智能大模型</title>
      <link>https://news.google.com/rss/articles/aaa</link>
      <pubDate>Sat, 26 Jul 2026 08:00:00 GMT</pubDate>
      <source url="https://example.cn">示例科技</source>
    </item>
    <item>
      <title>AI chip demand surges worldwide</title>
      <link>https://news.google.com/rss/articles/bbb</link>
      <pubDate>Sat, 26 Jul 2026 09:00:00 GMT</pubDate>
      <source url="https://example.com">Example Times</source>
    </item>
  </channel>
</rss>"""

_ATOM_XML = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>Efficient Attention for Long Contexts</title>
    <link href="https://arxiv.org/abs/2607.00001"/>
    <published>2026-07-26T00:00:00Z</published>
  </entry>
</feed>"""

_HN_JSON = json.dumps({
    "hits": [
        {"title": "Show HN: A tiny local news radar",
         "url": "https://example.com/radar",
         "points": 321, "objectID": "111",
         "created_at": "2026-07-26T07:00:00Z"},
        {"title": "Ask HN: best stdlib tricks?",  # self-post → HN discussion link
         "url": None, "points": 88, "objectID": "222",
         "created_at": "2026-07-26T06:00:00Z"},
    ]
})


# ---- URL building ----------------------------------------------------------
@pytest.mark.unit
def test_gnews_search_url_encodes_cjk_and_ceid():
    url = news.gnews_search_url("中美关系", "zh-CN", "CN")
    assert url.startswith("https://news.google.com/rss/search?q=")
    assert "%E4%B8%AD%E7%BE%8E%E5%85%B3%E7%B3%BB" in url  # 中美关系 percent-encoded
    assert "hl=zh-CN" in url and "gl=CN" in url and "ceid=CN%3Azh-Hans" in url


@pytest.mark.unit
def test_gnews_topic_url_uses_section_path():
    url = news.gnews_topic_url("BUSINESS", "en-US", "US")
    assert "/headlines/section/topic/BUSINESS" in url
    assert "ceid=US%3Aen" in url


@pytest.mark.unit
def test_feed_url_passes_through_absolute_urls():
    assert news._feed_url("rss", "https://x/y.rss", None, None) == "https://x/y.rss"
    assert news._feed_url("hn_algolia", "https://hn/api", None, None) == "https://hn/api"
    assert news._feed_url("bogus", "whatever", None, None) is None


# ---- parsing ---------------------------------------------------------------
@pytest.mark.unit
def test_parse_rss_extracts_items_with_source_and_cjk():
    items = news.parse_rss(_GNEWS_XML)
    assert len(items) == 2
    first = items[0]
    assert first["title"] == "某公司发布新一代人工智能大模型"
    assert first["link"] == "https://news.google.com/rss/articles/aaa"
    assert first["source_name"] == "示例科技"
    assert first["published"] == "Sat, 26 Jul 2026 08:00:00 GMT"


@pytest.mark.unit
def test_parse_rss_handles_atom_link_href():
    items = news.parse_rss(_ATOM_XML)
    assert len(items) == 1
    assert items[0]["link"] == "https://arxiv.org/abs/2607.00001"
    assert items[0]["published"] == "2026-07-26T00:00:00Z"


@pytest.mark.unit
def test_parse_rss_bad_xml_degrades_to_empty():
    assert news.parse_rss("<not xml") == []
    assert news.parse_rss("") == []


@pytest.mark.unit
def test_parse_rss_drops_items_missing_title_or_link():
    xml = ('<rss><channel><item><title>only title</title></item>'
           '<item><link>https://x/only-link</link></item></channel></rss>')
    assert news.parse_rss(xml) == []


@pytest.mark.unit
def test_parse_hn_carries_points_and_self_post_link():
    items = news.parse_hn(_HN_JSON)
    assert len(items) == 2
    assert items[0]["score"] == 321
    assert items[0]["source_name"] == "Hacker News"
    # null-url self post links to its HN discussion via objectID
    assert items[1]["link"] == "https://news.ycombinator.com/item?id=222"


@pytest.mark.unit
def test_parse_hn_bad_json_degrades_to_empty():
    assert news.parse_hn("not json") == []
    assert news.parse_hn("[]") == []  # wrong shape (list, no hits)


# ---- collect ---------------------------------------------------------------
@pytest.mark.unit
def test_collect_snapshots_items_across_feeds(monkeypatch):
    feeds = (
        ("ai-tech", "gnews_search", "人工智能", "zh-CN", "CN"),
        ("hn", "hn_algolia", "https://hn/api", None, None),
    )
    monkeypatch.setattr(news, "NEWS_FEEDS", feeds)
    monkeypatch.setattr(news, "_cst_today", lambda: "2026-07-26")

    def _fetch(url):
        return _HN_JSON if "hn" in url else _GNEWS_XML

    captured = {}

    def _cap(source, records):
        captured["recs"] = records
        return len(records)

    monkeypatch.setattr(news, "write_raw_snapshot", _cap)
    n = news.collect(fetch=_fetch)
    assert n == 4  # 2 gnews items + 2 hn items
    recs = captured["recs"]
    assert {r["topic"] for r in recs} == {"ai-tech", "hn"}
    ai = [r for r in recs if r["topic"] == "ai-tech"][0]
    assert ai["snapshot_date"] == "2026-07-26"  # CST stamp
    assert ai["title"] == "某公司发布新一代人工智能大模型"
    hn = [r for r in recs if r["topic"] == "hn"][0]
    assert hn["score"] == 321


@pytest.mark.unit
def test_collect_redacts_before_writing_raw(monkeypatch):
    # A title carrying a secret must be redacted on the way to raw storage.
    leaky = ('<rss><channel><item><title>leak sk-ABCDEFGHIJKLMNOP1234</title>'
             '<link>https://x/leak</link></item></channel></rss>')
    monkeypatch.setattr(news, "NEWS_FEEDS",
                        (("world", "rss", "https://x/feed", None, None),))
    monkeypatch.setattr(news, "_cst_today", lambda: "2026-07-26")
    # Use the REAL write_raw_snapshot but redirect its output dir.
    tmp_out = pathlib.Path(tempfile.mkdtemp()) / "news"

    import rawio
    monkeypatch.setattr(rawio, "raw_source_dir", lambda source: tmp_out)
    n = news.collect(fetch=lambda url: leaky)
    assert n == 1
    shard = next(tmp_out.glob("*.jsonl"))
    body = shard.read_text(encoding="utf-8")
    assert "sk-ABCDEFGHIJKLMNOP1234" not in body  # secret was redacted
    assert "<REDACTED>" in body


@pytest.mark.unit
def test_collect_skips_failed_feed_keeps_others(monkeypatch):
    feeds = (
        ("world", "gnews_topic", "WORLD", "en-US", "US"),   # fetch returns None
        ("hn", "hn_algolia", "https://hn/api", None, None),  # ok
    )
    monkeypatch.setattr(news, "NEWS_FEEDS", feeds)
    monkeypatch.setattr(news, "_cst_today", lambda: "2026-07-26")

    def _fetch(url):
        return None if "topic/WORLD" in url else _HN_JSON

    captured = {}

    def _cap(source, records):
        captured["recs"] = records
        return len(records)

    monkeypatch.setattr(news, "write_raw_snapshot", _cap)
    n = news.collect(fetch=_fetch)
    assert n == 2
    assert {r["topic"] for r in captured["recs"]} == {"hn"}


@pytest.mark.unit
def test_collect_fetch_raising_is_skipped(monkeypatch):
    monkeypatch.setattr(news, "NEWS_FEEDS",
                        (("world", "rss", "https://x/feed", None, None),))
    monkeypatch.setattr(news, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("should not write"))

    def _boom(url):
        raise RuntimeError("network down")

    assert news.collect(fetch=_boom) == 0  # exception → skip → 0, no crash


@pytest.mark.unit
def test_collect_all_feeds_fail_returns_zero(monkeypatch):
    monkeypatch.setattr(news, "NEWS_FEEDS",
                        (("world", "rss", "https://x/feed", None, None),))
    monkeypatch.setattr(news, "write_raw_snapshot",
                        lambda *a, **k: pytest.fail("should not write"))
    assert news.collect(fetch=lambda url: None) == 0


# ---- normalize -------------------------------------------------------------
@pytest.mark.unit
def test_normalize_dedups_by_topic_and_url(monkeypatch):
    # Same url under two topics → TWO rows (keeps which subject caught it).
    # Same (topic, url) twice → ONE row (last write wins).
    raw = [
        {"topic": "china", "url": "https://x/a", "title": "old",
         "snapshot_date": "2026-07-25", "score": None},
        {"topic": "china", "url": "https://x/a", "title": "new",
         "snapshot_date": "2026-07-26", "score": None},
        {"topic": "us-china", "url": "https://x/a", "title": "same url other topic",
         "snapshot_date": "2026-07-26", "score": None},
    ]
    monkeypatch.setattr(news, "read_raw", lambda source: raw)
    captured = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = rows
        return len(rows)

    monkeypatch.setattr(news, "write_clean", _cap)
    n = news.normalize()
    assert n == 2  # (china,a) collapsed to 1 + (us-china,a) = 2
    by_topic = {r["topic"]: r["title"] for r in captured["rows"]}
    assert by_topic["china"] == "new"  # last write wins within a topic
    assert by_topic["us-china"] == "same url other topic"
    # item_ids are distinct across topics
    assert len({r["item_id"] for r in captured["rows"]}) == 2


@pytest.mark.unit
def test_normalize_skips_rows_missing_key(monkeypatch):
    monkeypatch.setattr(news, "read_raw",
                        lambda source: [{"title": "x"}, {"topic": "china"}])
    monkeypatch.setattr(news, "write_clean",
                        lambda s, t, ddl, rows, cols: len(rows))
    assert news.normalize() == 0  # neither row has both topic + url
