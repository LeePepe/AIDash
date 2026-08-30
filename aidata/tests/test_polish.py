"""Unit tests for LLM slot-polish assembly (ADR-14/18).

Pure logic — `polish_digest` takes a fake client, no network.
"""

import pytest

from L5_apps.digest.llm import LLMError
from L5_apps.digest.polish import (
    PolishSlots, MAX_TLDR, build_prompt, parse_slots, truncate, apply_slots, polish_digest,
    EfficiencyEvidence, extract_efficiency_evidence, validate_efficiency_claim,
    neutral_fallback_tldr,
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
    assert "…" in out


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
    tldr_line = next(ln for ln in out.splitlines() if "💡 点评" in ln)
    # the commentary portion after the marker is capped
    assert len(tldr_line) <= len("> 💡 点评: ") + MAX_TLDR


@pytest.mark.unit
def test_polish_digest_end_to_end_with_fake_client():
    client = FakeClient('{"tldr": "整体上升", '
                        '"todos": ["尽快排查 pipeline:15/47 取消(取消率32%)"]}')
    out = polish_digest(TEMPLATE, client)
    assert "💡 点评: 整体趋势需关注，成本上升" in out
    assert "- P0: 尽快排查 pipeline" in out
    assert len(client.calls) == 1


# ---------------------------------------------------------------------------
# Efficiency-evidence gating tests (MY-1437/MY-1449)
# ---------------------------------------------------------------------------

# Template where cost rose +71%, waste rose +141%, and issues stayed flat.
TEMPLATE_COST_UP = """# AI 使用日报 2026-08-18

> 数据源: raven✅

## ⚡ Trending
- 成本: 4100$ ↑(+71%) vs 昨 2400$
- Token: 120000 ↑(+46%) vs 昨 82000
- 请求数: 950 ↑(+19%) vs 昨 800
- 浪费额: 580$ ↑(+141%) vs 昨 240$
- 完成任务: 128 ↑(+256%) vs 昨 36
- 完成 issue(近似): 0 ↑(+0%) vs 昨 0

## 📅 今日 TODO
- P0: 查浪费来源

## 🗂 昨日汇总
- 昨日花费 $4100.00，请求 950 次

## 🔍 可改良
- 昨日 $580 花在极小输出/大上下文，可考虑降级模型或裁剪上下文"""

# Template where cost went down
TEMPLATE_COST_DOWN = """# AI 使用日报 2026-08-18

> 数据源: raven✅

## ⚡ Trending
- 成本: 1800$ ↓(-25%) vs 昨 2400$
- 浪费额: 100$ ↓(-58%) vs 昨 240$

## 📅 今日 TODO
- P0: 继续优化

## 🗂 昨日汇总
- 昨日花费 $1800.00，请求 600 次

## 🔍 可改良
- 昨日无显著浪费信号"""


@pytest.mark.unit
def test_extract_evidence_cost_up():
    ev = extract_efficiency_evidence(TEMPLATE_COST_UP)
    assert ev.cost_pct == 71
    assert ev.waste_pct == 141
    assert ev.issues_pct == 0


@pytest.mark.unit
def test_extract_evidence_cost_down():
    ev = extract_efficiency_evidence(TEMPLATE_COST_DOWN)
    assert ev.cost_pct == -25
    assert ev.waste_pct == -58


@pytest.mark.unit
def test_extract_evidence_no_trend_lines():
    ev = extract_efficiency_evidence("# 空日报\n无数据")
    assert ev.cost_pct is None
    assert ev.waste_pct is None


@pytest.mark.unit
def test_allows_positive_claim_when_cost_down_waste_down_with_output_signal():
    ev = EfficiencyEvidence(cost_pct=-25, waste_pct=-58, tasks_pct=12, issues_pct=4)
    assert ev.allows_positive_claim() is True


@pytest.mark.unit
def test_disallows_positive_claim_when_cost_up():
    ev = EfficiencyEvidence(cost_pct=71, waste_pct=-10, tasks_pct=12)
    assert ev.allows_positive_claim() is False


@pytest.mark.unit
def test_disallows_positive_claim_when_waste_up():
    ev = EfficiencyEvidence(cost_pct=-10, waste_pct=141, tasks_pct=12)
    assert ev.allows_positive_claim() is False


@pytest.mark.unit
def test_disallows_positive_claim_when_both_up():
    ev = EfficiencyEvidence(cost_pct=71, waste_pct=141, tasks_pct=12)
    assert ev.allows_positive_claim() is False


@pytest.mark.unit
def test_disallows_positive_claim_when_no_data():
    ev = EfficiencyEvidence(cost_pct=None, waste_pct=None)
    assert ev.allows_positive_claim() is False


@pytest.mark.unit
def test_disallows_positive_claim_when_output_signal_missing():
    ev = EfficiencyEvidence(cost_pct=-10, waste_pct=None)
    assert ev.allows_positive_claim() is False


@pytest.mark.unit
def test_validate_rejects_positive_claim_when_cost_up():
    ev = EfficiencyEvidence(cost_pct=71, waste_pct=141, issues_pct=0)
    assert validate_efficiency_claim("效率明显提升", ev) is False
    assert validate_efficiency_claim("效率更高", ev) is False
    assert validate_efficiency_claim("效能提升", ev) is False
    assert validate_efficiency_claim("投入产出更好", ev) is False
    assert validate_efficiency_claim("效率上升", ev) is False
    assert validate_efficiency_claim("效率增长", ev) is False
    assert validate_efficiency_claim("成本上升，但效率大幅增长", ev) is False
    assert validate_efficiency_claim("成本上升，但 efficiency improved", ev) is False
    assert validate_efficiency_claim("成本上升，但效率创出新高", ev) is False
    assert validate_efficiency_claim("效率不如昨天", ev) is False
    assert validate_efficiency_claim("工作更高效", ev) is False
    assert validate_efficiency_claim("效率趋弱", ev) is False
    assert validate_efficiency_claim("效率回升", ev) is False
    assert validate_efficiency_claim("效率变好", ev) is False
    assert validate_efficiency_claim("效率明显下降", ev) is False


@pytest.mark.unit
def test_validate_rejects_negative_claim_without_input_evidence():
    ev = EfficiencyEvidence(cost_pct=None, waste_pct=None, tasks_pct=-10, issues_pct=-12)
    assert validate_efficiency_claim("效率下降", ev) is False
    assert validate_efficiency_claim("production fell", ev) is False


@pytest.mark.unit
def test_validate_rejects_positive_activity_without_counter_signal():
    ev = EfficiencyEvidence(cost_pct=71, waste_pct=141, tasks_pct=256, issues_pct=0)
    assert validate_efficiency_claim("完成任务上升", ev) is False


@pytest.mark.unit
def test_validate_rejects_positive_activity_without_input_signal():
    ev = EfficiencyEvidence(cost_pct=None, waste_pct=None, tasks_pct=20, issues_pct=0)
    assert validate_efficiency_claim("完成任务上升", ev) is False
    assert validate_efficiency_claim("任务上升", ev) is False


@pytest.mark.unit
def test_validate_rejects_partial_metric_evidence():
    ev = EfficiencyEvidence(cost_pct=71, waste_pct=None, issues_pct=0)
    assert validate_efficiency_claim("成本上升，浪费下降", ev) is False
    assert validate_efficiency_claim("成本上升，任务下降", ev) is False


@pytest.mark.unit
def test_validate_neutral_requires_named_adverse_metric():
    ev = EfficiencyEvidence(cost_pct=71, waste_pct=141, issues_pct=0)
    assert validate_efficiency_claim("整体平稳，需关注", ev) is False
    assert validate_efficiency_claim("请求量上升", ev) is False
    assert validate_efficiency_claim("成本上升，需关注", ev) is True
    assert validate_efficiency_claim("浪费上升，需关注", ev) is True


@pytest.mark.unit
def test_validate_allows_positive_claim_when_evidence_supports():
    ev = EfficiencyEvidence(cost_pct=-25, waste_pct=-58, tasks_pct=12, issues_pct=4)
    assert validate_efficiency_claim("效率明显提升", ev) is True
    assert validate_efficiency_claim("效率增长", ev) is True
    assert validate_efficiency_claim("效率回升", ev) is True
    assert validate_efficiency_claim("效率变好", ev) is True
    assert validate_efficiency_claim("工作更高效", ev) is False
    assert validate_efficiency_claim("效率明显下降", ev) is False
    assert validate_efficiency_claim("效率趋弱", ev) is False


@pytest.mark.unit
def test_neutral_fallback_mentions_counter_signal():
    ev = EfficiencyEvidence(cost_pct=71, waste_pct=141)
    fb = neutral_fallback_tldr(ev)
    assert "浪费上升" in fb  # highest counter-signal


@pytest.mark.unit
def test_neutral_fallback_cost_only():
    ev = EfficiencyEvidence(cost_pct=30, waste_pct=None)
    fb = neutral_fallback_tldr(ev)
    assert "成本上升" in fb


@pytest.mark.unit
def test_build_prompt_injects_constraint_when_cost_up():
    system, _ = build_prompt(TEMPLATE_COST_UP)
    assert "效率" in system  # the efficiency constraint was injected


@pytest.mark.unit
def test_build_prompt_includes_constraint_when_cost_down_but_evidence_is_insufficient():
    system, _ = build_prompt(TEMPLATE_COST_DOWN)
    assert "成本或浪费上升" in system


@pytest.mark.unit
def test_polish_digest_rejects_false_efficiency_claim():
    """LLM claims efficiency improved despite cost +71% / waste +141%."""
    client = FakeClient('{"tldr": "效率明显提升，继续保持", '
                        '"todos": ["优先排查浪费来源"]}')
    out = polish_digest(TEMPLATE_COST_UP, client)
    # The false claim must be replaced with a neutral fallback.
    assert "效率" not in out or "提升" not in out
    assert "浪费上升" in out or "成本上升" in out
    assert "- P0: 优先排查浪费来源" in out  # TODOs are kept


@pytest.mark.unit
@pytest.mark.parametrize(
    "claim",
    [
        "效率上升，继续保持",
        "效率增长，继续保持",
        "成本上升，但效率大幅增长",
        "成本上升，但工作更高效",
        "效率不如昨天",
    ],
)
def test_polish_digest_rejects_explicit_rise_phrases_claims(claim):
    """Explicit rise/growth wording and unclassified efficiency prose must be rejected under mixed evidence."""
    client = FakeClient(f'{{"tldr": "{claim}", "todos": ["优先排查浪费来源"]}}')
    out = polish_digest(TEMPLATE_COST_UP, client)
    assert claim not in out
    assert "浪费上升" in out or "成本上升" in out
    assert "- P0: 优先排查浪费来源" in out


@pytest.mark.unit
def test_polish_digest_rejects_english_efficiency_claim_and_missing_input_negative():
    client = FakeClient('{"tldr": "成本上升，但 efficiency improved", "todos": ["优先排查浪费来源"]}')
    out = polish_digest(TEMPLATE_COST_UP, client)
    assert "efficiency improved" not in out.lower()
    assert "浪费上升" in out or "成本上升" in out

    negative_client = FakeClient('{"tldr": "效率下降", "todos": ["继续观察"]}')
    negative_out = polish_digest("# AI 使用日报\n\n## ⚡ Trending\n- 完成任务: 11 ↓(-12%) vs 昨 12\n- 完成 issue: 8 ↓(-11%) vs 昨 9\n", negative_client)
    assert "效率下降" not in negative_out
    assert "整体趋势需关注" in negative_out or "数据不足" in negative_out


@pytest.mark.unit
def test_polish_digest_keeps_valid_positive_when_evidence_supports():
    """A sufficient evidence set should still permit a genuine positive claim."""
    valid_template = """# AI 使用日报 2026-08-18

> 数据源: raven✅

## ⚡ Trending
- 成本: 1800$ ↓(-25%) vs 昨 2400$
- 浪费额: 100$ ↓(-58%) vs 昨 240$
- 完成任务: 128 ↑(+32%) vs 昨 96
- 完成 issue(近似): 18 ↑(+29%) vs 昨 14
- 请求数: 540 ↑(+12%) vs 昨 480

## 📅 今日 TODO
- P0: 继续优化

## 🗂 昨日汇总
- 昨日花费 $1800.00，请求 540 次

## 🔍 可改良
- 昨日无显著浪费信号"""
    client = FakeClient('{"tldr": "效率增长，产出更高", "todos": ["继续优化"]}')
    out = polish_digest(valid_template, client)
    assert "效率增长" in out
    assert "整体趋势需关注" not in out


@pytest.mark.unit
def test_polish_digest_preserves_non_efficiency_qualitative_text():
    """Qualitative prose without an efficiency claim or tracked metric direction must survive unchanged."""
    client = FakeClient('{"tldr": "会话活跃，需关注波动", "todos": ["观察波动"]}')
    out = polish_digest(TEMPLATE_COST_UP, client)
    assert "会话活跃，需关注波动" in out
    assert "整体趋势需关注" not in out
    assert "观察波动" in out


@pytest.mark.unit
def test_polish_digest_keeps_valid_neutral_commentary():
    """LLM provides neutral commentary when cost is up — should be kept."""
    client = FakeClient('{"tldr": "成本上升，需关注", '
                        '"todos": ["排查浪费来源"]}')
    out = polish_digest(TEMPLATE_COST_UP, client)
    assert "成本上升，需关注" in out


@pytest.mark.unit
def test_polish_digest_rejects_task_growth_without_input_signal():
    """Tasks can rise without proving efficiency; missing cost/waste data must fall back."""
    partial_template = """# AI 使用日报 2026-08-18

> 数据源: raven✅

## ⚡ Trending
- 完成任务: 120 ↑(+20%) vs 昨 100
- 完成 issue(近似): 10 ↑(+5%) vs 昨 9

## 📅 今日 TODO
- P0: 继续推进

## 🗂 昨日汇总
- 昨日花费 $0.00，请求 0 次

## 🔍 可改良
- 无额外信息"""
    client = FakeClient('{"tldr": "完成任务上升", "todos": ["继续推进"]}')
    out = polish_digest(partial_template, client)
    assert "完成任务上升" not in out
    assert "整体趋势需关注" in out or "数据不足以判断" in out


@pytest.mark.unit
@pytest.mark.parametrize(
    "claim",
    [
        "成本上升，但效率增长",
        "效率增长，但成本上升",
    ],
)
def test_polish_digest_rejects_contradictory_metric_and_efficiency_clauses(claim):
    """Contradictory metric facts must win over the positive claim, regardless of ordering."""
    client = FakeClient(f'{{"tldr": "{claim}", "todos": ["继续优化"]}}')
    out = polish_digest(TEMPLATE_COST_DOWN, client)
    assert claim not in out
    assert "整体趋势需" in out or "数据不足以判断" in out
    assert "效率增长" not in out


@pytest.mark.unit
def test_polish_digest_rejects_positive_when_cost_down_but_evidence_is_insufficient():
    """The evidence is insufficient to authorize a positive efficiency claim."""
    client = FakeClient('{"tldr": "效率明显提升", "todos": ["继续优化"]}')
    out = polish_digest(TEMPLATE_COST_DOWN, client)
    assert "效率明显提升" not in out
    assert "整体趋势需" in out or "数据不足以判断" in out


@pytest.mark.unit
def test_polish_digest_keeps_non_efficiency_qualitative_text():
    """Qualitative text that is not an efficiency claim must survive unchanged."""
    client = FakeClient('{"tldr": "会话活跃，需关注波动", "todos": ["继续观察"]}')
    out = polish_digest(TEMPLATE_COST_UP, client)
    assert "会话活跃，需关注波动" in out
    assert "整体趋势需关注" not in out
