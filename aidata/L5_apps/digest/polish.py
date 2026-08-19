"""LLM slot-polish assembly for the digest (ADR-14/18).

The deterministic template is the source of every number. This module drives an
optional LLM pass that fills only two kinds of bounded free-text slots:

  1. An overall TL;DR "点评" line inserted after the title.
  2. Refined wording for each rule-based TODO — the priority prefix (P0/P1/...)
     and the underlying signal stay template-owned; only the phrasing changes.

Slots are hard length-capped (ADR-14). `apply_slots` never touches a
number-bearing line other than swapping a TODO's prose (whose numbers the
downstream guard re-verifies). `polish_digest` is the only function that calls
the injected client; everything else is pure.

Efficiency-evidence gating (MY-1437/MY-1449): the TL;DR must not claim
efficiency improved unless auditable evidence supports it. When cost or waste
rose, positive efficiency language is rejected and replaced with a deterministic
neutral fallback that retains the most material counter-signal.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass

from L5_apps.digest.llm import LLMError, LLMClient

MAX_TLDR = 150      # chars for the 点评 line (ADR-14 must-see budget)
MAX_TODO = 120      # chars for each refined TODO

_TODO_RE = re.compile(r"^- (P\d): (.*)$")
_TLDR_MARKER = "> 💡 点评: "


@dataclass(frozen=True)
class PolishSlots:
    tldr: str
    todos: tuple[str, ...]


# ---------------------------------------------------------------------------
# Efficiency-evidence extraction and gating (MY-1437/MY-1449)
# ---------------------------------------------------------------------------

# Matches trend lines like "- 成本: 2699$ ↑(+24%) vs 昨 2180$"
# Captures the label and the signed percentage inside parentheses.
_TREND_PCT_RE = re.compile(
    r"^- (成本|Token|请求数|浪费额|完成任务|会话数|开PR|完成 issue)"
    r".*?\(([+-]\d+)%\)"
)

# Labels whose percentage changes are relevant to efficiency claims.
_COST_LABELS = frozenset({"成本"})
_WASTE_LABELS = frozenset({"浪费额"})


@dataclass(frozen=True)
class EfficiencyEvidence:
    """Auditable evidence extracted from the template's trend percentages.

    `cost_pct` / `waste_pct`: the day-over-day % change from the template,
    or None when the trend line is missing or has insufficient data.
    """
    cost_pct: int | None
    waste_pct: int | None

    def allows_positive_claim(self) -> bool:
        """Return True only when evidence supports a positive efficiency claim.

        Condition (auditable threshold):
          - cost_pct is present AND <= 0 (cost did not rise)
          - waste_pct is absent OR <= 0 (waste did not rise)

        Any upward cost or waste movement makes the evidence insufficient.
        """
        if self.cost_pct is None:
            return False  # no data → cannot claim improvement
        if self.cost_pct > 0:
            return False
        if self.waste_pct is not None and self.waste_pct > 0:
            return False
        return True

    def top_counter_signal(self) -> str:
        """Return the most material counter-signal for neutral fallback text."""
        signals: list[tuple[int, str]] = []
        if self.waste_pct is not None and self.waste_pct > 0:
            signals.append((self.waste_pct, "浪费上升"))
        if self.cost_pct is not None and self.cost_pct > 0:
            signals.append((self.cost_pct, "成本上升"))
        if signals:
            signals.sort(reverse=True)
            return signals[0][1]
        return "数据不足以判断"


def extract_efficiency_evidence(template_md: str) -> EfficiencyEvidence:
    """Parse trend percentages from the template to build auditable evidence."""
    cost_pct: int | None = None
    waste_pct: int | None = None
    for line in template_md.splitlines():
        m = _TREND_PCT_RE.match(line)
        if m:
            label, pct_str = m.group(1), m.group(2)
            pct = int(pct_str)
            if label in _COST_LABELS:
                cost_pct = pct
            elif label in _WASTE_LABELS:
                waste_pct = pct
    return EfficiencyEvidence(cost_pct=cost_pct, waste_pct=waste_pct)


# Positive-efficiency keywords that must not appear when evidence is negative.
_POSITIVE_EFFICIENCY_RE = re.compile(
    r"效率.{0,4}(提升|提高|改善|进步|优化|好转|增强)"
    r"|efficiency.{0,6}(improv|increas|better|gain)"
    r"|(省|节约|降低).{0,4}(成本|开销|花费)"
    r"|用得更(省|好|高效)"
    r"|整体(向好|改善|优化)",
    re.IGNORECASE,
)


def validate_efficiency_claim(tldr: str, evidence: EfficiencyEvidence) -> bool:
    """Return True if the TL;DR is consistent with the evidence.

    Rejects when:
      - evidence does NOT allow a positive efficiency claim, AND
      - the TL;DR contains positive efficiency language.
    """
    if evidence.allows_positive_claim():
        return True  # positive claims are fine when evidence supports them
    return _POSITIVE_EFFICIENCY_RE.search(tldr) is None


def neutral_fallback_tldr(evidence: EfficiencyEvidence) -> str:
    """Deterministic neutral TL;DR when the LLM's claim is rejected."""
    counter = evidence.top_counter_signal()
    return f"整体趋势需关注，{counter}"


