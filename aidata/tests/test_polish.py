"""Unit tests for LLM slot-polish assembly (ADR-14/18).

Pure logic — `polish_digest` takes a fake client, no network.
"""

import pytest

from L5_apps.digest.llm import LLMError
from L5_apps.digest.polish import (
    PolishSlots, MAX_TLDR, MAX_TODO,
    build_prompt, parse_slots, truncate, apply_slots, polish_digest,
)

TEMPLATE = """# AI 使用日报 2026-07-09

> 数据源: raven✅

## ⚡ Trending
- 成本: 2699$ ↑(+24%) vs 昨 2180$

## 📅 今日 TODO
- P0: 查 pipeline:15/47 run 被取消(取消率32%)

## 🗂 昨日汇总
- 昨日花费 $2699.44，请求 8273 次

## 🔍 可改良
- 昨日无显著浪费信号"""


class FakeClient:
    def __init__(self, response: str):
        self._response = response
        self.calls: list[tuple[str, str]] = []

    def complete(self, system: str, user: str) -> str:
        self.calls.append((system, user))
        return self._response


@pytest.mark.unit
def test_build_prompt_forbids_numbers():
    system, user = build_prompt(TEMPLATE)
    # The instruction must forbid inventing/altering numbers.
    assert "数字" in system or "number" in system.lower()
    assert TEMPLATE in user


@pytest.mark.unit
def test_parse_slots_plain_json():
    slots = parse_slots('{"tldr": "总体上升", "todos": ["先查 pipeline"]}')
    assert isinstance(slots, PolishSlots)
    assert slots.tldr == "总体上升"
    assert slots.todos == ("先查 pipeline",)


@pytest.mark.unit
def test_parse_slots_strips_code_fence():
    raw = '```json\n{"tldr": "ok", "todos": []}\n```'
    slots = parse_slots(raw)
    assert slots.tldr == "ok"
    assert slots.todos == ()


@pytest.mark.unit
def test_parse_slots_garbage_raises():
    with pytest.raises(LLMError):
        parse_slots("not json at all")


@pytest.mark.unit
def test_truncate_enforces_cap():
    long = "字" * 300
    out = truncate(long, 150)
    assert len(out) <= 150
    assert out.endswith("…")


@pytest.mark.unit
def test_truncate_noop_when_short():
    assert truncate("short", 150) == "short"


@pytest.mark.unit
def test_apply_slots_inserts_tldr_and_preserves_priority():
    slots = PolishSlots(tldr="成本回落，关注 pipeline 取消",
                        todos=("优先排查 pipeline:15/47 取消(取消率32%)",))
    out = apply_slots(TEMPLATE, slots)
    assert "💡 点评: 成本回落" in out
    # Priority prefix stays template-owned.
    assert "- P0: 优先排查 pipeline" in out
    # Number-bearing lines outside TODO are untouched.
    assert "- 昨日花费 $2699.44，请求 8273 次" in out


@pytest.mark.unit
def test_apply_slots_no_todos_leaves_template_todo():
    slots = PolishSlots(tldr="平稳", todos=())
    out = apply_slots(TEMPLATE, slots)
    assert "- P0: 查 pipeline:15/47" in out  # unchanged when no refinement given


@pytest.mark.unit
def test_apply_slots_caps_lengths():
    slots = PolishSlots(tldr="长" * 400, todos=("改" * 400,))
    out = apply_slots(TEMPLATE, slots)
    tldr_line = next(l for l in out.splitlines() if "💡 点评" in l)
    # the commentary portion after the marker is capped
    assert len(tldr_line) <= len("> 💡 点评: ") + MAX_TLDR


@pytest.mark.unit
def test_polish_digest_end_to_end_with_fake_client():
    client = FakeClient('{"tldr": "整体上升", '
                        '"todos": ["尽快排查 pipeline:15/47 取消(取消率32%)"]}')
    out = polish_digest(TEMPLATE, client)
    assert "💡 点评: 整体上升" in out
    assert "- P0: 尽快排查 pipeline" in out
    assert len(client.calls) == 1
