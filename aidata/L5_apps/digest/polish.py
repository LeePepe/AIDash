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
    r"^- (成本|Token|请求数|浪费额|完成任务|已完成 issue|issues|tasks|会话数|开PR|完成 issue|完成 issue\(近似\))"
    r".*?\(([+-]\d+)%\)"
)

# Labels whose percentage changes are relevant to efficiency claims.
_COST_LABELS = frozenset({"成本"})
_WASTE_LABELS = frozenset({"浪费额"})
_OUTPUT_LABELS = frozenset({"Token", "请求数", "完成任务", "tasks", "issues", "已完成 issue", "完成 issue", "完成 issue(近似)"})


@dataclass(frozen=True)
class EfficiencyEvidence:
    """Auditable evidence extracted from the template's trend percentages.

    `cost_pct` / `waste_pct`: the day-over-day % change from the template,
    or None when the trend line is missing or has insufficient data.
    """
    cost_pct: int | None
    waste_pct: int | None
    token_pct: int | None = None
    requests_pct: int | None = None
    tasks_pct: int | None = None
    issues_pct: int | None = None

    def has_negative_signal(self) -> bool:
        """True when the template is evidencing a materially worse operating state."""
        if self.cost_pct is not None and self.cost_pct > 0:
            return True
        if self.waste_pct is not None and self.waste_pct > 0:
            return True
        if self.tasks_pct is not None and self.tasks_pct < 0:
            return True
        if self.issues_pct is not None and self.issues_pct < 0:
            return True
        return False

    def has_strict_outcome_improvement(self) -> bool:
        """True only when actual output/outcome evidence is strictly positive."""
        outcome_values = [self.tasks_pct, self.issues_pct]
        if not any(v is not None for v in outcome_values):
            return False
        if any(v is not None and v < 0 for v in outcome_values):
            return False
        return any(v is not None and v > 0 for v in outcome_values)

    def allows_positive_claim(self) -> bool:
        """Return True only when positive efficiency is auditable.

        Token/request growth alone never authorizes efficiency language. The
        evidence must show cost and waste did not rise, and at least one
        task/issue outcome metric improved strictly.
        """
        if self.cost_pct is None or self.cost_pct > 0:
            return False
        if self.waste_pct is not None and self.waste_pct > 0:
            return False
        if not self.has_strict_outcome_improvement():
            return False
        return True

    def top_counter_signal(self) -> str:
        """Return the most material counter-signal for neutral fallback text."""
        signals: list[tuple[int, str]] = []
        if self.waste_pct is not None and self.waste_pct > 0:
            signals.append((self.waste_pct, "浪费上升"))
        if self.cost_pct is not None and self.cost_pct > 0:
            signals.append((self.cost_pct, "成本上升"))
        if self.tasks_pct is not None and self.tasks_pct < 0:
            signals.append((abs(self.tasks_pct), "任务下降"))
        if self.issues_pct is not None and self.issues_pct < 0:
            signals.append((abs(self.issues_pct), "问题积压"))
        if signals:
            signals.sort(reverse=True)
            return signals[0][1]
        return "数据不足以判断"


def extract_efficiency_evidence(template_md: str) -> EfficiencyEvidence:
    """Parse trend percentages from the template to build auditable evidence."""
    cost_pct: int | None = None
    waste_pct: int | None = None
    token_pct: int | None = None
    requests_pct: int | None = None
    tasks_pct: int | None = None
    issues_pct: int | None = None
    for line in template_md.splitlines():
        m = _TREND_PCT_RE.match(line)
        if m:
            label, pct_str = m.group(1), m.group(2)
            pct = int(pct_str)
            if label in _COST_LABELS:
                cost_pct = pct
            elif label in _WASTE_LABELS:
                waste_pct = pct
            elif label == "Token":
                token_pct = pct
            elif label == "请求数":
                requests_pct = pct
            elif label in {"完成任务", "tasks"}:
                tasks_pct = pct
            elif label in {"issues", "已完成 issue", "完成 issue", "完成 issue(近似)"}:
                issues_pct = pct
    return EfficiencyEvidence(
        cost_pct=cost_pct,
        waste_pct=waste_pct,
        token_pct=token_pct,
        requests_pct=requests_pct,
        tasks_pct=tasks_pct,
        issues_pct=issues_pct,
    )


