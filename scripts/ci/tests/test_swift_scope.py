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


def test_out_of_range_lines_are_ignored():
    assert attachments_for_lines(PR171_SOURCE, [0, -3, 100_000]) == ()


@pytest.mark.parametrize("line", [PR171_PADDING_LINE, PR171_BODY_PADDING_LINE])
def test_reported_line_numbers_are_one_based_and_echo_source(line):
    item = _only(PR171_SOURCE, line)
    assert item.line == line
    assert item.modifier == PR171_SOURCE.splitlines()[line - 1].strip()
