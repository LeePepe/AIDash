"""LLM enrichment for the GitHub tool-radar (§radar, goal "技术雷达").

The L4 `radar/latest` query gives the objective facts (stars, delta, description,
topics). This module adds the SUBJECTIVE layer the user asked for — for each repo:

  - category        : a coarse bucket (AI-agent / 设计 / 交易投资 / 学习 / 工具 …)
  - related_project : which of the user's OWN projects it could plug into
                      (matched against distinct fact_turn.project), or None
  - tier            : "now" (值得现在看) vs "horizon" (拓展视野)
  - reason          : one Chinese sentence — why it's worth (or not yet) a look

It reuses the digest's single LLM boundary (llm.py, haiku-4.5 via the raven
proxy). Results are CACHED per repo keyed by a content hash of description+topics,
so an unchanged repo costs no tokens on the daily run — only genuinely new or
changed repos hit the model. Enrichment is OPTIONAL and degrades safe (ADR-16/23):
no API key, an LLM error, or a bad reply → the repo keeps its objective facts with
empty enrichment fields, and the cards still render (stars + delta only).
"""

from __future__ import annotations

import hashlib
import json
import logging
from dataclasses import dataclass, replace
from pathlib import Path

from config import AIDATA_HOME
from L5_apps.digest.llm import LLMClient, LLMError, default_client

log = logging.getLogger("aidata.digest.repo_radar")

# Cache lives beside the digest's other human-facing state (proposals.jsonl).
CACHE_PATH = AIDATA_HOME / "L5_apps" / "digest" / "state" / "repo_enrichment.json"

# Fixed tier vocabulary — kept small and stable so the app/cards can rely on it.
TIER_NOW = "now"          # 值得现在看
TIER_HORIZON = "horizon"  # 拓展视野
_TIERS = (TIER_NOW, TIER_HORIZON)

# Bound the fields so a chatty model can't bloat a card.
_MAX_CATEGORY = 20
_MAX_REASON = 80


@dataclass(frozen=True)
class RepoCard:
    """One enriched radar entry — objective facts + optional LLM enrichment."""
    repo: str                      # "owner/name"
    stars: int
    star_delta: int | None         # None on a repo's first snapshot
    description: str
    language: str
    topics: tuple[str, ...]
    url: str
    provenance: str
    category: str = ""             # LLM; "" when unavailable
    related_project: str | None = None
    tier: str = TIER_HORIZON       # default to 拓展视野 until judged
    reason: str = ""

    @property
    def enriched(self) -> bool:
        return bool(self.category or self.reason)


# ---------------------------------------------------------------------------
# Cache (content-addressed by description+topics so stale enrichment is reused
# only while the repo's blurb is unchanged).
# ---------------------------------------------------------------------------
def _content_key(description: str, topics: tuple[str, ...]) -> str:
    blob = json.dumps({"d": description or "", "t": list(topics)},
                      sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def load_cache(path: Path = CACHE_PATH) -> dict:
    """Read the enrichment cache; degrade to {} on any read/parse failure."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_cache(cache: dict, path: Path = CACHE_PATH) -> None:
    """Persist the cache atomically; best-effort (never raises)."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(cache, ensure_ascii=False, indent=2),
                      encoding="utf-8")
        tmp.replace(path)
    except OSError as exc:  # pragma: no cover - cache-of-convenience
        log.warning("could not write enrichment cache: %s", exc)


# ---------------------------------------------------------------------------
# LLM call (one repo → its enrichment fields). Pure except for the client.
# ---------------------------------------------------------------------------
def _system_prompt(projects: list[str]) -> str:
    project_list = "、".join(projects) if projects else "（无已知项目）"
    return (
        "你是一个技术雷达助手。用户收藏了一批 GitHub 工具/仓库，"
        "你要为每个仓库判断四件事，帮用户决定要不要看、能不能用到自己项目上。\n"
        f"用户当前在做的项目有：{project_list}。\n"
        "严格只返回 JSON 对象，不要解释、不要代码块，字段如下：\n"
        '{"category": "一个简短中文分类(如 AI-agent/设计/交易投资/学习/工具/框架)",'
        ' "related_project": "上面项目里最相关的一个名字，若都不相关则填 null",'
        ' "tier": "now 或 horizon（now=和用户当前工作直接相关值得现在看，'
        'horizon=有意思但更偏拓展视野）",'
        ' "reason": "一句话中文理由，不超过40字"}'
    )