# Closed policy: reject explicit efficiency-positive wording under mixed/insufficient
# evidence and keep neutral/uncertain wording only when the counter-signal is still
# present.
_POSITIVE_EFFICIENCY_RE = re.compile(
    r"(?:效率|效能|投入产出|产出|用得更|更高效|更省|节省|省下|生产力).{0,12}(?:提升|提高|改善|优化|好转|增强|更好|更高|增效|进步|上升|增长|增幅|升高|回升|变好|更高效了)"
    r"|(?:efficiency|productivity|throughput).{0,10}(?:improv|increas|better|optim|gain|rise|grow|boost)"
    r"|(?:效率更高|效率上升|效率增长|效率回升|效率变好|效能提升|投入产出更好|整体向好|整体改善|整体优化|现在更高效了|生产力提升)",
    re.IGNORECASE,
)

_NEGATIVE_EFFICIENCY_RE = re.compile(
    r"(?:效率|效能|投入产出|产出|生产力).{0,12}(?:下降|降低|恶化|变差|回落|减弱|走低|明显下降|明显降低)"
    r"|(?:efficiency|productivity|throughput).{0,10}(?:drop|declin|worsen|decreas|fall)"
    r"|(?:效率明显下降|效率下降|效率变差|生产力下降)",
    re.IGNORECASE,
)

_MATERIAL_COUNTER_SIGNAL_RE = re.compile(
    r"(?:成本上升|成本增加|浪费上升|浪费增加|任务下降|问题积压|问题增加|开销上升|花费上升)",
    re.IGNORECASE,
)

_COUNTER_SIGNAL_RE = re.compile(
    r"(?:浪费|成本|任务|问题|需关注|谨慎|仍需|波动|不确定|风险|待观察|反向|上升|下降|压缩)",
    re.IGNORECASE,
)

_UNCERTAINTY_RE = re.compile(
    r"(?:需关注|谨慎|仍需|待观察|不确定|可能|待确认|有待|需留意|整体平稳|整体保持活跃|活动明显增加)",
    re.IGNORECASE,
)


def _metric_direction_matches(tldr: str, evidence: EfficiencyEvidence) -> bool:
    """True when a fact-style metric direction matches the extracted evidence."""
    if evidence.cost_pct is not None:
        if re.search(r"(?:成本|开销|花费).{0,8}(?:上升|增加|上调|上涨)", tldr, re.IGNORECASE):
            return evidence.cost_pct > 0
        if re.search(r"(?:成本|开销|花费).{0,8}(?:下降|降低|减少|回落)", tldr, re.IGNORECASE):
            return evidence.cost_pct < 0
    if evidence.waste_pct is not None:
        if re.search(r"(?:浪费).{0,8}(?:上升|增加|上涨|增多)", tldr, re.IGNORECASE):
            return evidence.waste_pct > 0
        if re.search(r"(?:浪费).{0,8}(?:下降|降低|减少|回落)", tldr, re.IGNORECASE):
            return evidence.waste_pct < 0
    if evidence.tasks_pct is not None:
        if re.search(r"(?:任务|产出).{0,8}(?:下降|减少|回落|减弱)", tldr, re.IGNORECASE):
            return evidence.tasks_pct < 0
        if re.search(r"(?:任务|产出).{0,8}(?:上升|增加|增长|提升)", tldr, re.IGNORECASE):
            return evidence.tasks_pct > 0
    if evidence.issues_pct is not None:
        if re.search(r"(?:问题|积压).{0,8}(?:增加|上升|增多|积压)", tldr, re.IGNORECASE):
            return evidence.issues_pct > 0
        if re.search(r"(?:问题|积压).{0,8}(?:下降|降低|减少|缓解)", tldr, re.IGNORECASE):
            return evidence.issues_pct < 0
    if evidence.requests_pct is not None:
        if re.search(r"(?:请求|请求量).{0,8}(?:上升|增加|增长|上涨|增多)", tldr, re.IGNORECASE):
            return evidence.requests_pct > 0
        if re.search(r"(?:请求|请求量).{0,8}(?:下降|降低|减少|回落)", tldr, re.IGNORECASE):
            return evidence.requests_pct < 0
    if evidence.token_pct is not None:
        if re.search(r"(?:Token|token).{0,8}(?:上升|增加|增长|上涨|增多)", tldr, re.IGNORECASE):
            return evidence.token_pct > 0
        if re.search(r"(?:Token|token).{0,8}(?:下降|降低|减少|回落)", tldr, re.IGNORECASE):
            return evidence.token_pct < 0
    return False


