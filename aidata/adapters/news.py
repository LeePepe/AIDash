"""news adapter — a key-free, public news radar (Google News / HN / arXiv).

The user wants a daily pulse across a handful of subjects (AI/tech, the HN
community, finance/investing, world + China news, US-China relations). This
adapter turns config.NEWS_FEEDS — one maintainable manifest of feeds, mirroring
COLLECTED_TOOLS_DIR's role for github_repo — into a LIVING daily radar: every
run it fetches each feed's current headlines and stamps a CST snapshot_date, so
the L2 clean DB accumulates the news surface per day. news is L2-only — it is NOT
merged into the warehouse (no L3/L4/L5 consumer yet).

L1 collect: walk NEWS_FEEDS, HTTP-GET each feed, parse out (title, link,
published, source_name, score). News has no CLI, so instead of ado_pr/github_repo's
subprocess shell-out we fetch over stdlib urllib — but keep the SAME injectable
runner seam (`fetch` param, defaulting to `_http_get`) so tests stay hermetic and
no live network is required. Every string still flows through write_raw_snapshot's
redact path (the enforced red line), and the snapshot is content-hashed so an
unchanged pull writes nothing.

L2 normalize: one row per (topic, url) — keyed by a COMPOSITE hash so the same
article surfacing under two subjects is preserved as two rows (we keep "which
subject caught it"), while a genuine dupe within one subject collapses.

Degrade-not-crash (ADR-23): a feed that fails to fetch or parse is skipped and
the rest continue; if every feed fails, collect returns 0 and never raises. Only
title + link + light metadata are kept — never article full text (copyright/size).
"""

from __future__ import annotations

import hashlib
import json
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from typing import Any, Callable

from config import NEWS_FEEDS
from timeutil import cst_today
from timeutil import CST as _CST  # noqa: F401 (re-export seam)
from rawio import write_raw_snapshot, read_raw
from cleanio import write_clean

SOURCE = "news"

# _CST re-exported from timeutil (seam). The snapshot day is stamped at collect
# time so no downstream +8h bucketing is needed (ADR-2): already the CST day.

_HTTP_TIMEOUT_S = 13
_USER_AGENT = "aidata-news/1.0"
_GNEWS_BASE = "https://news.google.com/rss"

# A conservative per-feed cap so one noisy feed can't dominate the snapshot.
_MAX_ITEMS_PER_FEED = 40


def _cst_today() -> str:
    """Current CST calendar day (thin wrapper over timeutil.cst_today; seam)."""
    return cst_today()


# ---------------------------------------------------------------------------
# HTTP fetch seam — the injectable runner (like github_repo's _gh_repo).
# ---------------------------------------------------------------------------
def _http_get(url: str) -> str | None:
    """GET `url` and return the body text, or None on any degrade path.

    A key-free public request with a plain User-Agent and bounded timeout. A
    network error, timeout, non-2xx status, or decode failure all yield None so
    the caller skips just that feed — never raises (ADR-23).
    """
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=_HTTP_TIMEOUT_S) as resp:  # nosec B310
            raw = resp.read()
    except (urllib.error.URLError, OSError, ValueError):
        return None
    try:
        return raw.decode("utf-8", errors="replace")
    except (UnicodeDecodeError, AttributeError):
        return None


# ---------------------------------------------------------------------------
# Feed URL builders (Google News RSS).
# ---------------------------------------------------------------------------
def _ceid_lang(lang: str) -> str:
    """The ceid language token Google News expects (verified 2026-07-26).

    en-US → "en"; zh-CN → "zh-Hans" (Simplified). Falls back to the bare
    primary subtag for anything else.
    """
    if lang.startswith("zh"):
        return "zh-Hant" if "TW" in lang or "Hant" in lang else "zh-Hans"
    return lang.split("-", 1)[0]


def _gnews_common(lang: str, geo: str) -> str:
    """The shared hl/gl/ceid query tail for any Google News RSS URL."""
    params = {"hl": lang, "gl": geo, "ceid": f"{geo}:{_ceid_lang(lang)}"}
    return urllib.parse.urlencode(params)


def gnews_search_url(query: str, lang: str, geo: str) -> str:
    """Keyword-search RSS URL (query is URL-encoded; supports CJK)."""
    q = urllib.parse.quote(query)
    return f"{_GNEWS_BASE}/search?q={q}&{_gnews_common(lang, geo)}"


def gnews_topic_url(topic: str, lang: str, geo: str) -> str:
    """Section RSS URL for a WORLD/BUSINESS/TECHNOLOGY-style TOPIC token."""
    tok = urllib.parse.quote(topic)
    return f"{_GNEWS_BASE}/headlines/section/topic/{tok}?{_gnews_common(lang, geo)}"


def _feed_url(kind: str, target: str, lang: str | None, geo: str | None) -> str | None:
    """Resolve a NEWS_FEEDS entry to a concrete fetch URL, or None if unknown."""
    if kind == "gnews_search":
        return gnews_search_url(target, lang or "en-US", geo or "US")
    if kind == "gnews_topic":
        return gnews_topic_url(target, lang or "en-US", geo or "US")
    if kind in ("rss", "hn_algolia"):
        return target  # already an absolute URL
    return None


# ---------------------------------------------------------------------------
# Parsers — each returns a list of item dicts:
#   {title, link, published, source_name, score}
# ---------------------------------------------------------------------------
def _local(tag: str) -> str:
    """Strip an XML namespace: '{http://...}title' -> 'title'."""
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def _child_text(elem: ET.Element, name: str) -> str | None:
    for child in elem:
        if _local(child.tag) == name:
            return (child.text or "").strip() or None
    return None


