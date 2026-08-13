#!/usr/bin/env python3
"""Pure Swift scope analysis for the automated review gates.

Why this exists
---------------
A unified-diff hunk boundary is **not** a scope boundary. A `.modifier(...)`
line added right after an inner closure's `}` attaches to *that inner
construct*, not to the outer container two levels up — but a reviewer that
sees only the hunk cannot tell the two apart, because the hunk shows the `}`
without showing which `{` it closes.

That exact ambiguity produced a false high-severity blocker on PR #171: a
`.padding(.trailing, trailingInset)` added inside `private var labelLine` was
described as attached to `BarListRow.body`'s outer `VStack`. Both review
models made the same mistake from the same hunk.

These helpers resolve the receiver **deterministically from exact-HEAD
source**, so the reviewer is handed a computed fact instead of an inference.

Deliberately literal
--------------------
This is a lexical scanner (blank out comments and string literals, then match
braces over the blanked text), not a Swift parser. Anything it cannot resolve
with confidence is reported as *unresolved* rather than guessed — callers must
treat unresolved as "no modifier-scope evidence available", never as evidence.

Stdlib only, no side effects: every function takes text in and returns new
values out.
"""

from __future__ import annotations

import re
from typing import NamedTuple, Optional, Sequence, Tuple

# A line is a declaration head if it opens a scope and names one of these.
_DECL_RE = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"          # attributes: @ViewBuilder, @State…
    r"(?:(?:public|internal|private|fileprivate|open|package)\s+(?:\(set\)\s+)?)?"
    r"(?:static\s+|class\s+|final\s+|override\s+|mutating\s+|nonisolated\s+)*"
    r"(var|let|func|init|subscript|struct|class|enum|extension|protocol|actor)\b"
)

_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*")

# Keywords that can precede the construct a modifier applies to. Reporting
# `return` as the receiver of `.chartXAxis { … }` is useless to a reviewer;
# reporting `Chart` is the point.
_LEADING_KEYWORDS = frozenset({"return", "try", "await", "let", "var", "case"})

# `.padding(...)`, `.font(x)`, `.chartXAxis { … }` — a leading-dot member
# access is how every SwiftUI modifier is written.
_MODIFIER_RE = re.compile(r"^\.([A-Za-z_][A-Za-z0-9_]*)")

# A leading dot introduces plenty of things that are NOT modifiers:
#   · collection-literal elements — `.init(label: "a", value: 1),`
#   · enum-case shorthand as an argument value — `alignment:` / `.leading`
#   · standalone member expressions — `.red`
# Resolving a "receiver" for any of those is meaningless, and — worse — it comes
# back `resolved=True`, which the prompt treats as citable evidence. So the bar
# for calling a line a modifier is deliberately high, and everything that does
# not clear it is dropped rather than reported with a guess.
_COLLECTION_ELEMENT_RE = re.compile(r",\s*$")
_NON_MODIFIER_MEMBERS = frozenset({"init"})

# A modifier is APPLIED: the member name is followed by a call or a trailing
# closure. `.padding(8)`, `.frame(` (multiline call), `.chartXAxis { … }` all
# qualify; bare `.leading` and `.red` do not. Bare-property modifiers are
# vanishingly rare in SwiftUI (it is `.bold()`, not `.bold`), and the cost of
# missing one is no evidence — never wrong evidence.
_INVOCATION_RE = re.compile(r"^\.[A-Za-z_][A-Za-z0-9_]*\s*[({]")

# The last character of the line a modifier chains off. A chain continues an
# expression, so its predecessor ends in something that can END one. A line
# ending in `,` `:` `(` `[` `{` `=` opens an argument or element instead, which
# makes the leading-dot line below it a VALUE, not a modifier.
_EXPRESSION_END_RE = re.compile(r"[)\]}\"A-Za-z0-9_?!>]$")


def is_modifier_line(text: str) -> bool:
    """Whether `text` reads, on its own, as an applied view modifier.

    Purely textual — the structural half of the test lives in
    `_is_chain_continuation`, which needs the whole file. Callers that have the
    file should use both; `review_context` uses this as a cheap prefilter.
    """
    stripped = text.strip()
    match = _MODIFIER_RE.match(stripped)
    if not match:
        return False
    if match.group(1) in _NON_MODIFIER_MEMBERS:
        return False
    if not _INVOCATION_RE.match(stripped):
        return False
    # A trailing comma means this is one element among several, not a modifier
    # applied to the line above it.
    return not _COLLECTION_ELEMENT_RE.search(stripped)


