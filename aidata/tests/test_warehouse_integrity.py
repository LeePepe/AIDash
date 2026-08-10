import subprocess
from pathlib import Path

import pytest

from config import UNPRICED_MODELS

ROOT = Path(__file__).resolve().parent.parent
WAREHOUSE = ROOT / "L3_merge" / "warehouse.db"

# The warehouse is a gitignored local artifact (built by `cli.py merge`). On a
# fresh clone or in CI it does not exist, so these integration tests have
# nothing to assert against — skip rather than fail. `pytest -m integration`
# on a machine with a built warehouse still runs them for real.
pytestmark = pytest.mark.skipif(
    not WAREHOUSE.exists(),
    reason="warehouse.db not built (gitignored local artifact) — run `cli.py merge`",
)


def _q(sql: str):
    # use system sqlite3 CLI (default python3 sqlite is too old for the WAL DBs,
    # but warehouse.db is written by us — still, be consistent with the project)
    out = subprocess.run(
        ["sqlite3", str(WAREHOUSE), sql],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return out


@pytest.mark.integration
def test_fact_request_has_model_canon():
    cols = _q("PRAGMA table_info(fact_request);")
    assert "model_canon" in cols


@pytest.mark.integration
def test_model_canon_collapses_names():
    # canon count strictly less than raw model count (dotted/hyphen merged)
    raw = int(_q("SELECT count(DISTINCT model) FROM fact_request;"))
    canon = int(_q("SELECT count(DISTINCT model_canon) FROM fact_request;"))
    assert canon < raw


@pytest.mark.integration
def test_no_tokens_without_cost():
    # The v2 headline fix: every row that has BOTH tokens must have a cost.
    # (NULL-token rows legitimately stay NULL — excluded here.)
    #
    # UNPRICED_MODELS is the one sanctioned escape hatch. Some models have no
    # published price at all (internal/codename builds), and inventing a number
    # would be worse than a NULL: a made-up rate turns an honest gap into a
    # precise-looking wrong number that flows into the cost-attribution cards
    # and never trips a gate again. So those rows stay NULL on purpose and are
    # measured in TOKENS, not dollars.
    #
    # The exemption is deliberately narrow — an explicit name list, not a
    # predicate — so a NEW unpriced model still fails this test loudly instead
    # of silently joining the exempt set. Adding a name here is a decision.
    #
    # The empty-list short-circuit matters: the finding doc tells the next
    # reader to REMOVE a name once a real price is known, and emptying the tuple
    # would otherwise render `NOT IN ()`, which SQLite rejects as a syntax
    # error — the gate would explode instead of passing, right at the moment it
    # should simply become unconditional again.
    # `model_canon IS NULL` must stay INSIDE the gate. SQLite evaluates
    # `NULL NOT IN (...)` to NULL, not true, so a bare NOT IN silently drops
    # every NULL-model row from the count — verified: 2 rows, `NOT IN` counts 1.
    # model_canon() returns None for empty/None input and _cost() returns None
    # in the same case, so "tokens present, cost NULL, model_canon NULL" is a
    # REAL shape this gate is supposed to catch. Excluding it would widen the
    # exemption far beyond the explicit name list this comment promises.
    clause = ""
    if UNPRICED_MODELS:
        exempt = ", ".join(f"'{m}'" for m in UNPRICED_MODELS)
        clause = f" AND (model_canon IS NULL OR model_canon NOT IN ({exempt}))"
    n = int(_q(
        "SELECT count(*) FROM fact_request "
        "WHERE cost_usd IS NULL AND input_tokens IS NOT NULL "
        f"AND output_tokens IS NOT NULL{clause};"
    ))
    assert n == 0, f"{n} rows have tokens but no cost (and are not in UNPRICED_MODELS)"


@pytest.mark.integration
def test_unpriced_models_still_carry_tokens():
    # The flip side of the exemption: an unpriced model must still be fully
    # measurable in tokens. If these rows lost their token counts too they
    # would be invisible everywhere, not just in the dollar columns — the
    # exemption is about MISSING PRICE, never about missing usage.
    if not UNPRICED_MODELS:
        pytest.skip("no unpriced models — nothing to assert")
    exempt = ", ".join(f"'{m}'" for m in UNPRICED_MODELS)
    n = int(_q(
        "SELECT count(*) FROM fact_request "
        f"WHERE model_canon IN ({exempt}) AND total_tokens IS NULL;"
    ))
    assert n == 0, f"{n} unpriced-model rows also lack tokens — usage must stay measurable"
