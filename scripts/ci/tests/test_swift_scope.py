#!/usr/bin/env python3
"""Deterministic coverage for the review gate's Swift scope resolver.

The anchor case is PR #171 (MY-1402): a `.padding(.trailing, trailingInset)`
added after an inner `HStack` closure and before the next computed property was
reported by BOTH review models as attached to the outer `body` VStack. The
first test below reproduces that exact hunk shape and pins the correct answer.

Run by CI (`review-gate (pytest)`) and by `scripts/hooks/pre-push` whenever the
push touches `scripts/ci/**`.
"""

from __future__ import annotations

import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from swift_scope import (  # noqa: E402
    attachments_for_lines,
    blank_source,
    declaration_slice,
    is_balanced,
    is_modifier_line,
)

# The PR #171 shape, reduced to its essentials: an outer `body` VStack, an
# inner `labelLine` HStack, and a modifier added after the inner closure's `}`
# — the ambiguity that produced the false blocker.
PR171_SOURCE = '''\
private struct BarListRow: View {
    @Environment(\\.theme) private var theme
    let item: BarListPayload.Item
    let trailingInset: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s4) {
            labelLine
            bar
        }
        .padding(.vertical, AIDashSpace.s2)
        .accessibilityElement(children: .combine)
    }

    private var labelLine: some View {
        HStack(spacing: AIDashSpace.s8) {
            Text(item.label)
                .font(BarListCardView.recipe.primary)
                .lineLimit(1)
            Spacer(minLength: AIDashSpace.s8)
            Text(valueText)
                .font(BarListCardView.recipe.secondary)
        }
        // Only the LABEL LINE is inset: the value read-out is what the star
        // would collide with. The bar below keeps the full track width.
        .padding(.trailing, trailingInset)
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.neutrals.inner)
            }
        }
        .frame(height: Self.barHeight)
    }
}
'''

PR171_PADDING_LINE = 26          # `.padding(.trailing, trailingInset)`
PR171_BODY_PADDING_LINE = 11     # `.padding(.vertical, AIDashSpace.s2)`


def test_the_fixture_constants_point_at_the_lines_they_claim():
    """Guards the rest of the file: a shifted fixture must fail here, loudly."""
    lines = PR171_SOURCE.splitlines()
    assert lines[PR171_PADDING_LINE - 1].strip() == ".padding(.trailing, trailingInset)"
    assert lines[PR171_BODY_PADDING_LINE - 1].strip() == ".padding(.vertical, AIDashSpace.s2)"


def _only(source: str, line: int):
    found = attachments_for_lines(source, [line])
    assert len(found) == 1, f"expected one attachment for line {line}, got {found}"
    return found[0]


def test_pr171_padding_attaches_to_inner_hstack_not_outer_body():
    """The regression under test: receiver is `labelLine`'s HStack, not `body`."""
    item = _only(PR171_SOURCE, PR171_PADDING_LINE)

    assert item.resolved
    assert item.receiver == "HStack"
    assert item.declaration == "private var labelLine"
    # The false blocker claimed `body` / VStack. Pin both negatives explicitly:
    # this test exists to fail if that misattribution ever returns.
    assert item.receiver != "VStack"
    assert "body" not in item.declaration


def test_pr171_body_padding_still_attaches_to_the_outer_vstack():
    """The genuine outer-body case must not be mislabelled in the other direction."""
    item = _only(PR171_SOURCE, PR171_BODY_PADDING_LINE)

    assert item.resolved
    assert item.receiver == "VStack"
    assert item.declaration == "var body"


def test_pr171_excerpt_covers_the_whole_enclosing_declaration():
    span = declaration_slice(PR171_SOURCE, PR171_PADDING_LINE)
    assert span is not None
    start, end = span

    excerpt = "\n".join(PR171_SOURCE.splitlines()[start - 1:end])
    assert excerpt.lstrip().startswith("private var labelLine")
    assert "HStack(spacing: AIDashSpace.s8)" in excerpt
    assert ".padding(.trailing, trailingInset)" in excerpt
    # A scope excerpt that leaked the sibling would recreate the ambiguity.
    assert "GeometryReader" not in excerpt


def test_modifier_chain_walks_to_the_root_construct():
    """Mid-chain modifiers resolve to the construct, not the modifier above."""
    source = '''\
struct Row: View {
    var body: some View {
        Text("hi")
            .font(.body)
            .foregroundStyle(.red)
    }
}
'''
    item = _only(source, 5)      # `.foregroundStyle(.red)`
    assert item.resolved
    assert item.receiver == "Text"
    assert item.declaration == "var body"


def test_modifier_after_trailing_closure_call_resolves_to_that_call():
    source = '''\
struct Grid: View {
    var body: some View {
        ForEach(items) { item in
            Text(item.label)
        }
        .padding(.horizontal, 8)
    }
}
'''
    item = _only(source, 6)
    assert item.resolved
    assert item.receiver == "ForEach"


