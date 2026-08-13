#!/usr/bin/env python3
"""Deterministic coverage for the review gate's exact-HEAD context builder.

Covers the parts that decide what the reviewer actually sees: which added lines
count as modifier candidates, what the receiver table asserts, that every cap is
announced rather than silently applied, and that the untrusted-data framing
survives into the emitted block.
"""

from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from review_context import (  # noqa: E402
    FileEvidence,
    added_line_numbers,
    evidence_for_file,
    render,
)
from test_swift_scope import PR171_PADDING_LINE, PR171_SOURCE  # noqa: E402

PATH = "Packages/AIDashUI/Sources/AIDashUI/CardView/BarListCardView.swift"

# The PR #171 hunk shape as a unified diff: the modifier is added right after
# the inner closure's `}` and before the next computed property.
PR171_DIFF = f"""\
diff --git a/{PATH} b/{PATH}
index bbc8e29..2fb40be 100644
--- a/{PATH}
+++ b/{PATH}
@@ -24,6 +24,10 @@ private struct BarListRow: View {{
                 .font(BarListCardView.recipe.secondary)
         }}
+        // Only the LABEL LINE is inset: the value read-out is what the star
+        // would collide with. The bar below keeps the full track width.
+        .padding(.trailing, trailingInset)
     }}

     private var bar: some View {{
"""


def _stub_git(monkeypatch, source):
    """Point the context builder's git reader at in-memory source."""
    import review_context

    monkeypatch.setattr(
        review_context, "run_git", lambda args: source, raising=True
    )


def test_added_line_numbers_tracks_head_side_positions():
    numbers = added_line_numbers(PR171_DIFF, PATH)
    # Hunk starts at HEAD line 24; two context lines precede the three additions.
    assert numbers == (26, 27, 28)


def test_added_line_numbers_ignores_other_files():
    other = PR171_DIFF.replace(PATH, "Packages/AIDashUI/Sources/AIDashUI/Other.swift")
    assert added_line_numbers(other, PATH) == ()


def test_added_line_numbers_handles_multiple_hunks():
    diff = f"""\
diff --git a/{PATH} b/{PATH}
--- a/{PATH}
+++ b/{PATH}
@@ -1,2 +1,3 @@
 context
+added_a
 context
@@ -40,2 +41,3 @@
 context
+added_b
 context
"""
    assert added_line_numbers(diff, PATH) == (2, 42)


def test_pr171_evidence_names_the_inner_hstack_and_quotes_its_declaration(monkeypatch):
    _stub_git(monkeypatch, PR171_SOURCE)

    item = evidence_for_file(
        path=PATH,
        head_sha="41a793e",
        diff_text=_diff_marking(PR171_PADDING_LINE),
        max_file_bytes=400_000,
        max_excerpt_bytes=20_000,
    )
    assert item is not None
    table = "\n".join(item.table_rows)

    assert "attaches to `HStack`" in table
    assert "private var labelLine" in table
    # The false blocker's claim must not be expressible from this evidence.
    assert "VStack" not in table

    assert len(item.excerpts) == 1
    declaration, start, end, text = item.excerpts[0]
    assert declaration == "private var labelLine"
    assert start < PR171_PADDING_LINE < end
    assert ".padding(.trailing, trailingInset)" in text


def test_non_modifier_additions_produce_no_evidence(monkeypatch):
    _stub_git(monkeypatch, PR171_SOURCE)
    # Line 8 is `bar` — a plain body line, not a modifier.
    item = evidence_for_file(
        path=PATH, head_sha="deadbee", diff_text=_diff_marking(8),
        max_file_bytes=400_000, max_excerpt_bytes=20_000,
    )
    assert item is None


def test_file_missing_at_head_yields_no_evidence(monkeypatch):
    import review_context

    monkeypatch.setattr(review_context, "run_git", lambda args: None, raising=True)
    item = evidence_for_file(
        path=PATH, head_sha="deadbee", diff_text=PR171_DIFF,
        max_file_bytes=400_000, max_excerpt_bytes=20_000,
    )
    assert item is None


def test_oversized_file_is_skipped_and_says_so(monkeypatch):
    _stub_git(monkeypatch, PR171_SOURCE)
    item = evidence_for_file(
        path=PATH, head_sha="deadbee", diff_text=_diff_marking(PR171_PADDING_LINE),
        max_file_bytes=10, max_excerpt_bytes=20_000,
    )
    assert item is not None
    assert item.table_rows == ()
    assert item.excerpts == ()
    assert "10-byte cap" in item.skipped


def test_oversized_excerpt_is_dropped_and_announced(monkeypatch):
    _stub_git(monkeypatch, PR171_SOURCE)
    item = evidence_for_file(
        path=PATH, head_sha="deadbee", diff_text=_diff_marking(PR171_PADDING_LINE),
        max_file_bytes=400_000, max_excerpt_bytes=10,
    )
    assert item is not None
    assert item.table_rows            # the receiver table still resolves
    assert item.excerpts == ()
    assert "exceeded the 10-byte cap" in item.skipped


def test_render_states_that_hunk_boundaries_are_not_scope_boundaries():
    body = render(
        [FileEvidence(path=PATH, table_rows=("  line 28: x",), excerpts=(), skipped="")],
        max_total_bytes=120_000,
    )
    assert "exact-HEAD" in body
    assert "hunk 边界不是作用域边界" in body
    # The block must keep flagging its own content as untrusted.
    assert "不可信" in body
    assert "unresolved" in body


def test_render_of_nothing_is_empty():
    assert render([], max_total_bytes=120_000) == ""


def test_render_truncation_is_explicit():
    rows = tuple(f"  line {n}: `.padding({n})` attaches to `HStack`" for n in range(400))
    body = render(
        [FileEvidence(path=PATH, table_rows=rows, excerpts=(), skipped="")],
        max_total_bytes=800,
    )
    assert len(body.encode("utf-8")) <= 800 + 200      # cap + the notice itself
    assert "[截断]" in body
    assert "不要断言 modifier 归属" in body


def _diff_marking(head_line: int) -> str:
    """A minimal diff that marks exactly `head_line` as added on the HEAD side."""
    return (
        f"diff --git a/{PATH} b/{PATH}\n"
        f"--- a/{PATH}\n"
        f"+++ b/{PATH}\n"
        f"@@ -{head_line},0 +{head_line},1 @@\n"
        f"+placeholder\n"
    )
