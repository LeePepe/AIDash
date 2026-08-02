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


_SYSTEM = (
    "你是 AI 使用日报的文字润色助手。给你一份已经算好数字的日报模板。"
    "严格规则：绝对不要发明、改动、或复述任何数字/百分比/金额——数字全部由模板拥有。"
    "你只做两件事：(1) 写一句总体点评（简短、口语、不含任何数字）；"
    "(2) 把每条 TODO 的措辞改得更可执行（保留其中已有的数字原样，不加不减，不改优先级）。"
    "只返回严格 JSON：{\"tldr\": \"...\", \"todos\": [\"...\", ...]}，不要解释、不要代码块外的文字。"
)


def build_prompt(template_md: str) -> tuple[str, str]:
    """Return (system, user) prompts for the polish pass."""
    user = ("这是今天的日报模板，请按规则返回 JSON：\n\n" + template_md)
    return _SYSTEM, user


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
    """Run the LLM polish pass. Propagates LLMError for the caller to catch."""
    system, user = build_prompt(template_md)
    raw = client.complete(system, user)
    slots = parse_slots(raw)
    return apply_slots(template_md, slots)
