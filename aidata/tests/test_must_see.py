"""Unit tests for the 必看层 (must-see) compact layer (ADR-14)."""

import pytest

from L5_apps.digest.must_see import must_see_layer

# A representative full digest (superset of the golden shape) with an LLM 点评
# line, several flat-streak "背景噪音" items, alerts, TODO, and deep analysis.
FULL_MD = """# AI 使用日报 2026-07-09

> 💡 点评: 成本回落但请求下滑，关注会话骤降

> 数据源: raven✅ multica✅ ADO✅ state.db✅

## ⚡ Trending
- 成本: 2699$ ↑(+24%) vs 昨 2180$ · 7日均 1866$
- Token: 683860023 ↑(+37%) vs 昨 498605887 · 7日均 469198137
- 请求数: 8273 ↑(+80%) vs 昨 4595 · 7日均 4904
- 浪费额: 262$ ↑(+371%) vs 昨 56$ · 7日均 103$
- 完成任务: 32 → vs 昨 — · 7日均 86
- 会话数: 76 ↑(+300%) vs 昨 19 · 7日均 40
- 开PR: 4 ↓(-20%) vs 昨 5 · 7日均 4
- 自动化占比: 71% ↑ vs 昨 63%
- 完成 issue(近似): 26 ↑(+420%) vs 昨 5 · 7日均 21
- 🚩 成本已连续 5 天持平

## 📅 今日 TODO
- P0: 查 pipeline:15/47 run 被取消(取消率32%)

## 🗂 昨日汇总
- 昨日花费 $2699.44，请求 8273 次
- 昨日完成: 26 个 issue（近似）（WorkspaceA: 5, my: 21）
- 开了 4 个 PR（合并 3 个）
- 自动化占比 71%（自动 120 / 手动 49）

## 🔍 可改良
- 昨日 $262 花在极小输出/大上下文，可考虑降级模型或裁剪上下文
"""


@pytest.mark.unit
def test_within_budget():
    out = must_see_layer(FULL_MD)
    assert len(out) <= 1500


@pytest.mark.unit
def test_keeps_tldr_and_arrows():
    out = must_see_layer(FULL_MD)
    assert "点评" in out
    assert "成本回落" in out
    assert "↑" in out  # trend arrows preserved
    assert "成本" in out


@pytest.mark.unit
def test_folds_flat_streak_into_background_noise():
    out = must_see_layer(FULL_MD)
    # the raw "连续 5 天持平" alert line is folded away...
    assert "连续 5 天持平" not in out
    # ...into a single background-noise counter line
    assert "🔇 背景噪音" in out
    assert "1 项无变化" in out


@pytest.mark.unit
def test_keeps_todo_and_analysis():
    out = must_see_layer(FULL_MD)
    assert "今日 TODO" in out
    assert "P0" in out


@pytest.mark.unit
def test_over_budget_truncates():
    huge = FULL_MD + "\n".join(f"- 噪音行 {i} 内容内容内容内容" for i in range(500))
    out = must_see_layer(huge, budget=800)
    assert len(out) <= 800


@pytest.mark.unit
def test_no_noise_no_fold_line():
    # A digest without any flat-streak alert must not emit a background-noise line.
    md = "\n".join(ln for ln in FULL_MD.splitlines() if "🚩" not in ln)
    out = must_see_layer(md)
    assert "🔇 背景噪音" not in out


@pytest.mark.unit
def test_degraded_md_does_not_crash():
    degraded = "# AI 使用日报 2026-07-09\n\n## ⚡ Trending\n- 数据缺失（raven 未采到）\n"
    out = must_see_layer(degraded)
    assert "数据缺失" in out
    assert len(out) <= 1500