def _atom_link(elem: ET.Element) -> str | None:
    """An Atom <entry> may carry <link href="..."/> instead of link text."""
    for child in elem:
        if _local(child.tag) == "link":
            href = child.get("href")
            if href:
                return href.strip()
            if child.text and child.text.strip():
                return child.text.strip()
    return None


def parse_rss(text: str) -> list[dict[str, Any]]:
    """Parse RSS 2.0 / RDF / Atom into news items (namespace-agnostic).

    Handles Google News <item> (with <source>) and arXiv/Atom <entry>. Items
    missing a title or link are dropped. Never raises on malformed XML — an
    unparseable body yields [] so the caller degrades (ADR-23).
    """
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return []
    items: list[dict[str, Any]] = []
    for elem in root.iter():
        if _local(elem.tag) not in ("item", "entry"):
            continue
        title = _child_text(elem, "title")
        link = _child_text(elem, "link") or _atom_link(elem)
        if not title or not link:
            continue
        published = (_child_text(elem, "pubDate")
                     or _child_text(elem, "published")
                     or _child_text(elem, "updated")
                     or _child_text(elem, "date"))
        source_name = _child_text(elem, "source") or _child_text(elem, "creator")
        items.append({
            "title": title,
            "link": link,
            "published": published,
            "source_name": source_name,
            "score": None,
        })
    return items


def parse_hn(text: str) -> list[dict[str, Any]]:
    """Parse a Hacker News Algolia JSON payload into news items.

    Carries `points` as score. A self/Ask-HN post (null url) links to its HN
    discussion. Bad JSON or an unexpected shape yields [] (degrade, ADR-23).
    """
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return []
    hits = data.get("hits") if isinstance(data, dict) else None
    if not isinstance(hits, list):
        return []
    items: list[dict[str, Any]] = []
    for hit in hits:
        if not isinstance(hit, dict):
            continue
        title = hit.get("title") or hit.get("story_title")
        object_id = hit.get("objectID")
        url = hit.get("url") or hit.get("story_url")
        if not url and object_id:
            url = f"https://news.ycombinator.com/item?id={object_id}"
        if not title or not url:
            continue
        points = hit.get("points")
        items.append({
            "title": str(title),
            "link": str(url),
            "published": hit.get("created_at"),
            "source_name": "Hacker News",
            "score": points if isinstance(points, int) else None,
        })
    return items


def _parse(kind: str, text: str) -> list[dict[str, Any]]:
    return parse_hn(text) if kind == "hn_algolia" else parse_rss(text)


# ---------------------------------------------------------------------------
# L1 collect.
# ---------------------------------------------------------------------------
def collect(fetch: Callable[[str], str | None] = _http_get) -> int:
    """Snapshot every NEWS_FEEDS feed's current headlines for today (CST).

    Returns records written (0 on any degrade path: every feed failing, or an
    unchanged snapshot). `fetch` is injectable so tests stay hermetic.
    """
    snapshot_date = _cst_today()
    records: list[dict[str, Any]] = []
    for topic, kind, target, lang, geo in NEWS_FEEDS:
        url = _feed_url(kind, target, lang, geo)
        if not url:
            continue  # unknown kind — skip, don't crash
        try:
            body = fetch(url)
        except Exception:  # nosec B110 - any fetch failure degrades to skip (ADR-23)
            body = None
        if not body:
            continue  # feed fetch failed — skip, keep going
        try:
            items = _parse(kind, body)
        except Exception:  # nosec B110 - a malformed feed skips, never crashes
            items = []
        for item in items[:_MAX_ITEMS_PER_FEED]:
            records.append({
                "topic": topic,
                "snapshot_date": snapshot_date,
                "title": item["title"],
                "url": item["link"],
                "published_at": item.get("published"),
                "source_name": item.get("source_name"),
                "score": item.get("score"),
            })
    if not records:
        return 0
    return write_raw_snapshot(SOURCE, records)


# ---------------------------------------------------------------------------
# L2 normalize.
# ---------------------------------------------------------------------------
_CLEAN_DDL = """
CREATE TABLE news_item (
    item_id TEXT PRIMARY KEY, snapshot_date TEXT, topic TEXT,
    source_name TEXT, title TEXT, url TEXT, published_at TEXT, score INTEGER
)
"""
_CLEAN_COLS = ("item_id", "snapshot_date", "topic", "source_name",
               "title", "url", "published_at", "score")


def _item_id(topic: str, url: str) -> str:
    """Stable composite key so (topic, url) dedups but cross-topic hits survive."""
    return hashlib.sha256(f"{topic}\n{url}".encode("utf-8")).hexdigest()[:16]


def normalize() -> int:
    """Reshape raw shards into one row per (topic, url).

    Keyed by the composite hash so the SAME article caught under two subjects is
    kept as two rows (preserving which subject surfaced it), while a true dupe
    within one subject collapses. Last write wins within a key — a later
    snapshot just refreshes that item's row.
    """
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        topic = rec.get("topic")
        url = rec.get("url")
        if not topic or not url:
            continue
        rows[_item_id(topic, url)] = {
            "item_id": _item_id(topic, url),
            "snapshot_date": rec.get("snapshot_date"),
            "topic": topic,
            "source_name": rec.get("source_name"),
            "title": rec.get("title"),
            "url": url,
            "published_at": rec.get("published_at"),
            "score": rec.get("score"),
        }
    return write_clean(SOURCE, "news_item", _CLEAN_DDL,
                       list(rows.values()), _CLEAN_COLS)