def test_modifier_after_a_multiline_argument_list_resolves_to_the_call():
    source = '''\
struct Card: View {
    var body: some View {
        Label(
            title: "x",
            icon: "star"
        )
        .padding(4)
    }
}
'''
    item = _only(source, 7)
    assert item.resolved
    assert item.receiver == "Label"


def test_comment_braces_do_not_shift_attachment():
    """A `}` inside a comment must not be matched as real structure."""
    source = '''\
struct Row: View {
    var body: some View {
        HStack {
            // closing } inside a comment, and /* a { block one */
            Text("hi")
        }
        .padding(2)
    }
}
'''
    item = _only(source, 7)
    assert item.resolved
    assert item.receiver == "HStack"


def test_string_literal_braces_do_not_shift_attachment():
    source = '''\
struct Row: View {
    var body: some View {
        VStack {
            Text("a } brace { in a string")
        }
        .padding(2)
    }
}
'''
    item = _only(source, 6)
    assert item.resolved
    assert item.receiver == "VStack"


def test_multiline_string_braces_do_not_shift_attachment():
    source = '''\
struct Row: View {
    var body: some View {
        VStack {
            Text("""
            a } brace { inside a multiline literal
            """)
        }
        .padding(2)
    }
}
'''
    item = _only(source, 8)
    assert item.resolved
    assert item.receiver == "VStack"


def test_nested_block_comment_is_blanked_fully():
    lines = ["let a = 1 /* outer /* inner */ still */ + 2"]
    blanked = blank_source(lines)
    assert "outer" not in blanked[0]
    assert "inner" not in blanked[0]
    assert blanked[0].startswith("let a = 1 ")
    assert blanked[0].rstrip().endswith("+ 2")
    assert len(blanked[0]) == len(lines[0])


def test_unbalanced_source_reports_unresolved_rather_than_guessing():
    """Fail-closed on the evidence side: no confident answer from a bad lex."""
    source = '''\
struct Row: View {
    var body: some View {
        VStack {
            Text("hi")
        .padding(2)
    }
}
'''
    assert not is_balanced(blank_source(source.splitlines()))
    item = _only(source, 5)
    assert not item.resolved
    assert item.receiver == ""
    assert item.receiver_line == 0


def test_non_modifier_lines_are_not_reported():
    found = attachments_for_lines(PR171_SOURCE, [7, 8, 9])
    assert found == ()


def test_collection_literal_elements_are_not_treated_as_modifiers():
    """`.init(...),` inside an array literal is an element, not a modifier.

    Resolving a "receiver" for these produced pure noise in the evidence table
    — and noise is what makes a reviewer stop reading the evidence.
    """
    source = '''\
#Preview("bar list") {
    BarListCardView(
        payload: BarListPayload(items: [
            .init(label: "runtime-offline", value: 39, semantic: "warning"),
            .init(label: "codex-init-fail", value: 21),
        ])
    )
}
'''
    assert attachments_for_lines(source, [4, 5]) == ()
    assert not is_modifier_line('        .init(label: "a", value: 1),')
    # A genuine modifier with no trailing comma still resolves.
    assert is_modifier_line("        .padding(.trailing, trailingInset)")


def test_enum_case_shorthand_in_an_argument_list_is_not_a_modifier():
    assert not is_modifier_line("            .leading,")
    assert not is_modifier_line("    .init(a: 1),")


# --- Blocker 1: standalone enum / member expressions --------------------------
#
# A leading-dot line with no trailing comma was accepted as a modifier, so a
# bare `.leading` or `.red` sitting on its own line as an ARGUMENT VALUE came
# back `resolved=True` with an invented receiver. `resolved` is what the prompt
# treats as citable, so that is false evidence, not merely noise.

def test_standalone_enum_argument_value_is_not_attachment_evidence():
    source = '''\
struct Row: View {
    var body: some View {
        VStack(
            alignment:
                .leading
        ) {
            Text("hi")
        }
    }
}
'''
    # Omitted entirely — `unresolved` would claim "a modifier we could not
    # place", and this is not a modifier at all.
    assert attachments_for_lines(source, [5]) == ()


def test_bare_member_expression_as_argument_is_not_attachment_evidence():
    source = '''\
struct Row: View {
    var body: some View {
        Text("hi")
            .foregroundStyle(
                .red
            )
    }
}
'''
    assert attachments_for_lines(source, [5]) == ()