def _user_prompt(repo: str, description: str, language: str,
                 topics: tuple[str, ...]) -> str:
    return json.dumps({
        "repo": repo,
        "description": description or "",
        "language": language or "",
        "topics": list(topics),
    }, ensure_ascii=False)


def _parse_enrichment(raw: str, known_projects: list[str]) -> dict:
    """Parse + clamp the model's JSON reply; raise LLMError if unusable."""
    text = raw.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    try:
        data = json.loads(text)
    except (ValueError, json.JSONDecodeError) as exc:
        raise LLMError(f"enrichment reply not JSON: {exc}") from None
    if not isinstance(data, dict):
        raise LLMError("enrichment reply not a JSON object")

    tier = str(data.get("tier") or "").strip().lower()
    if tier not in _TIERS:
        tier = TIER_HORIZON
    related = data.get("related_project")
    related = str(related).strip() if related not in (None, "", "null") else None
    # Only trust a project name the user actually has (guards against a
    # hallucinated project); case-insensitive match, echo the canonical name.
    if related is not None:
        match = next((p for p in known_projects
                      if p.lower() == related.lower()), None)
        related = match  # None when the model named a project that isn't ours
    return {
        "category": str(data.get("category") or "").strip()[:_MAX_CATEGORY],
        "related_project": related,
        "tier": tier,
        "reason": str(data.get("reason") or "").strip()[:_MAX_REASON],
    }


def enrich_repos(cards: list[RepoCard], *, client: LLMClient | None = None,
                 projects: list[str] | None = None,
                 cache_path: Path = CACHE_PATH) -> list[RepoCard]:
    """Return `cards` with LLM enrichment filled in (cache-first, degrade-safe).

    A cache hit (same repo + unchanged description/topics) reuses the stored
    enrichment with no LLM call. On a miss, one bounded call per repo fills the
    fields; any failure leaves that card's objective facts intact with empty
    enrichment. When no client is available (no API key), every card is returned
    unenriched — the cards still render with stars + delta.
    """
    client = client or default_client()
    projects = projects or []
    if not cards:
        return cards
    cache = load_cache(cache_path)
    out: list[RepoCard] = []
    dirty = False

    for card in cards:
        key = _content_key(card.description, card.topics)
        entry = cache.get(card.repo)
        if entry and entry.get("key") == key:
            out.append(_apply_entry(card, entry, projects))
            continue
        if client is None:
            out.append(card)  # no LLM available → keep objective-only
            continue
        try:
            raw = client.complete(
                _system_prompt(projects),
                _user_prompt(card.repo, card.description, card.language,
                             card.topics))
            fields = _parse_enrichment(raw, projects)
        except LLMError as exc:
            log.warning("enrichment failed for %s: %s", card.repo, exc)
            out.append(card)  # degrade: objective-only card
            continue
        cache[card.repo] = {"key": key, **fields}
        dirty = True
        out.append(_apply_entry(card, cache[card.repo], projects))

    if dirty:
        save_cache(cache, cache_path)
    return out


def _apply_entry(card: RepoCard, entry: dict,
                 projects: list[str] | None = None) -> RepoCard:
    """Return a new card with enrichment fields from a cache/LLM entry.

    `related_project` is re-validated against the CURRENT projects list even on a
    cache hit: the enrichment content-hash keys only on description+topics, so a
    project that has since dropped off the user's list must not linger as a stale
    match. An unknown/missing name resolves to None (no LLM re-call needed)."""
    related = entry.get("related_project")
    if related is not None and projects is not None:
        related = next((p for p in projects if p.lower() == related.lower()), None)
    return replace(
        card,
        category=entry.get("category", ""),
        related_project=related,
        tier=entry.get("tier", TIER_HORIZON),
        reason=entry.get("reason", ""),
    )
