import subprocess
from pathlib import Path

import pytest

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
    n = int(_q(
        "SELECT count(*) FROM fact_request "
        "WHERE cost_usd IS NULL AND input_tokens IS NOT NULL "
        "AND output_tokens IS NOT NULL;"
    ))
    assert n == 0, f"{n} rows have tokens but no cost"