def _is_chain_continuation(blanked: Sequence[str], index: int) -> bool:
    """Whether the leading-dot line at `index` continues an expression.

    `someCall(` / `.value("x", y)` is an ARGUMENT — invoked, comma-free, and
    still not a modifier. What separates it from a real chain is the line above:
    a chain hangs off something that ends an expression (`)`, `}`, `]`, an
    identifier), an argument hangs off something that opens a list.
    """
    previous = _previous_code_line(blanked, index)
    if previous is None:
        return False
    text = blanked[previous].rstrip()
    if not text:
        return False
    return bool(_EXPRESSION_END_RE.search(text))

# Walking a receiver chain is bounded: a pathological file must not hang CI.
_MAX_WALK_STEPS = 500

# A declaration head may span several lines (a multiline parameter list), but
# not many. Bounding the backwards scan keeps a malformed file from turning one
# lookup into a whole-file walk.
_MAX_DECL_HEAD_LINES = 40


class Attachment(NamedTuple):
    """Where one leading-dot modifier line actually attaches.

    `resolved` is False when the scanner could not establish ownership; every
    other field is then advisory only and MUST NOT be cited as evidence.
    """

    line: int                       # 1-based line of the modifier itself
    modifier: str                   # source text of the modifier line, stripped
    receiver: str                   # e.g. "HStack"; "" when unresolved
    receiver_line: int              # 1-based line the receiver opens on; 0 when unresolved
    declaration: str                # e.g. "private var labelLine"; "" when unknown
    declaration_line: int           # 1-based; 0 when unknown
    resolved: bool


def blank_source(lines: Sequence[str]) -> Tuple[str, ...]:
    '''Return `lines` with comments and string literals replaced by spaces.

    Column positions are preserved (same length per line) so brace matching can
    report exact coordinates back into the original text. Handles line comments,
    nested block comments, double-quoted strings with escapes, and Swift's
    triple-quoted multiline string literals.
    '''
    out: list[str] = []
    block_depth = 0
    in_multiline_string = False

    for raw in lines:
        buf = list(raw)
        n = len(raw)
        in_string = False
        i = 0
        while i < n:
            pair = raw[i:i + 2]
            triple = raw[i:i + 3]

            if in_multiline_string:
                if triple == '"""':
                    in_multiline_string = False
                    buf[i] = buf[i + 1] = buf[i + 2] = " "
                    i += 3
                    continue
                buf[i] = " "
                i += 1
                continue

            if block_depth:
                if pair == "*/":
                    block_depth -= 1
                    buf[i] = buf[i + 1] = " "
                    i += 2
                    continue
                if pair == "/*":            # Swift block comments nest.
                    block_depth += 1
                    buf[i] = buf[i + 1] = " "
                    i += 2
                    continue
                buf[i] = " "
                i += 1
                continue

            if in_string:
                if raw[i] == "\\":
                    buf[i] = " "
                    if i + 1 < n:
                        buf[i + 1] = " "
                    i += 2
                    continue
                if raw[i] == '"':
                    in_string = False
                buf[i] = " "
                i += 1
                continue

            if triple == '"""':
                in_multiline_string = True
                buf[i] = buf[i + 1] = buf[i + 2] = " "
                i += 3
                continue
            if raw[i] == '"':
                in_string = True
                buf[i] = " "
                i += 1
                continue
            if pair == "//":
                for j in range(i, n):
                    buf[j] = " "
                break
            if pair == "/*":
                block_depth += 1
                buf[i] = buf[i + 1] = " "
                i += 2
                continue
            i += 1

        out.append("".join(buf))

    return tuple(out)


def is_balanced(blanked: Sequence[str]) -> bool:
    """Whether brace matching over `blanked` can be trusted at all.

    A file whose braces do not net to zero means the scanner mis-lexed
    something (an unsupported raw-string form, say). Rather than emit a
    confidently wrong receiver, callers degrade the whole file to unresolved.
    """
    depth = 0
    for line in blanked:
        for ch in line:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth < 0:
                    return False
    return depth == 0


def _match_backwards(
    blanked: Sequence[str], line: int, col: int, opener: str, closer: str
) -> Optional[Tuple[int, int]]:
    """Find the opener matching the closer at (line, col), scanning backwards."""
    depth = 0
    row = line
    steps = 0
    while row >= 0 and steps < _MAX_WALK_STEPS:
        steps += 1
        text = blanked[row]
        start = col if row == line else len(text) - 1
        for c in range(start, -1, -1):
            ch = text[c]
            if ch == closer:
                depth += 1
            elif ch == opener:
                depth -= 1
                if depth == 0:
                    return (row, c)
        row -= 1
    return None


