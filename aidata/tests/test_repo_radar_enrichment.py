"""Hermetic unit tests for L5_apps.digest.repo_radar — the LLM enrichment layer.

The LLM client is a stub, so these prove cache hit/miss, the degrade paths (no
client / LLM error), project-name validation, and field clamping deterministically
— no network.
"""

import json

import pytest

from L5_apps.digest import repo_radar as rr
from L5_apps.digest.repo_radar import RepoCard, TIER_NOW, TIER_HORIZON
from L5_apps.digest.llm import LLMError


def _card(repo="a/b", description="desc", topics=()):
    return RepoCard(
        repo=repo, stars=100, star_delta=None, description=description,
        language="Python", topics=topics, url=f"https://github.com/{repo}",
        provenance="curated")


class _StubClient:
    def __init__(self, reply):
        self._reply = reply
        self.calls = 0

    def complete(self, system, user):
        self.calls += 1
        if isinstance(self._reply, Exception):
            raise self._reply
        return self._reply


_GOOD_REPLY = json.dumps({
    "category": "AI-agent", "related_project": "AIDash",
    "tier": "now", "reason": "直接相关",
})


# ---- enrichment happy path -------------------------------------------------
@pytest.mark.unit
def test_enrich_fills_fields(tmp_path):
    client = _StubClient(_GOOD_REPLY)
    out = rr.enrich_repos([_card()], client=client, projects=["AIDash"],
                          cache_path=tmp_path / "c.json")
    assert client.calls == 1
    assert out[0].category == "AI-agent"
    assert out[0].related_project == "AIDash"
    assert out[0].tier == TIER_NOW
    assert out[0].reason == "直接相关"
    assert out[0].enriched is True


@pytest.mark.unit
def test_enrich_caches_by_content(tmp_path):
    cache = tmp_path / "c.json"
    client = _StubClient(_GOOD_REPLY)
    rr.enrich_repos([_card()], client=client, projects=["AIDash"], cache_path=cache)
    # Second run, identical repo/description → cache hit, NO new LLM call.
    client2 = _StubClient(_GOOD_REPLY)
    out = rr.enrich_repos([_card()], client=client2, projects=["AIDash"],
                          cache_path=cache)
    assert client2.calls == 0
    assert out[0].category == "AI-agent"


@pytest.mark.unit
def test_enrich_reanalyzes_on_description_change(tmp_path):
    cache = tmp_path / "c.json"
    rr.enrich_repos([_card(description="old")], client=_StubClient(_GOOD_REPLY),
                    projects=["AIDash"], cache_path=cache)
    client2 = _StubClient(_GOOD_REPLY)
    rr.enrich_repos([_card(description="new blurb")], client=client2,
                    projects=["AIDash"], cache_path=cache)
    assert client2.calls == 1  # content hash changed → miss → re-analyze


# ---- degrade paths ---------------------------------------------------------
@pytest.mark.unit
def test_no_client_returns_objective_only(tmp_path, monkeypatch):
    # Simulate a keyless env: default_client() yields None → no enrichment.
    monkeypatch.setattr(rr, "default_client", lambda: None)
    out = rr.enrich_repos([_card()], client=None, projects=["AIDash"],
                          cache_path=tmp_path / "c.json")
    assert out[0].enriched is False
    assert out[0].tier == TIER_HORIZON  # default until judged


@pytest.mark.unit
def test_llm_error_degrades_that_card(tmp_path):
    client = _StubClient(LLMError("boom"))
    out = rr.enrich_repos([_card()], client=client, projects=["AIDash"],
                          cache_path=tmp_path / "c.json")
    assert out[0].enriched is False


@pytest.mark.unit
def test_bad_json_reply_degrades(tmp_path):
    out = rr.enrich_repos([_card()], client=_StubClient("not json"),
                          projects=["AIDash"], cache_path=tmp_path / "c.json")
    assert out[0].enriched is False


# ---- validation / clamping -------------------------------------------------
@pytest.mark.unit
def test_hallucinated_project_is_dropped(tmp_path):
    reply = json.dumps({"category": "x", "related_project": "NotMyProject",
                        "tier": "now", "reason": "r"})
    out = rr.enrich_repos([_card()], client=_StubClient(reply),
                          projects=["AIDash"], cache_path=tmp_path / "c.json")
    assert out[0].related_project is None  # not in the known-projects list


@pytest.mark.unit
def test_project_match_is_case_insensitive(tmp_path):
    reply = json.dumps({"category": "x", "related_project": "aidash",
                        "tier": "now", "reason": "r"})
    out = rr.enrich_repos([_card()], client=_StubClient(reply),
                          projects=["AIDash"], cache_path=tmp_path / "c.json")
    assert out[0].related_project == "AIDash"  # echoes canonical casing


@pytest.mark.unit
def test_unknown_tier_defaults_to_horizon(tmp_path):
    reply = json.dumps({"category": "x", "related_project": None,
                        "tier": "someday", "reason": "r"})
    out = rr.enrich_repos([_card()], client=_StubClient(reply),
                          projects=[], cache_path=tmp_path / "c.json")
    assert out[0].tier == TIER_HORIZON


@pytest.mark.unit
def test_reason_is_length_capped(tmp_path):
    reply = json.dumps({"category": "x", "related_project": None,
                        "tier": "now", "reason": "很长" * 100})
    out = rr.enrich_repos([_card()], client=_StubClient(reply),
                          projects=[], cache_path=tmp_path / "c.json")
    assert len(out[0].reason) <= rr._MAX_REASON


@pytest.mark.unit
def test_fenced_json_is_parsed(tmp_path):
    reply = "```json\n" + _GOOD_REPLY + "\n```"
    out = rr.enrich_repos([_card()], client=_StubClient(reply),
                          projects=["AIDash"], cache_path=tmp_path / "c.json")
    assert out[0].category == "AI-agent"


@pytest.mark.unit
def test_cache_hit_revalidates_stale_project(tmp_path):
    # Cache a card whose related_project is AIDash, then re-run with a projects
    # list that no longer contains AIDash: the cache hit must drop the stale
    # project (self-heal) WITHOUT an LLM re-call.
    cache = tmp_path / "c.json"
    rr.enrich_repos([_card()], client=_StubClient(_GOOD_REPLY),
                    projects=["AIDash"], cache_path=cache)
    client2 = _StubClient(_GOOD_REPLY)
    out = rr.enrich_repos([_card()], client=client2, projects=["Financial"],
                          cache_path=cache)
    assert client2.calls == 0                 # still a cache hit
    assert out[0].related_project is None     # AIDash no longer valid → dropped
    assert out[0].category == "AI-agent"      # other fields preserved


@pytest.mark.unit
def test_empty_cards_short_circuits(tmp_path):
    client = _StubClient(_GOOD_REPLY)
    assert rr.enrich_repos([], client=client, cache_path=tmp_path / "c.json") == []
    assert client.calls == 0