def _named_adverse_signal_matches(tldr: str, evidence: EfficiencyEvidence) -> bool:
    """Require a named adverse metric and an adverse direction to justify a neutral claim."""
    if evidence.cost_pct is not None and evidence.cost_pct > 0 and re.search(r"(?:成本|开销|花费).{0,8}(?:上升|增加|上调|上涨)", tldr, re.IGNORECASE):
        return True
    if evidence.waste_pct is not None and evidence.waste_pct > 0 and re.search(r"(?:浪费).{0,8}(?:上升|增加|上涨|增多)", tldr, re.IGNORECASE):
        return True
    if evidence.tasks_pct is not None and evidence.tasks_pct < 0 and re.search(r"(?:任务|产出).{0,8}(?:下降|减少|减|回落)", tldr, re.IGNORECASE):
        return True
    if evidence.issues_pct is not None and evidence.issues_pct > 0 and re.search(r"(?:问题|积压).{0,8}(?:增加|上升|积压|增多)", tldr, re.IGNORECASE):
        return True
    return False


def _efficiency_assertion_kind(tldr: str) -> str | None:
    """Return 'positive', 'negative', or None for the claim direction."""
    if _POSITIVE_EFFICIENCY_RE.search(tldr):
        return "positive"
    if _NEGATIVE_EFFICIENCY_RE.search(tldr):
        return "negative"
    return None


def validate_efficiency_claim(tldr: str, evidence: EfficiencyEvidence) -> bool:
    """Return True if the TL;DR is consistent with the evidence.

    Positive efficiency claims are only allowed when the template shows strict
    outcome improvement and no adverse cost/waste signal. Mixed or insufficient
    evidence must fail closed: positive or unsupported negative wording is rejected,
    and neutral/fact-style wording is accepted only with a real metric-direction
    match or an explicit material counter-signal.
    """
    if not tldr or not tldr.strip():
        return False
    if re.search(r"\d|[$%]", tldr):
        return False

    assertion_kind = _efficiency_assertion_kind(tldr)
    if evidence.allows_positive_claim():
        if assertion_kind == "negative":
            return False
        if assertion_kind == "positive":
            return True
        if _metric_direction_matches(tldr, evidence):
            return True
        return True

    if assertion_kind == "positive":
        return False
    if assertion_kind == "negative":
        return False

    if _metric_direction_matches(tldr, evidence):
        return True
    if _named_adverse_signal_matches(tldr, evidence):
        return True
    if _COUNTER_SIGNAL_RE.search(tldr) or _UNCERTAINTY_RE.search(tldr):
        return _named_adverse_signal_matches(tldr, evidence) or _metric_direction_matches(tldr, evidence)
    return False


def neutral_fallback_tldr(evidence: EfficiencyEvidence) -> str:
    """Deterministic neutral TL;DR when the LLM's claim is rejected."""
    counter = evidence.top_counter_signal()
    if counter == "数据不足以判断":
        return "整体趋势需观察，数据不足以判断效率变化"
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
    "额外约束：模板中成本或浪费上升时，点评绝对不能说效率提升/效率上升/效率增长/改善/优化/好转。"
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


def _is_cjk(ch: str) -> bool:
    """True if *ch* is a CJK ideograph (safe to cut after)."""
    cp = ord(ch)
    return (0x4E00 <= cp <= 0x9FFF      # CJK Unified Ideographs
            or 0x3400 <= cp <= 0x4DBF   # Extension A
            or 0xF900 <= cp <= 0xFAFF   # Compatibility Ideographs
            or 0x20000 <= cp <= 0x2A6DF)  # Extension B


