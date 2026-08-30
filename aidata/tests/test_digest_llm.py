"""LLM-path tests for build_digest (ADR-16/18/23).

Hermetic: fake clients, the golden's frozen fetch fixtures (no warehouse). These
tests exercise the M4 additions — the --llm path, the number-verification guard,
and every fallback route — while the golden test (test_digest_golden.py) proves
the template path is byte-identical and unchanged.
"""

import pytest

import L5_apps.digest.app as app
from L5_apps.digest.app import build_digest
from L5_apps.digest.llm import LLMError
from L5_apps.digest.sources import RepoRadar, SourceHealth

# Reuse the exact frozen fixtures that back the golden template output.
from tests.test_digest_golden import (
    _FROZEN_TRENDS, _FROZEN_MULTICA, _FROZEN_ADO, _FROZEN_AUTOMATION,
)

REPORT_DATE = "2026-07-10"


@pytest.fixture
def frozen(monkeypatch):
    monkeypatch.setattr(app, "fetch_raven_trends", lambda: _FROZEN_TRENDS)
    monkeypatch.setattr(app, "fetch_multica_completed", lambda: _FROZEN_MULTICA)
    monkeypatch.setattr(app, "fetch_ado_pr_trends", lambda: _FROZEN_ADO)
    # Freeze the seam _fetch_sources ACTUALLY calls. Freezing only
    # fetch_ado_pr_trends leaves the PR line reading this machine's live
    # warehouse — the exact trap recorded in tech-context.md 坑 ①.
    monkeypatch.setattr(app, "fetch_combined_pr_trends", lambda: _FROZEN_ADO)
    monkeypatch.setattr(app, "fetch_automation_trends", lambda: _FROZEN_AUTOMATION)
    # Radar frozen to empty/degraded so build_digest stays hermetic (no
    # warehouse/LLM). A degraded radar renders no section — template unchanged.
    monkeypatch.setattr(app, "fetch_repo_radar",
                        lambda: RepoRadar([], SourceHealth("github_repo", "skipped:未取")))


class FakeClient:
    def __init__(self, response: str):
        self._response = response

    def complete(self, system: str, user: str) -> str:
        return self._response


class RaisingClient:
    def complete(self, system: str, user: str) -> str:
        raise LLMError("simulated raven outage")


@pytest.mark.unit
def test_use_llm_false_equals_template(frozen):
    template = build_digest(REPORT_DATE)
    # explicit False and default both stay on the template path
    assert build_digest(REPORT_DATE, use_llm=False) == template


@pytest.mark.unit
def test_happy_path_polishes_and_passes_guard(frozen):
    template = build_digest(REPORT_DATE, use_llm=False)
    # Keep the LLM path valid against the extracted evidence: it may describe a
    # named adverse metric without claiming unsupported efficiency improvement.
    client = FakeClient('{"tldr": "成本上升，需关注", "todos": []}')
    out = build_digest(REPORT_DATE, use_llm=True, client=client)
    assert out != template
    assert "💡 点评: 成本上升，需关注" in out


@pytest.mark.unit
def test_llm_keeps_non_efficiency_qualitative_text(frozen):
    template = build_digest(REPORT_DATE, use_llm=False)
    client = FakeClient('{"tldr": "会话活跃，需关注波动", "todos": []}')
    out = build_digest(REPORT_DATE, use_llm=True, client=client)
    assert out != template
    assert "💡 点评: 会话活跃，需关注波动" in out


@pytest.mark.unit
def test_llm_rejects_unclassified_efficiency_assertion(frozen):
    template = build_digest(REPORT_DATE, use_llm=False)
    client = FakeClient('{"tldr": "成本上升，但工作更高效", "todos": []}')
    out = build_digest(REPORT_DATE, use_llm=True, client=client)
    assert "工作更高效" not in out
    assert "成本上升" in out or "整体趋势需关注" in out
    assert out != template


@pytest.mark.unit
def test_llm_preserves_non_efficiency_qualitative_text(frozen):
    template = build_digest(REPORT_DATE, use_llm=False)
    client = FakeClient('{"tldr": "会话活跃，需关注波动", "todos": []}')
    out = build_digest(REPORT_DATE, use_llm=True, client=client)
    assert "会话活跃，需关注波动" in out
    assert out != template


@pytest.mark.unit
def test_llm_rejects_negative_efficiency_without_threshold(frozen):
    template = build_digest(REPORT_DATE, use_llm=False)
    client = FakeClient('{"tldr": "效率趋弱", "todos": []}')
    out = build_digest(REPORT_DATE, use_llm=True, client=client)
    assert "效率趋弱" not in out
    assert out != template


@pytest.mark.unit
def test_fallback_on_llm_error(frozen):
    template = build_digest(REPORT_DATE, use_llm=False)
    out = build_digest(REPORT_DATE, use_llm=True, client=RaisingClient())
    assert out == template


@pytest.mark.unit
def test_fallback_on_hallucinated_number(frozen):
    template = build_digest(REPORT_DATE, use_llm=False)
    # The TL;DR sneaks in a fabricated number ($9999) → guard must reject and
    # the digest must fall back to the pure template.
    client = FakeClient('{"tldr": "昨日浪费高达 $9999，务必优化", "todos": []}')
    out = build_digest(REPORT_DATE, use_llm=True, client=client)
    assert out == template
    assert "9999" not in out


@pytest.mark.unit
def test_fallback_when_no_client_available(frozen, monkeypatch):
    template = build_digest(REPORT_DATE, use_llm=False)
    monkeypatch.setattr(app, "default_client", lambda: None)
    out = build_digest(REPORT_DATE, use_llm=True)  # no injected client, no key
    assert out == template


@pytest.mark.unit
def test_llm_path_never_crashes_on_garbage(frozen):
    template = build_digest(REPORT_DATE, use_llm=False)
    out = build_digest(REPORT_DATE, use_llm=True,
                       client=FakeClient("this is not json"))
    assert out == template