def _previous_code_line(blanked: Sequence[str], index: int) -> Optional[int]:
    """Nearest earlier line holding actual code (comments are already blanked)."""
    for row in range(index - 1, -1, -1):
        if blanked[row].strip():
            return row
    return None


def _leading_expression(text: str) -> str:
    """The construct a line introduces: `HStack(spacing: s8) {` → `HStack`.

    Leading keywords are stripped so `return Chart { … }` reports `Chart` — the
    thing the modifier actually applies to — rather than `return`.
    """
    stripped = text.strip()
    for _ in range(4):
        match = _IDENT_RE.match(stripped)
        if match and match.group(0) in _LEADING_KEYWORDS:
            stripped = stripped[match.end():].lstrip()
            continue
        break
    match = _IDENT_RE.match(stripped)
    if match:
        return match.group(0)
    return stripped[:40]


def enclosing_declaration(
    blanked: Sequence[str], raw: Sequence[str], index: int
) -> Optional[Tuple[int, str]]:
    """The declaration whose body encloses line `index` (0-based).

    Returns (0-based line of the declaration's FIRST line, display text), or
    None at file scope. Walks outward through anonymous scopes (closures, `if`
    blocks) until it reaches a scope opened by a declaration.
    """
    row, col = index, -1
    for _ in range(_MAX_WALK_STEPS):
        opener = _enclosing_open_brace(blanked, row, col)
        if opener is None:
            return None
        row, col = opener
        head = _declaration_head(blanked, raw, row)
        if head is not None:
            return head
    return None


def _declaration_head(
    blanked: Sequence[str], raw: Sequence[str], brace_row: int
) -> Optional[Tuple[int, str]]:
    """The declaration that opens the scope whose `{` sits on `brace_row`.

    A declaration's keyword is NOT always on the same line as its `{`:

        private func kpiCell(
            _ item: KPIItem,
            width: CGFloat
        ) -> some View {

    Matching only `brace_row` misses that, and the walk then continues outward
    and reports the enclosing `struct` — with `resolved=True`, so a reviewer
    would read a confidently-wrong scope.

    What ties `) -> some View {` back to its keyword is PAREN CONTINUATION: the
    line closes a parameter list opened above. So the scan follows that paren,
    and nothing else. A looser "just look at the line above" rule would adopt
    whatever statement happened to precede an ordinary closure — e.g. read
    `let viz = vizKind(item)` as the declaration owning `return VStack {`.
    """
    if _DECL_RE.match(raw[brace_row]):
        return (brace_row, _display_declaration(raw[brace_row]))

    # Text before the `{`: does it close more parens than it opens?
    text = blanked[brace_row]
    brace_col = text.find("{")
    if brace_col < 0:
        return None
    prefix = text[:brace_col]

    depth = 0
    close_col = -1
    for col, char in enumerate(prefix):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth < 0 and close_col < 0:
                close_col = col
    if close_col < 0:
        return None                      # no unmatched `)` — not a multiline head

    opener = _match_backwards(blanked, brace_row, close_col, "(", ")")
    if opener is None:
        return None
    head_row = opener[0]
    if brace_row - head_row > _MAX_DECL_HEAD_LINES:
        return None
    if _DECL_RE.match(raw[head_row]):
        return (head_row, _display_declaration(raw[head_row]))
    return None


def _enclosing_open_brace(
    blanked: Sequence[str], line: int, col: int
) -> Optional[Tuple[int, int]]:
    """The `{` that opens the scope containing position (line, col)."""
    depth = 0
    row = line
    steps = 0
    while row >= 0 and steps < _MAX_WALK_STEPS:
        steps += 1
        text = blanked[row]
        start = (col - 1) if (row == line and col >= 0) else len(text) - 1
        if row == line and col < 0:
            start = -1                      # start scanning from the line above
        for c in range(start, -1, -1):
            ch = text[c]
            if ch == "}":
                depth += 1
            elif ch == "{":
                if depth == 0:
                    return (row, c)
                depth -= 1
        row -= 1
        col = -2                            # subsequent rows scan in full
    return None


def _display_declaration(raw_line: str) -> str:
    """`    private var labelLine: some View {` → `private var labelLine`.

    Also trims the dangling `(` a multiline function head leaves behind, so the
    evidence row reads `private func kpiCell`, not `private func kpiCell(`.
    """
    text = raw_line.strip()
    for cut in ("{", "(", ":", "="):
        head = text.split(cut, 1)[0]
        if head != text:
            text = head
    return " ".join(text.split())


