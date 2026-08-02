"""Golden/hermetic fixtures must freeze the seams the digest actually calls.

The recurring trap (tech-context.md 坑 ①): `_fetch_sources` calls
`fetch_combined_pr_trends`, but fixtures froze `fetch_ado_pr_trends` — a
sibling with the same shape and a very similar name. Nothing failed loudly.
The frozen-looking test quietly read this machine's live warehouse, so it
passed on a fresh clone and drifted on a machine with real data.

That is a *fixture completeness* bug, and it cannot be caught by the tests it
breaks — they look green. So catch it structurally instead: every `fetch_*`
that `_fetch_sources` invokes must be frozen by any fixture claiming to be
hermetic.

Hermetic itself — parses source text, touches neither warehouse nor network.
"""

import ast
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
APP_PY = ROOT / "L5_apps" / "digest" / "app.py"

# Fixtures that must freeze EVERY seam. Scoped to the golden test, which is the
# one that asserts exact rendered output and therefore actually drifts when a
# live source leaks in.
#
# test_digest_llm.py / test_digest_aidash.py are deliberately NOT in this list
# yet. They freeze the 5 seams whose values they care about (including the PR
# union — fixed alongside this guard) but leave 8 batch-2 seams live:
#   fetch_ai_efficiency, fetch_app_focus, fetch_commit_by_repo,
#   fetch_cost_improvement, fetch_model_tier, fetch_news_radar,
#   fetch_value_efficiency, fetch_work_by_project
# They assert on LLM fallback / push behaviour rather than exact numbers, so
# they do not silently drift — but they do read the local warehouse, which is
# slower than it should be and is hermeticity in name only. Bringing them under
# this guard means extracting the golden's freeze-everything fixture into a
# shared helper; that is a separate change from the PR-union refactor this
# guard shipped with, so it is recorded here rather than done silently.
STRICT_FIXTURE_FILES = [
    "test_digest_golden.py",
]


def _seams_called_by_fetch_sources() -> set[str]:
    """Names of every `fetch_*` invoked inside `_fetch_sources`.

    Read from the AST, not a hand-maintained list — a hand list is exactly the
    thing that drifts when a new source is added.
    """
    tree = ast.parse(APP_PY.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "_fetch_sources":
            return {
                n.func.id
                for n in ast.walk(node)
                if isinstance(n, ast.Call)
                and isinstance(n.func, ast.Name)
                and n.func.id.startswith("fetch_")
            }
    raise AssertionError("_fetch_sources not found in app.py")


def _frozen_in(filename: str) -> set[str]:
    text = (ROOT / "tests" / filename).read_text(encoding="utf-8")
    return set(re.findall(r'monkeypatch\.setattr\(\s*app,\s*"(fetch_\w+)"', text))


def test_fetch_sources_has_seams():
    """Guard the guard: if the AST walk finds nothing, the test below is vacuous."""
    seams = _seams_called_by_fetch_sources()
    assert len(seams) >= 5, f"suspiciously few seams found: {seams}"


@pytest.mark.parametrize("filename", STRICT_FIXTURE_FILES)
def test_strict_fixtures_freeze_every_seam(filename: str):
    missing = _seams_called_by_fetch_sources() - _frozen_in(filename)
    assert not missing, (
        f"{filename} does not freeze {sorted(missing)} — _fetch_sources calls "
        f"them, so the test reads this machine's live warehouse. It will pass "
        f"on a fresh clone and drift where real data exists. Freeze the seam "
        f"_fetch_sources ACTUALLY calls, not a similarly-named sibling."
    )


@pytest.mark.parametrize("filename", ["test_digest_llm.py", "test_digest_aidash.py"])
def test_pr_union_seam_is_frozen(filename: str):
    """The PR seam specifically must be frozen everywhere it is referenced.

    Narrower than the strict check above, and separate on purpose: freezing
    `fetch_ado_pr_trends` alone looks right but misses the union the app calls.
    Any fixture that bothers to freeze the ADO series must freeze the union too,
    or it is asserting against half the data it thinks it froze.
    """
    frozen = _frozen_in(filename)
    if "fetch_ado_pr_trends" in frozen:
        assert "fetch_combined_pr_trends" in frozen, (
            f"{filename} freezes fetch_ado_pr_trends but not "
            f"fetch_combined_pr_trends — _fetch_sources calls the union, so "
            f"live GitHub PRs leak into a test that looks frozen."
        )