def test_uninvoked_leading_dot_lines_are_rejected_textually():
    """A modifier is applied: the member is followed by a call or a closure."""
    assert not is_modifier_line(".leading")
    assert not is_modifier_line(".red")
    assert not is_modifier_line("        .infinity")
    assert is_modifier_line(".padding(8)")
    assert is_modifier_line(".frame(")
    assert is_modifier_line(".chartXAxis { RelationshipChartAxis.gridless() }")


def test_invoked_argument_value_is_still_rejected_structurally():
    """`.value(...)` after `PointMark(` is an argument, not a modifier.

    It is invoked and comma-free, so the textual test alone would accept it.
    What rules it out is the line above: an argument hangs off a line that
    OPENS a list, a chain hangs off one that ENDS an expression.
    """
    source = '''\
struct Chart2: View {
    var body: some View {
        Chart(points) { point in
            PointMark(
                x: .value("x", point.x)
            )
        }
    }
}
'''
    assert attachments_for_lines(source, [5]) == ()


# --- Blocker 2: multiline declaration heads -----------------------------------
#
# A declaration was recognized only when its keyword shared a line with `{`.
# For a multiline parameter list the walk continued outward and reported the
# enclosing type — while still returning `resolved=True`, so a reviewer would
# read a confidently-wrong scope.

def test_multiline_function_head_is_attributed_to_the_function():
    source = '''\
struct Card: View {
    private func kpiCell(
        _ item: KPIItem,
        width: CGFloat
    ) -> some View {
        HStack {
            Text(item.label)
        }
        .padding(.trailing, 8)
    }
}
'''
    item = _only(source, 9)
    assert item.resolved
    assert item.receiver == "HStack"
    assert item.declaration == "private func kpiCell"
    assert item.declaration_line == 2
    # The pre-fix behaviour: attributed to the enclosing struct, resolved=True.
    assert item.declaration != "struct Card"


def test_multiline_initializer_head_is_attributed_to_the_initializer():
    source = '''\
struct Card: View {
    init(
        payload: Payload,
        size: CardSize
    ) {
        VStack {
            Text("x")
        }
        .padding(4)
    }
}
'''
    item = _only(source, 9)
    assert item.resolved
    assert item.declaration == "init"
    assert item.declaration_line == 2


def test_multiline_head_scan_does_not_adopt_a_preceding_statement():
    """An ordinary closure `{` must not adopt the statement above it.

    The head scan follows PAREN CONTINUATION only — an unmatched `)` before the
    `{`, matched back to its opener. A looser "look at the line above" rule
    would read `let items = compute()` as the declaration owning
    `return ForEach(items) {`, which is how the first attempt at this fix
    regressed MetricCardView to `let viz`.
    """
    source = '''\
struct Card: View {
    var body: some View {
        let items = compute()
        return ForEach(items) { item in
            Text(item.label)
        }
        .padding(4)
    }
}
'''
    item = _only(source, 7)
    assert item.resolved
    assert item.receiver == "ForEach"
    # `var body` — reached by the outward walk, not by adopting line 3.
    assert item.declaration == "var body"
    assert item.declaration_line == 2


def test_declaration_with_body_locals_still_reports_the_declaration():
    """Locals between the head and the modifier must not become the scope.

    This is the MetricCardView shape from the real PR #171 diff: `kpiCell`
    declares two `let`s, then returns a view. The evidence must say
    `private func kpiCell`, not `let viz`.
    """
    source = '''\
struct MetricCard: View {
    private func kpiCell(_ item: MetricPayload.Item) -> some View {
        let recipe = AIDashTypography.detail(for: .metric)
        let viz = vizKind(item)
        return VStack(alignment: .leading, spacing: AIDashSpace.s12) {
            Text(item.label)
                .font(recipe.secondary)
        }
        .padding(4)
    }
}
'''
    item = _only(source, 9)
    assert item.resolved
    assert item.receiver == "VStack"
    assert item.declaration == "private func kpiCell"
    assert item.declaration_line == 2


def test_receiver_skips_leading_keywords():
    """`return Chart { … }` reports `Chart`, not `return`."""
    source = '''\
struct ScatterChart: View {
    private var scatterChart: some View {
        return Chart(points) { point in
            PointMark(x: .value("x", point.x), y: .value("y", point.y))
        }
        .chartLegend(.visible)
    }
}
'''
    item = _only(source, 6)
    assert item.resolved
    assert item.receiver == "Chart"
    assert item.declaration == "private var scatterChart"


def test_out_of_range_lines_are_ignored():
    assert attachments_for_lines(PR171_SOURCE, [0, -3, 100_000]) == ()


@pytest.mark.parametrize("line", [PR171_PADDING_LINE, PR171_BODY_PADDING_LINE])
def test_reported_line_numbers_are_one_based_and_echo_source(line):
    item = _only(PR171_SOURCE, line)
    assert item.line == line
    assert item.modifier == PR171_SOURCE.splitlines()[line - 1].strip()