def modifier_attachment(
    raw: Sequence[str], blanked: Sequence[str], index: int
) -> Attachment:
    """Resolve what the leading-dot modifier on 0-based `index` attaches to."""
    text = raw[index].strip()
    unresolved = Attachment(
        line=index + 1, modifier=text, receiver="", receiver_line=0,
        declaration="", declaration_line=0, resolved=False,
    )
    if not is_modifier_line(text):
        return unresolved
    # Textually a modifier, but structurally an argument value — e.g. the
    # `.value("x", p.x)` on the line after `PointMark(`. Dropping it keeps a
    # non-modifier from being reported as `resolved` attachment evidence.
    if not _is_chain_continuation(blanked, index):
        return unresolved

    receiver = _receiver_line(blanked, index)
    if receiver is None:
        return unresolved

    decl = enclosing_declaration(blanked, raw, index)
    return Attachment(
        line=index + 1,
        modifier=text,
        receiver=_leading_expression(raw[receiver]),
        receiver_line=receiver + 1,
        declaration=decl[1] if decl else "",
        declaration_line=(decl[0] + 1) if decl else 0,
        resolved=True,
    )


def _receiver_line(blanked: Sequence[str], index: int) -> Optional[int]:
    """0-based line of the expression the modifier at `index` applies to.

    A modifier applies to whatever immediately precedes it. When that is a
    closing `}` or `)`, the receiver is the line that OPENED it — which is the
    whole point: the `}` above a modifier belongs to an inner construct far
    more often than to the enclosing body.
    """
    row = index
    for _ in range(_MAX_WALK_STEPS):
        previous = _previous_code_line(blanked, row)
        if previous is None:
            return None

        text = blanked[previous].rstrip()
        col = len(text) - 1
        last = text[col] if text else ""

        if last == "}":
            opened = _match_backwards(blanked, previous, col, "{", "}")
        elif last == ")":
            opened = _match_backwards(blanked, previous, col, "(", ")")
        else:
            opened = (previous, 0)

        if opened is None:
            return None

        # A receiver that is itself a modifier means we are mid-chain; keep
        # walking until the chain's root construct.
        if _MODIFIER_RE.match(blanked[opened[0]].strip()):
            row = opened[0]
            continue
        return opened[0]
    return None


def attachments_for_lines(
    source: str, line_numbers: Sequence[int]
) -> Tuple[Attachment, ...]:
    """Resolve every 1-based line in `line_numbers` that is a modifier line.

    Non-modifier lines are skipped. If the file does not lex cleanly, every
    modifier line comes back unresolved.
    """
    raw = source.splitlines()
    blanked = blank_source(raw)
    trustworthy = is_balanced(blanked)

    results: list[Attachment] = []
    for number in sorted(set(line_numbers)):
        index = number - 1
        if index < 0 or index >= len(raw):
            continue
        if not is_modifier_line(raw[index]):
            continue
        # Not a modifier at all (an argument value that merely starts with a
        # dot) — omit it entirely rather than emitting an `unresolved` row.
        # `unresolved` means "this IS a modifier we could not place"; using it
        # for non-modifiers would bury the real ones in noise.
        if trustworthy and not _is_chain_continuation(blanked, index):
            continue
        if not trustworthy:
            results.append(
                Attachment(
                    line=number, modifier=raw[index].strip(), receiver="",
                    receiver_line=0, declaration="", declaration_line=0,
                    resolved=False,
                )
            )
            continue
        results.append(modifier_attachment(raw, blanked, index))
    return tuple(results)


def declaration_slice(source: str, line_number: int) -> Optional[Tuple[int, int]]:
    """1-based inclusive line range of the declaration enclosing `line_number`.

    Used to give the reviewer a bounded but scope-complete excerpt of a file too
    large to include whole.
    """
    raw = source.splitlines()
    blanked = blank_source(raw)
    if not is_balanced(blanked):
        return None
    index = line_number - 1
    if index < 0 or index >= len(raw):
        return None

    decl = enclosing_declaration(blanked, raw, index)
    if decl is None:
        return None

    start = decl[0]
    open_col = blanked[start].find("{")
    if open_col < 0:
        return None
    end = _match_forwards(blanked, start, open_col)
    if end is None:
        return None
    return (start + 1, end + 1)


def _match_forwards(blanked: Sequence[str], line: int, col: int) -> Optional[int]:
    """Line holding the `}` that closes the `{` at (line, col)."""
    depth = 0
    steps = 0
    for row in range(line, len(blanked)):
        steps += 1
        if steps > _MAX_WALK_STEPS:
            return None
        text = blanked[row]
        start = col if row == line else 0
        for c in range(start, len(text)):
            if text[c] == "{":
                depth += 1
            elif text[c] == "}":
                depth -= 1
                if depth == 0:
                    return row
    return None