# Characters that define valid word-boundary cut positions.
_BREAK_PUNCT = frozenset(":/;,，；：、)）】」—")
_BREAK_WS = frozenset(" \t\n")


def _find_last_boundary(text: str, limit: int) -> int:
    """Return the last valid cut position k in [1, limit] or -1.

    text[:k] is the kept prefix.  A boundary is: right before whitespace,
    right after punctuation, or right after a CJK ideograph.
    """
    candidate = -1
    scan_end = min(limit + 1, len(text))
    for i in range(scan_end):
        if text[i] in _BREAK_WS:
            candidate = i
        elif i > 0 and text[i - 1] in _BREAK_PUNCT:
            candidate = i
        elif i > 0 and _is_cjk(text[i - 1]):
            candidate = i
    return candidate


def _find_first_boundary(text: str, start: int) -> int:
    """Return the first valid resume position k >= start, or -1.

    text[k:] is the kept suffix.  Skips past whitespace/punctuation to
    land on the start of a token; for CJK the character itself is a valid
    resume point.
    """
    for i in range(max(start, 0), len(text)):
        if text[i] in _BREAK_WS:
            return i + 1
        if text[i] in _BREAK_PUNCT:
            return i + 1
        if _is_cjk(text[i]):
            return i
    return -1


_SUFFIX = " …"       # 2 chars — appended when head-only
_SEPARATOR = " … "   # 3 chars — joins head and tail
_OMISSION = "… [oversized token omitted]"


def truncate(text: str, n: int) -> str:
    """Boundary-aware truncation with head + tail retention.

    Strategy (in priority order):
    1. **Head + tail**: keep the problem-object prefix *and* the actionable
       cue at the end, joined by ' … '.  Head gets ~60 % of the budget,
       tail gets ~40 %.  Both cuts land on a word boundary.
    2. **Head-only**: when no clean tail boundary exists but the head
       boundary retains >= 60 % of the budget.
    3. **Explicit omission**: when no boundary exists at all (indivisible
       token) or the only boundary is too early (< 60 % retention), emit an
       omission marker without copying a partial token.  If a complete prefix
       exists, retain that prefix before the marker.

    Word boundaries: spaces, common punctuation (:/;,)…), and CJK
    ideographs (individually addressable — any inter-CJK position is valid).
    ASCII identifiers are never split mid-word when a boundary exists.
    """
    if n <= 0:
        return ""
    if len(text) <= n:
        return text
    max_body = n - len(_SUFFIX)          # max text chars for head-only path
    if max_body <= 0:
        return "…"

    # --- 1. head + tail ---------------------------------------------------
    if n >= 10:
        avail = n - len(_SEPARATOR)      # chars available for head + tail
        head_budget = avail * 3 // 5     # ~60 % for head
        tail_budget = avail - head_budget

        hb = _find_last_boundary(text, head_budget)
        if hb > 0:
            head = text[:hb].rstrip()
            tail_start = max(len(text) - tail_budget, hb)
            tb = _find_first_boundary(text, tail_start)
            if 0 < tb < len(text):
                tail = text[tb:]
                result = head + _SEPARATOR + tail
                if len(result) <= n:
                    return result

    # --- 2. head-only (good retention) ------------------------------------
    hb = _find_last_boundary(text, max_body)
    if hb > 0 and hb >= max_body * 6 // 10:
        return text[:hb].rstrip() + _SUFFIX

    # --- 3. explicit omission (indivisible / early boundary) --------------
    # Never hard-cut a boundary-free ASCII identifier: a partial identifier
    # is misleading, while an explicit omission is honest and retry-safe.
    if hb > 0:
        result = text[:hb].rstrip() + " " + _OMISSION
        if len(result) <= n:
            return result
    if len(_OMISSION) <= n:
        return _OMISSION
    return "…"


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
    if re.search(r"\d|[$%]", slots.tldr):
        return template_md
    evidence = extract_efficiency_evidence(template_md)
    if not validate_efficiency_claim(slots.tldr, evidence):
        slots = PolishSlots(
            tldr=neutral_fallback_tldr(evidence),
            todos=slots.todos,
        )
    return apply_slots(template_md, slots)
