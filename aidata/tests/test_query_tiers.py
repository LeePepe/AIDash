"""L4 query tiers — production contract vs exploratory (audit Phase 3).

The audit found L4 mixing two populations with very different lifetimes:

  24 queries feed the daily digest through L5 — changing their shape breaks a
     card, so they are a CONTRACT.
  15 queries have no L5 consumer at all — they exist for ad-hoc investigation
     via `cli.py query <name>`, and nothing downstream depends on their columns.

Nothing marked the difference, so both looked equally load-bearing. An agent
refactoring the warehouse could not tell which queries it was free to change,
and the 15 exploratory ones added noise to every "what does L4 guarantee?"
question.

Rather than MOVE the exploratory files (their paths are published in README
usage examples and cli.py's `--help`, and `cli.py query issues/trend` is
documented — moving them breaks every one of those), each declares its tier
in a header line, mirroring the existing `-- aidata-attach:` convention:

    -- aidata-tier: explore

Absence of the marker means production. These tests keep the two populations
honest: every query declares a valid tier, the production set is exactly what
L5 actually imports, and no exploratory query is silently wired into L5.

Hermetic — reads only the repo's .sql and .py files, never the warehouse.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUERIES = ROOT / "L4_serve" / "queries"
DIGEST = ROOT / "L5_apps" / "digest"

TIER_DIRECTIVE = re.compile(r"^\s*--\s*aidata-tier:\s*(\S+)\s*$", re.MULTILINE)
VALID_TIERS = {"explore"}

# Every query name L5 references as a string literal. This is how the digest
# actually addresses queries (serve.run_query("trend/daily-cost")), so it is the
# real consumer set — not a hand-maintained list that would drift.
QUERY_REF = re.compile(
    r'"((?:trend|cost|roi|health|work|radar|news|time|inbox|issues|behavior'
    r'|memory|tools)/[a-z0-9-]+)"'
)


def _all_queries() -> set[str]:
    return {
        str(p.relative_to(QUERIES).with_suffix("")) for p in QUERIES.glob("**/*.sql")
    }


def _tier_of(name: str) -> str:
    sql = (QUERIES / f"{name}.sql").read_text(encoding="utf-8")
    match = TIER_DIRECTIVE.search(sql)
    return match.group(1) if match else "production"


def _l5_referenced() -> set[str]:
    names: set[str] = set()
    for path in DIGEST.glob("*.py"):
        names |= set(QUERY_REF.findall(path.read_text(encoding="utf-8")))
    return names


def test_every_query_declares_a_valid_tier():
    """A typo'd marker would silently read as production — catch it."""
    bad = {
        name: _tier_of(name)
        for name in _all_queries()
        if _tier_of(name) not in VALID_TIERS | {"production"}
    }
    assert not bad, f"queries with an unrecognized aidata-tier: {bad}"


def test_production_tier_is_exactly_what_l5_consumes():
    """The contract set must match reality in BOTH directions.

    A production query with no consumer is an orphan that should be marked
    explore; an explore query that L5 imports is a contract in disguise, and
    changing its columns would break a card without warning.
    """
    production = {n for n in _all_queries() if _tier_of(n) == "production"}
    referenced = _l5_referenced()

    unconsumed = production - referenced
    assert not unconsumed, (
        f"production queries with no L5 consumer: {sorted(unconsumed)} — "
        "either wire them into the digest or mark `-- aidata-tier: explore`"
    )

    # Only flag names that actually exist; a stale string in L5 is a different
    # bug, covered by test_l5_references_resolve below.
    misfiled = (referenced & _all_queries()) - production
    assert not misfiled, (
        f"explore queries consumed by L5: {sorted(misfiled)} — "
        "they are a contract; remove their explore marker"
    )


def test_l5_references_resolve():
    """Every query name L5 mentions exists on disk (guards renames)."""
    missing = _l5_referenced() - _all_queries()
    assert not missing, f"L5 references non-existent queries: {sorted(missing)}"


def test_explore_tier_is_documented():
    """The convention must be discoverable, or the markers rot into noise."""
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "aidata-tier" in readme, "README does not explain the aidata-tier marker"
