"""Unit tests for the raven LLM client boundary (ADR-11).

Hermetic: `RavenClient` is exercised against a fake `urlopen`, never real
network. One `@pytest.mark.integration` test hits real raven and skips when
unreachable.
"""

import io
import json
import urllib.error

import pytest

from L5_apps.digest import llm
from L5_apps.digest.llm import (
    LLMConfig, LLMError, RavenClient, config_from_env,
)


@pytest.mark.unit
def test_config_from_env_reads_values(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_BASE_URL", "http://localhost:7024")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "rvn_secret")
    monkeypatch.setenv("ANTHROPIC_SMALL_FAST_MODEL", "claude-haiku-4.5")
    cfg = config_from_env()
    assert cfg is not None
    assert cfg.base_url == "http://localhost:7024"
    assert cfg.api_key == "rvn_secret"
    assert cfg.model == "claude-haiku-4.5"


@pytest.mark.unit
def test_config_from_env_none_without_key(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("RAVEN_API_KEY", raising=False)
    assert config_from_env() is None


@pytest.mark.unit
def test_config_from_env_defaults(monkeypatch):
    monkeypatch.delenv("ANTHROPIC_BASE_URL", raising=False)
    monkeypatch.delenv("ANTHROPIC_SMALL_FAST_MODEL", raising=False)
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("RAVEN_API_KEY", "rvn_fallback")
    cfg = config_from_env()
    assert cfg is not None
    assert cfg.base_url == "http://localhost:7024"
    assert cfg.model == "claude-haiku-4.5"
    assert cfg.api_key == "rvn_fallback"


def _fake_urlopen_returning(payload: dict):
    def _fake(req, timeout=None):
        body = json.dumps(payload).encode("utf-8")
        return io.BytesIO(body)
    return _fake


@pytest.mark.unit
def test_complete_parses_text(monkeypatch):
    payload = {"content": [{"type": "text", "text": "hello world"}]}
    monkeypatch.setattr(llm.urllib.request, "urlopen",
                        _fake_urlopen_returning(payload))
    client = RavenClient(LLMConfig("http://x", "k", "m", 10.0, 256))
    assert client.complete("sys", "user") == "hello world"


@pytest.mark.unit
def test_complete_network_error_raises_llmerror(monkeypatch):
    def _boom(req, timeout=None):
        raise urllib.error.URLError("connection refused")
    monkeypatch.setattr(llm.urllib.request, "urlopen", _boom)
    client = RavenClient(LLMConfig("http://x", "k", "m", 10.0, 256))
    with pytest.raises(LLMError):
        client.complete("sys", "user")


@pytest.mark.unit
def test_complete_malformed_body_raises_llmerror(monkeypatch):
    monkeypatch.setattr(llm.urllib.request, "urlopen",
                        _fake_urlopen_returning({"unexpected": "shape"}))
    client = RavenClient(LLMConfig("http://x", "k", "m", 10.0, 256))
    with pytest.raises(LLMError):
        client.complete("sys", "user")


@pytest.mark.unit
def test_error_never_leaks_api_key(monkeypatch):
    secret = "rvn_TOPSECRET_KEY_123"

    def _boom(req, timeout=None):
        raise urllib.error.URLError("boom")
    monkeypatch.setattr(llm.urllib.request, "urlopen", _boom)
    client = RavenClient(LLMConfig("http://x", secret, "m", 10.0, 256))
    try:
        client.complete("sys", "user")
        assert False, "expected LLMError"
    except LLMError as exc:
        assert secret not in str(exc)


@pytest.mark.integration
def test_real_raven_roundtrip():
    """Hits the live raven 7024 gateway; skips if unreachable / no key."""
    cfg = config_from_env()
    if cfg is None:
        pytest.skip("no API key in env")
    client = RavenClient(cfg)
    try:
        out = client.complete("You are terse.",
                              "Reply with exactly the word: pong")
    except LLMError as exc:
        pytest.skip(f"raven unreachable: {exc}")
    assert isinstance(out, str) and out.strip()
