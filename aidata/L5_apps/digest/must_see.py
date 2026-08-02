"""必看层 (must-see) compact layer for the digest (ADR-14).

The full digest md is the archive (必成 sink). The must-see layer is the compact
≤1500-char view that downstream pushes (AIDash cards, any future WeChat-style
push) consume. It is deterministic and template-based — it only trims and folds
the existing template text, never invents a number and never calls an LLM.

Layout (ADR-14): TL;DR → per-section trending (arrows kept) → trend alerts (with
"连续 3+ 天不变" folded into one "🔇 背景噪音: N 项无变化" line) → tomorrow's TODO
→ deep analysis. When over budget, deep analysis is trimmed first, then trending
extras, and the whole thing is hard-capped with an ellipsis.
"""

from __future__ import annotations

import re

DEFAULT_BUDGET = 1500
_TLDR_MARKER = "> 💡 点评: "
_ALERT_MARK = "🚩"
# "连续 N 天持平/不变" where N >= 3 counts as background noise to fold away.
_FLAT_RE = re.compile(r"连续\s*(\d+)\s*天.*?(?:持平|不变|无变化)")


def _split_sections(md: str) -> dict[str, list[str]]:
    """Split md into {heading: [body lines]}; the preamble is under key ''."""
    sections: dict[str, list[str]] = {"": []}
    current = ""
    for line in md.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            sections[current] = []
        else:
            sections.setdefault(current, []).append(line)
    return sections


def _find_section(sections: dict[str, list[str]], needle: str) -> list[str]:
    for heading, body in sections.items():
        if needle in heading:
            return body
    return []


def _content_lines(body: list[str]) -> list[str]:
    return [ln for ln in body if ln.strip()]


def _tldr(sections: dict[str, list[str]]) -> list[str]:
    """1–3 line TL;DR: the LLM 点评 line if present, else the 昨日汇总 headline."""
    for ln in sections.get("", []):
        if ln.startswith(_TLDR_MARKER):
            return [ln[len("> "):].strip()]
    summary = _content_lines(_find_section(sections, "昨日汇总"))
    return [summary[0].lstrip("- ").strip()] if summary else []


def _fold_alerts(trending: list[str]) -> tuple[list[str], list[str]]:
    """Return (kept trending lines, alert lines) with flat-streaks folded.

    Any alert line describing a 连续 N(≥3) 天不变 item is removed from the
    output and counted; the count becomes one "🔇 背景噪音" line.
    """
    kept: list[str] = []
    alerts: list[str] = []
    folded = 0
    for ln in _content_lines(trending):
        if _ALERT_MARK in ln:
            m = _FLAT_RE.search(ln)
            if m and int(m.group(1)) >= 3:
                folded += 1
                continue
            alerts.append(ln)
        else:
            kept.append(ln)
    if folded:
        alerts.append(f"- 🔇 背景噪音: {folded} 项无变化")
    return kept, alerts


def _assemble(tldr: list[str], trending: list[str], alerts: list[str],
              todo: list[str], analysis: list[str]) -> list[str]:
    blocks: list[str] = []
    if tldr:
        blocks += tldr + [""]
    if trending:
        blocks += ["## ⚡ Trending"] + trending + [""]
    if alerts:
        blocks += alerts + [""]
    if todo:
        blocks += ["## 📅 今日 TODO"] + todo + [""]
    if analysis:
        blocks += ["## 🔍 可改良"] + analysis
    return blocks


def _enforce_budget(tldr: list[str], trending: list[str], alerts: list[str],
                    todo: list[str], analysis: list[str], budget: int) -> str:
    """Drop analysis, then trending extras, then hard-truncate to fit budget."""
    trimmed_analysis = list(analysis)
    trimmed_trending = list(trending)
    for _ in range(len(analysis) + len(trending) + 1):
        text = "\n".join(_assemble(tldr, trimmed_trending, alerts, todo,
                                   trimmed_analysis)).rstrip()
        if len(text) <= budget:
            return text
        if trimmed_analysis:
            trimmed_analysis.pop()
        elif len(trimmed_trending) > 1:
            trimmed_trending.pop()
        else:
            break
    text = "\n".join(_assemble(tldr, trimmed_trending, alerts, todo,
                               trimmed_analysis)).rstrip()
    if len(text) > budget:
        text = text[: budget - 1] + "…"
    return text


def must_see_layer(full_md: str, budget: int = DEFAULT_BUDGET) -> str:
    """Fold the full digest md into the compact ≤budget must-see layer (ADR-14).

    Pure and deterministic: no LLM, no new numbers. Never raises on degraded or
    empty input.
    """
    sections = _split_sections(full_md)
    tldr = _tldr(sections)
    trending, alerts = _fold_alerts(_find_section(sections, "Trending"))
    todo = _content_lines(_find_section(sections, "今日 TODO"))
    analysis = _content_lines(_find_section(sections, "可改良"))
    return _enforce_budget(tldr, trending, alerts, todo, analysis, budget)
