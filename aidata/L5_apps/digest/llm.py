"""The single LLM network boundary for the digest (ADR-11).

L1–L4 are pure data. This module is the ONLY place in the codebase that talks
to an LLM over the network — the raven reverse-proxy at localhost:7024, which
speaks the Anthropic Messages API and is pinned to `claude-haiku-4.5` for the
small/fast model. Isolating the dependency here keeps the app layer's polish
logic pure and testable (it takes an `LLMClient` by dependency injection).

Stdlib `urllib.request` only — no new dependency. Any network/timeout/HTTP/parse
failure is normalized to `LLMError` so callers can fall back to the template
(ADR-16/18/23). The API key is read from the environment and never logged.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Protocol

DEFAULT_BASE_URL = "http://localhost:7024"
DEFAULT_MODEL = "claude-haiku-4.5"
DEFAULT_TIMEOUT_S = 20.0
DEFAULT_MAX_TOKENS = 512
ANTHROPIC_VERSION = "2023-06-01"


class LLMError(Exception):
    """Any failure talking to the LLM. Never carries the API key."""


@dataclass(frozen=True)
class LLMConfig:
    base_url: str
    api_key: str
    model: str
    timeout_s: float
    max_tokens: int


def config_from_env() -> LLMConfig | None:
    """Build config from env; return None when no API key is present.

    A missing key is not an error — it means the caller should stay on the
    template path. Accepts either ANTHROPIC_API_KEY or RAVEN_API_KEY.
    """
    api_key = os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("RAVEN_API_KEY")
    if not api_key:
        return None
    return LLMConfig(
        base_url=os.environ.get("ANTHROPIC_BASE_URL", DEFAULT_BASE_URL),
        api_key=api_key,
        model=os.environ.get("ANTHROPIC_SMALL_FAST_MODEL", DEFAULT_MODEL),
        timeout_s=DEFAULT_TIMEOUT_S,
        max_tokens=DEFAULT_MAX_TOKENS,
    )


class LLMClient(Protocol):
    def complete(self, system: str, user: str) -> str: ...


class RavenClient:
    """Anthropic-Messages client over urllib, pointed at the raven gateway."""

    def __init__(self, config: LLMConfig) -> None:
        self._cfg = config

    def complete(self, system: str, user: str) -> str:
        """Send one system+user turn; return the assistant's text.

        Raises LLMError on any transport, HTTP, or response-shape problem. The
        error message is scrubbed so the API key can never appear in a log.
        """
        body = json.dumps({
            "model": self._cfg.model,
            "max_tokens": self._cfg.max_tokens,
            "system": system,
            "messages": [{"role": "user", "content": user}],
        }).encode("utf-8")
        req = urllib.request.Request(
            f"{self._cfg.base_url}/v1/messages",
            data=body,
            headers={
                "x-api-key": self._cfg.api_key,
                "anthropic-version": ANTHROPIC_VERSION,
                "content-type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self._cfg.timeout_s) as resp:
                raw = resp.read().decode("utf-8")
            payload = json.loads(raw)
            return self._extract_text(payload)
        except LLMError:
            raise
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise LLMError(f"raven request failed: {self._scrub(exc)}") from None
        except (ValueError, json.JSONDecodeError) as exc:
            raise LLMError(f"raven response parse failed: {exc}") from None

    @staticmethod
    def _extract_text(payload: dict) -> str:
        try:
            blocks = payload["content"]
            texts = [b["text"] for b in blocks if b.get("type") == "text"]
        except (KeyError, TypeError) as exc:
            raise LLMError(f"unexpected response shape: {exc}") from None
        if not texts:
            raise LLMError("response had no text content")
        return "".join(texts)

    def _scrub(self, exc: object) -> str:
        msg = str(exc)
        return msg.replace(self._cfg.api_key, "***")


def default_client() -> LLMClient | None:
    """The env-configured client, or None when no API key is available."""
    cfg = config_from_env()
    return RavenClient(cfg) if cfg else None