# ---------------------------------------------------------------------------
# Prompt and slot assembly
# ---------------------------------------------------------------------------

_SYSTEM = (
    "你是 AI 使用日报的文字润色助手。给你一份已经算好数字的日报模板。"
    "严格规则：绝对不要发明、改动、或复述任何数字/百分比/金额——数字全部由模板拥有。"
    "你只做两件事：(1) 写一句总体点评（简短、口语、不含任何数字）；"
    "(2) 把每条 TODO 的措辞改得更可执行（保留其中已有的数字原样，不加不减，不改优先级）。"
    "只返回严格 JSON：{\"tldr\": \"...\", \"todos\": [\"...\", ...]}，不要解释、不要代码块外的文字。"
)

_EFFICIENCY_CONSTRAINT = (
    "额外约束：模板中成本或浪费上升时，点评绝对不能说效率提升/改善/优化/好转。"
    "此时用中性或谨慎措辞，并提及最突出的反向信号。"
)


def build_prompt(template_md: str) -> tuple[str, str]:
    """Return (system, user) prompts for the polish pass.

    When evidence shows cost/waste rose, an extra constraint is injected into the
    system prompt forbidding positive efficiency claims.
    """
    evidence = extract_efficiency_evidence(template_md)
    system = _SYSTEM
    if not evidence.allows_positive_claim():
        system = system + _EFFICIENCY_CONSTRAINT
    user = ("这是今天的日报模板，请按规则返回 JSON：\n\n" + template_md)
    return system, user


def _strip_fence(raw: str) -> str:
    text = raw.strip()
    if text.startswith("```"):
        # drop the opening fence line and any trailing fence
        lines = text.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    return text


def parse_slots(raw: str) -> PolishSlots:
    """Parse the LLM's JSON reply into slots; raise LLMError if unparseable."""
    try:
        data = json.loads(_strip_fence(raw))
    except (ValueError, json.JSONDecodeError) as exc:
        raise LLMError(f"polish reply not JSON: {exc}") from None
    if not isinstance(data, dict):
        raise LLMError("polish reply not a JSON object")
    tldr = data.get("tldr", "")
    todos = data.get("todos", [])
    if not isinstance(tldr, str) or not isinstance(todos, list):
        raise LLMError("polish reply has wrong field types")
    return PolishSlots(tldr=tldr,
                       todos=tuple(str(t) for t in todos))


def truncate(text: str, n: int) -> str:
    """Hard char cap; append an ellipsis when the text was cut."""
    if len(text) <= n:
        return text
    return text[: n - 1] + "…"


def apply_slots(template_md: str, slots: PolishSlots) -> str:
    """Insert the TL;DR line and swap TODO wording, preserving all numbers.

    Pure: builds a new string, never mutates the input. The priority prefix of
    each TODO is kept from the template; only its prose is replaced (in order),
    and only while refined todos remain.
    """
    lines = template_md.splitlines()
    out: list[str] = []
    todo_iter = iter(slots.todos)

    for i, line in enumerate(lines):
        out.append(line)
        # Insert the 点评 line right after the H1 title.
        if i == 0 and line.startswith("# ") and slots.tldr.strip():
            out.append("")
            out.append(_TLDR_MARKER + truncate(slots.tldr.strip(), MAX_TLDR))

    refined = _refine_todos(out, todo_iter)
    return "\n".join(refined)


def _refine_todos(lines: list[str], todo_iter) -> list[str]:
    result: list[str] = []
    for line in lines:
        m = _TODO_RE.match(line)
        if m:
            replacement = next(todo_iter, None)
            if replacement is not None and replacement.strip():
                result.append(f"- {m.group(1)}: "
                              f"{truncate(replacement.strip(), MAX_TODO)}")
                continue
        result.append(line)
    return result


def polish_digest(template_md: str, client: LLMClient) -> str:
    """Run the LLM polish pass. Propagates LLMError for the caller to catch.

    After parsing the LLM's reply, validates the TL;DR against efficiency
    evidence extracted from the template. If the LLM made an unsupported
    positive efficiency claim, the TL;DR is replaced with a deterministic
    neutral fallback (MY-1437/MY-1449). TODOs are kept as-is since they only
    rephrase template-owned action items.
    """
    system, user = build_prompt(template_md)
    raw = client.complete(system, user)
    slots = parse_slots(raw)
    evidence = extract_efficiency_evidence(template_md)
    if not validate_efficiency_claim(slots.tldr, evidence):
        slots = PolishSlots(
            tldr=neutral_fallback_tldr(evidence),
            todos=slots.todos,
        )
    return apply_slots(template_md, slots)
