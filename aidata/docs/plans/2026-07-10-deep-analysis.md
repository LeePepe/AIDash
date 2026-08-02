# aidata v2: Data-Quality Fixes + First Deep-Analysis Set — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 8 data pitfalls in aidata's L2 normalize layer so the warehouse is trustworthy, then ship 7 STRONG-data-supported deep-analysis queries in L4.

**Architecture:** Architecture decision A — pitfalls are fixed once at the source (L2 normalize + schema), so L3 merge and all L4 queries inherit clean data. Original fields stay immutable; canonicalization is a new derived column `model_canon`. Analysis queries are plain `.sql` files run via `aidata query <name>`.

**Tech Stack:** Python 3.11 (stdlib only — sqlite3, csv, json), system `sqlite3` CLI (via existing `sqlite_ro.py`) because the default python3 bundles sqlite 3.19. pytest for tests.

## Global Constraints

- **Immutable original data**: never overwrite the raw `model` column; add derived `model_canon` alongside. (spec Part 1, "核心原则")
- **NULL cost is correct when tokens are NULL**: only rows with BOTH input+output tokens present must get a cost; NULL-token rows (errors) stay NULL. (spec Part 1 组1 注意)
- **Stdlib only** — no new pip dependencies. Match existing adapter style (module-level `SOURCE`, `collect()`, `normalize()`).
- **Read-only sources**: never write to raven.db / source DBs.
- **UTC storage, local display**: raw/warehouse timestamps stay UTC epoch-ms; every L4 time query uses `datetime(ts/1000,'unixepoch','localtime')`. (spec Part 1 组3)
- **Cost matching uses `model_canon`**, but the derived USD is written back to the existing `cost_usd` column (cost does not fork). (spec Part 1 组1, self-review fix)
- Python style: PEP 8, type annotations on all signatures, functions <50 lines, files focused.
- Tests: pytest, `@pytest.mark.unit` / `@pytest.mark.integration` categorization.

---

## File Structure

**New files:**
- `adapters/model_canon.py` — pure model-name canonicalization function. One responsibility: map any observed model string → canonical form.
- `tests/__init__.py` — test package marker.
- `tests/test_model_canon.py` — unit tests for canonicalization.
- `tests/test_raven_cost.py` — unit tests for cost derivation via canon.
- `tests/test_warehouse_integrity.py` — integration tests asserting no "tokens-but-no-cost" rows, canon collapses names.
- `L4_serve/queries/cost/pareto.sql`
- `L4_serve/queries/cost/model-downgrade.sql`
- `L4_serve/queries/cost/context-waste.sql`
- `L4_serve/queries/health/agent-scorecard.sql`
- `L4_serve/queries/health/wasted-tokens.sql`
- `L4_serve/queries/health/rework-loops.sql`
- `L4_serve/queries/behavior/runaway-sessions.sql`

**Modified files:**
- `schema/dim_model.csv` — add missing models, keyed by canonical name.
- `schema/warehouse.sql` — add `model_canon` column to `fact_request`; fix multica-tokens comment; flag deprecated/broken fields.
- `adapters/raven.py` — compute `model_canon` in `normalize()`, use it for price lookup; add to clean DDL/cols.
- `merge.py` — carry `model_canon` from `rv.req` into `fact_request`.
- `README.md` — document the UTC→local query convention.

**Task boundaries:** Tasks 1-5 are the data-quality fix (each independently testable). Tasks 6-12 are one analysis query each. Task 13 is docs + final verification.

---

## Task 1: Model-name canonicalization function

**Files:**
- Create: `adapters/model_canon.py`
- Create: `tests/__init__.py`
- Create: `tests/test_model_canon.py`

**Interfaces:**
- Produces: `model_canon(model: str | None) -> str | None` — returns a canonical model id. Rules: `None`/empty → `None`; unify dotted↔hyphen minor versions (`claude-opus-4.7` → `claude-opus-4-7`); unify `-1m`/`.6-1m` suffix ordering (`claude-opus-4.6-1m` → `claude-opus-4-6-1m`); leave already-canonical and unknown names untouched (returned as-is after normalization pass).

- [ ] **Step 1: Write the failing test**

Create `tests/__init__.py` (empty file).

Create `tests/test_model_canon.py`:

```python
import pytest

from adapters.model_canon import model_canon


@pytest.mark.unit
def test_none_and_empty():
    assert model_canon(None) is None
    assert model_canon("") is None


@pytest.mark.unit
def test_dotted_minor_to_hyphen():
    # dotted minor version unified to hyphen form
    assert model_canon("claude-opus-4.7") == "claude-opus-4-7"
    assert model_canon("claude-opus-4.6") == "claude-opus-4-6"
    assert model_canon("claude-opus-4.8") == "claude-opus-4-8"
    assert model_canon("claude-sonnet-4.6") == "claude-sonnet-4-6"


@pytest.mark.unit
def test_one_million_suffix_unified():
    # both spellings collapse to one canonical
    assert model_canon("claude-opus-4.6-1m") == model_canon("claude-opus-4-6-1m")
    assert model_canon("claude-opus-4.6-1m") == "claude-opus-4-6-1m"


@pytest.mark.unit
def test_already_canonical_untouched():
    assert model_canon("claude-opus-4-7") == "claude-opus-4-7"
    assert model_canon("gpt-5.5") == "gpt-5.5"   # gpt dotted versions are canonical
    assert model_canon("claude-haiku-4-5-20251001") == "claude-haiku-4-5-20251001"


@pytest.mark.unit
def test_haiku_short_and_long_same():
    assert model_canon("claude-haiku-4.5") == "claude-haiku-4-5"
    assert model_canon("claude-haiku-4-5") == "claude-haiku-4-5"


@pytest.mark.unit
def test_unknown_passthrough():
    assert model_canon("models") == "models"
    assert model_canon("gpt-4o-mini") == "gpt-4o-mini"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_model_canon.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'adapters.model_canon'`

- [ ] **Step 3: Write minimal implementation**

Create `adapters/model_canon.py`:

```python
"""Model-name canonicalization.

Observed raven data spells the same model several ways (claude-opus-4.7 vs
claude-opus-4-7, claude-opus-4.6-1m vs claude-opus-4-6-1m). Aggregations and
price lookups split across these. `model_canon` maps any spelling to one
canonical id. Original `model` is preserved upstream; this is a derived value.

Rule for Claude models: dotted minor versions become hyphenated
(claude-opus-4.7 -> claude-opus-4-7). GPT models keep dotted versions
(gpt-5.5 is canonical). Unknown names pass through the same transform.
"""

from __future__ import annotations

import re

# Turn "claude-<family>-<major>.<minor>" into "claude-<family>-<major>-<minor>".
# Only applies to claude- models; gpt-5.5 etc. keep their dot.
_CLAUDE_DOTTED = re.compile(r"^(claude-[a-z]+-\d+)\.(\d+)")


def model_canon(model: str | None) -> str | None:
    """Return the canonical model id, or None for null/empty input."""
    if not model:
        return None
    m = model.strip()
    if m.startswith("claude-"):
        # claude-opus-4.7 -> claude-opus-4-7 ; claude-opus-4.6-1m -> claude-opus-4-6-1m
        m = _CLAUDE_DOTTED.sub(r"\1-\2", m)
    return m
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_model_canon.py -v`
Expected: PASS (7 passed)

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add adapters/model_canon.py tests/__init__.py tests/test_model_canon.py
git commit -m "feat: model-name canonicalization for aidata"
```

---

## Task 2: Complete the price map (dim_model.csv)

**Files:**
- Modify: `schema/dim_model.csv`
- Test: `tests/test_model_canon.py` (add coverage assertion)

**Interfaces:**
- Consumes: `model_canon()` from Task 1.
- Produces: `schema/dim_model.csv` whose `model` column holds **canonical** ids and covers every model that appears in real data with non-null tokens.

The models needing entries (canonical form → the raw spellings they cover), from the real data census:
`claude-opus-4-8`, `claude-opus-4-7`(+`claude-opus-4.7`), `claude-opus-4-6`(+`claude-opus-4.6`), `claude-opus-4-6-1m`(+`claude-opus-4.6-1m`), `claude-opus-4-5`, `claude-sonnet-4-6`(+`claude-sonnet-4.6`), `claude-sonnet-4-5`, `claude-sonnet-4`, `claude-sonnet-4-20250514`, `claude-haiku-4-5`(+`claude-haiku-4.5`), `claude-haiku-4-5-20251001`, `claude-3-5-sonnet-20241022`, `claude-3-5-haiku`(+`-20241022`), `claude-3-haiku`, `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-2026-03-05`, `gpt-5`, `gpt-5-mini`, `gpt-5.1-codex`, `gpt-5.3-codex`, `gpt-4.1`, `gpt-4o-mini`, `codex-5.5`, `google/gemini-3-flash-preview`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_model_canon.py`:

```python
@pytest.mark.unit
def test_price_map_covers_common_models():
    import csv
    from pathlib import Path
    from adapters.model_canon import model_canon

    csv_path = Path(__file__).resolve().parent.parent / "schema" / "dim_model.csv"
    priced = {row["model"] for row in csv.DictReader(csv_path.open())}
    # Models that appear with real tokens must be priced under their canonical id.
    for raw in ["gpt-5-mini", "claude-sonnet-4", "claude-sonnet-4-5",
                "claude-opus-4-6-1m", "gpt-4.1", "claude-opus-4-8", "gpt-5.5"]:
        assert model_canon(raw) in priced, f"{raw} -> {model_canon(raw)} not priced"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_model_canon.py::test_price_map_covers_common_models -v`
Expected: FAIL — assertion error on `gpt-5-mini` (not yet priced).

- [ ] **Step 3: Write minimal implementation**

Replace `schema/dim_model.csv` entirely with (USD per 1M tokens; codex/gpt use published list prices, unknown/gemini priced at 0 to avoid fabricating — they get counted as $0, not NULL):

```csv
model,input_per_mtok,output_per_mtok,cache_read_per_mtok,cache_write_per_mtok
claude-opus-4-8,5.00,25.00,0.50,6.25
claude-opus-4-7,5.00,25.00,0.50,6.25
claude-opus-4-6,5.00,25.00,0.50,6.25
claude-opus-4-6-1m,7.50,37.50,0.75,9.375
claude-opus-4-5,5.00,25.00,0.50,6.25
claude-sonnet-4-6,3.00,15.00,0.30,3.75
claude-sonnet-4-5,3.00,15.00,0.30,3.75
claude-sonnet-4,3.00,15.00,0.30,3.75
claude-sonnet-4-20250514,3.00,15.00,0.30,3.75
claude-sonnet-5,3.00,15.00,0.30,3.75
claude-haiku-4-5,1.00,5.00,0.10,1.25
claude-haiku-4-5-20251001,1.00,5.00,0.10,1.25
claude-3-5-sonnet-20241022,3.00,15.00,0.30,3.75
claude-3-5-haiku,0.80,4.00,0.08,1.00
claude-3-5-haiku-20241022,0.80,4.00,0.08,1.00
claude-3-haiku,0.25,1.25,0.03,0.30
gpt-5.5,1.25,10.00,0.125,0
gpt-5.4,1.25,10.00,0.125,0
gpt-5.4-mini,0.25,2.00,0.025,0
gpt-5.4-2026-03-05,1.25,10.00,0.125,0
gpt-5,1.25,10.00,0.125,0
gpt-5-mini,0.25,2.00,0.025,0
gpt-5.1-codex,1.25,10.00,0.125,0
gpt-5.3-codex,1.25,10.00,0.125,0
codex-5.5,1.25,10.00,0.125,0
gpt-4.1,2.00,8.00,0.50,0
gpt-4o-mini,0.15,0.60,0.075,0
google/gemini-3-flash-preview,0,0,0,0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_model_canon.py -v`
Expected: PASS (8 passed)

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add schema/dim_model.csv tests/test_model_canon.py
git commit -m "feat: complete dim_model price map keyed by canonical name"
```

---

## Task 3: raven normalize — compute model_canon and price by it

**Files:**
- Modify: `adapters/raven.py:96-167` (`_load_prices`, `_cost`, `_CLEAN_DDL`, `_CLEAN_COLS`, `normalize`)
- Create: `tests/test_raven_cost.py`

**Interfaces:**
- Consumes: `model_canon()` (Task 1), completed `dim_model.csv` (Task 2).
- Produces: clean `raven.db` `req` table gains a `model_canon TEXT` column; `cost_usd` is derived by looking up `model_canon` in the price map; rows with both tokens present and a priced canon get a non-null cost.

- [ ] **Step 1: Write the failing test**

Create `tests/test_raven_cost.py`:

```python
import pytest

from adapters.raven import _cost, _load_prices


@pytest.mark.unit
def test_cost_uses_canonical_lookup():
    prices = _load_prices()
    # dotted spelling must still price (via canon) — same as hyphen form
    c_dotted = _cost("claude-opus-4.7", 1_000_000, 1_000_000, prices)
    c_hyphen = _cost("claude-opus-4-7", 1_000_000, 1_000_000, prices)
    assert c_dotted is not None
    assert c_dotted == c_hyphen


@pytest.mark.unit
def test_cost_null_tokens_stay_null():
    prices = _load_prices()
    assert _cost("claude-opus-4-8", None, 5, prices) is None
    assert _cost("claude-opus-4-8", 100, None, prices) is None


@pytest.mark.unit
def test_previously_unpriced_model_now_costs():
    prices = _load_prices()
    # gpt-5-mini and claude-sonnet-4 were NULL-cost before the price map fix
    assert _cost("gpt-5-mini", 1_000_000, 1_000_000, prices) is not None
    assert _cost("claude-sonnet-4", 1_000_000, 1_000_000, prices) is not None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_raven_cost.py -v`
Expected: FAIL — `test_cost_uses_canonical_lookup` fails because `_cost` currently looks up the raw dotted name, which isn't in the (canonical-keyed) price map → returns None.

- [ ] **Step 3: Write minimal implementation**

In `adapters/raven.py`, add the import near the top (after line 21):

```python
from adapters.model_canon import model_canon
```

Replace `_cost` (currently lines 115-120) with a version that canonicalizes before lookup:

```python
def _cost(model, itok, otok, prices) -> float | None:
    """Derive notional USD cost, matching price by canonical model name.

    NULL tokens -> NULL cost (don't guess). Unknown canon -> NULL cost.
    """
    p = prices.get(model_canon(model))
    if p is None or itok is None or otok is None:
        return None
    return round(itok / 1e6 * p["in"] + otok / 1e6 * p["out"], 6)
```

Replace `_CLEAN_DDL` (lines 123-131) to add `model_canon`:

```python
_CLEAN_DDL = """
CREATE TABLE req (
    request_id TEXT PRIMARY KEY, ts INTEGER, client TEXT, version TEXT,
    model TEXT, model_canon TEXT, resolved_model TEXT,
    input_tokens INTEGER, output_tokens INTEGER,
    total_tokens INTEGER, latency_ms INTEGER, ttft_ms INTEGER, status TEXT,
    cost_usd REAL, session_uuid TEXT, has_session INTEGER, tool_call_count INTEGER,
    strategy TEXT, path TEXT
)
"""
```

Replace `_CLEAN_COLS` (lines 132-137) to include `model_canon`:

```python
_CLEAN_COLS = (
    "request_id", "ts", "client", "version", "model", "model_canon",
    "resolved_model", "input_tokens", "output_tokens", "total_tokens",
    "latency_ms", "ttft_ms", "status", "cost_usd", "session_uuid",
    "has_session", "tool_call_count", "strategy", "path",
)
```

In `normalize()` (the row dict built at lines 147-166), add `model_canon` right after the `"model"` key:

```python
            "model": model,
            "model_canon": model_canon(model),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_raven_cost.py -v`
Expected: PASS (3 passed)

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add adapters/raven.py tests/test_raven_cost.py
git commit -m "feat: raven prices by canonical model name, adds model_canon column"
```

---

## Task 4: Warehouse schema — model_canon column + corrected annotations

**Files:**
- Modify: `schema/warehouse.sql` (fact_request block lines 11-33; fact_task comment ~lines 74-83)
- Modify: `merge.py:62-73` (fact_request INSERT/SELECT)

**Interfaces:**
- Consumes: clean `req.model_canon` (Task 3).
- Produces: `fact_request.model_canon` populated in the warehouse; corrected schema comments.

- [ ] **Step 1: Write the failing test**

Create `tests/test_warehouse_integrity.py`:

```python
import sqlite3
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
WAREHOUSE = ROOT / "L3_merge" / "warehouse.db"


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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_warehouse_integrity.py -v`
Expected: FAIL — `no such column: model_canon` (schema not yet updated; warehouse not rebuilt).

- [ ] **Step 3: Write minimal implementation**

In `schema/warehouse.sql`, in the `CREATE TABLE fact_request` block, add `model_canon` right after the `model` line (line 16):

```sql
    model           TEXT,
    model_canon     TEXT,               -- canonical model id (derived; original model preserved)
```

Add an index after the existing fact_request indexes (after line 33):

```sql
CREATE INDEX IF NOT EXISTS idx_req_model_canon ON fact_request(model_canon);
```

In the `fact_task` comment block, correct the mislabeled token note. Find the line reading `-- Source: multica runs + claude jobs. multica runs have NO token field` and replace that clause with:

```sql
-- Source: multica runs + claude jobs. multica runs DO carry tokens
-- (499/508 populated, ~2.54B total — the warehouse's richest cost signal);
-- claude jobs carry cumulative `tokens`.
```

Also flag the degenerate field on `fact_request.tool_call_count` — change its column comment to:

```sql
    tool_call_count INTEGER             -- DEPRECATED: uniformly 0 in raven, do not use
```

In `merge.py`, update the fact_request INSERT (lines 62-73) to carry `model_canon`:

```python
        if _attach(conn, "raven", "rv"):
            conn.execute("""
                INSERT INTO fact_request
                  (request_id, ts, client, version, model, model_canon,
                   resolved_model, input_tokens, output_tokens, cache_read,
                   cache_write, total_tokens, latency_ms, ttft_ms, status,
                   cost_usd, session_uuid, has_session, tool_call_count)
                SELECT request_id, ts, client, version, model, model_canon,
                       resolved_model, input_tokens, output_tokens, NULL, NULL,
                       total_tokens, latency_ms, ttft_ms, status, cost_usd,
                       session_uuid, has_session, tool_call_count
                FROM rv.req
            """)
            counts["fact_request"] = conn.execute(
                "SELECT count(*) FROM fact_request").fetchone()[0]
```

- [ ] **Step 4: Rebuild the warehouse, then run tests**

Run:
```bash
cd ~/Development/AIDash/aidata
python3 cli.py normalize --source raven
python3 cli.py merge
python3 -m pytest tests/test_warehouse_integrity.py -v
```
Expected: PASS (2 passed) — `model_canon` exists and collapses names.

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add schema/warehouse.sql merge.py tests/test_warehouse_integrity.py
git commit -m "feat: warehouse model_canon column + corrected field annotations"
```

---

## Task 5: Verify the cost-gap is closed (integrity gate)

**Files:**
- Modify: `tests/test_warehouse_integrity.py` (add the headline assertion)

**Interfaces:**
- Consumes: rebuilt warehouse from Task 4.
- Produces: a regression test proving the "16,264 rows with tokens but no cost" bug is fixed (→ 0).

- [ ] **Step 1: Write the failing test**

Add to `tests/test_warehouse_integrity.py`:

```python
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
```

- [ ] **Step 2: Run test to verify current state**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_warehouse_integrity.py::test_no_tokens_without_cost -v`
Expected: If Tasks 2-4 fully applied and warehouse rebuilt, this may already PASS. If it FAILS with a nonzero count, inspect which models still lack a price:
```bash
sqlite3 L3_merge/warehouse.db "SELECT model_canon, count(*) n FROM fact_request WHERE cost_usd IS NULL AND input_tokens IS NOT NULL AND output_tokens IS NOT NULL GROUP BY model_canon ORDER BY n DESC;"
```
Add any missing `model_canon` to `schema/dim_model.csv`, then re-run `normalize --source raven` + `merge`.

- [ ] **Step 3: Ensure pass**

Iterate price-map additions until the count is 0. (Every model in the diagnostic query above must appear in `dim_model.csv` under its canonical name.)

- [ ] **Step 4: Confirm total spend rose**

Run:
```bash
sqlite3 L3_merge/warehouse.db "SELECT round(sum(cost_usd),2) FROM fact_request;"
```
Expected: a value noticeably higher than the pre-fix $86,290 (sonnet-4 / gpt-5-mini cost now counted). Record the number.

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add tests/test_warehouse_integrity.py schema/dim_model.csv
git commit -m "test: gate that all token-bearing requests have cost"
```

---

## Task 6: Query — cost/pareto

**Files:**
- Create: `L4_serve/queries/cost/pareto.sql`

**Interfaces:**
- Consumes: `fact_request` (ts, cost_usd, model_canon). Run via `python3 cli.py query cost/pareto`.
- Produces: cost concentration by model_canon (the cleanest STRONG cut; session-level needs claude-cli-only session_uuid, so model/day cuts are used).

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/cost/pareto.sql`:

```sql
-- cost/pareto — spend concentration by model (STRONG: full $ coverage).
-- Shows each model's share and the running cumulative share, so you can read
-- "top N models = X% of spend" directly. Uses model_canon so dotted/hyphen
-- spellings are merged.
WITH per_model AS (
  SELECT model_canon AS model,
         round(sum(cost_usd), 2) AS cost_usd,
         count(*)                AS requests
  FROM fact_request
  WHERE cost_usd IS NOT NULL
  GROUP BY model_canon
),
ranked AS (
  SELECT model, cost_usd, requests,
         sum(cost_usd) OVER (ORDER BY cost_usd DESC
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           AS cum_cost,
         sum(cost_usd) OVER () AS total_cost
  FROM per_model
)
SELECT model, cost_usd, requests,
       round(100.0 * cost_usd / total_cost, 1) AS pct_of_spend,
       round(100.0 * cum_cost / total_cost, 1) AS cumulative_pct
FROM ranked
ORDER BY cost_usd DESC;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query cost/pareto`
Expected: table where the top model's `pct_of_spend` is a large share (opus family dominant) and `cumulative_pct` climbs to 100.0 at the last row.

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/cost/pareto.sql
git commit -m "feat: cost/pareto query — spend concentration by model"
```

---

## Task 7: Query — cost/model-downgrade

**Files:**
- Create: `L4_serve/queries/cost/model-downgrade.sql`

**Interfaces:**
- Consumes: `fact_request` (model_canon, output_tokens, cost_usd). Run via `python3 cli.py query cost/model-downgrade`.
- Produces: expensive-model requests that returned tiny outputs — downgrade candidates with wasted $.

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/cost/model-downgrade.sql`:

```sql
-- cost/model-downgrade — Opus (or any pricey model) used for tiny outputs.
-- Flags requests on opus-tier models that produced <20 output tokens: trivial
-- completions that a cheaper model would serve. Sum the cost to see the prize.
SELECT model_canon                                   AS model,
       count(*)                                      AS tiny_output_requests,
       round(sum(cost_usd), 2)                       AS wasted_usd,
       round(avg(input_tokens), 0)                   AS avg_input_tokens
FROM fact_request
WHERE model_canon LIKE 'claude-opus-%'
  AND output_tokens IS NOT NULL AND output_tokens < 20
  AND cost_usd IS NOT NULL
GROUP BY model_canon
ORDER BY wasted_usd DESC;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query cost/model-downgrade`
Expected: `claude-opus-4-8` row with several thousand requests and a wasted_usd near the verified ~$1,534 anchor (value will be higher now that dotted opus-4.8 spellings merge in).

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/cost/model-downgrade.sql
git commit -m "feat: cost/model-downgrade query — opus-for-tiny-output waste"
```

---

## Task 8: Query — cost/context-waste

**Files:**
- Create: `L4_serve/queries/cost/context-waste.sql`

**Interfaces:**
- Consumes: `fact_request` (input_tokens, output_tokens, cost_usd, model_canon). Run via `python3 cli.py query cost/context-waste`.
- Produces: big-input/tiny-output requests (context bloat) with count and cost.

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/cost/context-waste.sql`:

```sql
-- cost/context-waste — huge input, near-empty output. Paying to stuff big
-- contexts (>50k input) for <20 output tokens: prompt bloat or misfires.
SELECT count(*)                        AS requests,
       round(avg(input_tokens), 0)     AS avg_input_tokens,
       round(sum(cost_usd), 2)         AS total_usd,
       round(max(input_tokens), 0)     AS max_input_tokens
FROM fact_request
WHERE input_tokens IS NOT NULL AND input_tokens > 50000
  AND output_tokens IS NOT NULL AND output_tokens < 20
  AND cost_usd IS NOT NULL;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query cost/context-waste`
Expected: one row, `requests` in the low thousands (~2,259 anchor), avg_input_tokens ~100k, total_usd near ~$1,056.

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/cost/context-waste.sql
git commit -m "feat: cost/context-waste query — big-input tiny-output spend"
```

---

## Task 9: Query — health/agent-scorecard

**Files:**
- Create: `L4_serve/queries/health/agent-scorecard.sql`

**Interfaces:**
- Consumes: `fact_task` (agent_id, source, status, ts_start, ts_end, tokens). Run via `python3 cli.py query health/agent-scorecard`.
- Produces: per-agent reliability × cycle time × token burn — one row per multica agent.

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/health/agent-scorecard.sql`:

```sql
-- health/agent-scorecard — reliability + speed + token burn per multica agent.
-- Cycle time from ISO ts_start/ts_end (julianday diff -> seconds). Only
-- multica_run rows carry agent_id; claude_job rows are excluded.
SELECT agent_id,
       count(*)                                              AS runs,
       sum(status = 'completed')                             AS completed,
       sum(status = 'cancelled')                             AS cancelled,
       sum(status = 'failed')                                AS failed,
       round(100.0 * sum(status = 'completed') / count(*), 1) AS completion_pct,
       round(avg((julianday(ts_end) - julianday(ts_start)) * 86400.0), 0)
                                                             AS avg_seconds,
       round(avg(tokens), 0)                                 AS avg_tokens
FROM fact_task
WHERE source = 'multica_run' AND agent_id IS NOT NULL
GROUP BY agent_id
ORDER BY completion_pct ASC;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query health/agent-scorecard`
Expected: the worst agent at the top with completion_pct near the verified ~40.8% anchor, and its avg_seconds / avg_tokens the highest (multi-signal problem child).

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/health/agent-scorecard.sql
git commit -m "feat: health/agent-scorecard query — reliability/speed/tokens per agent"
```

---

## Task 10: Query — health/wasted-tokens

**Files:**
- Create: `L4_serve/queries/health/wasted-tokens.sql`

**Interfaces:**
- Consumes: `fact_task` (source, status, tokens). Run via `python3 cli.py query health/wasted-tokens`.
- Produces: share of multica tokens spent on non-completed runs.

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/health/wasted-tokens.sql`:

```sql
-- health/wasted-tokens — tokens burned on runs that did not complete.
-- Uses multica_run tokens (the corrected, populated field). Shows each terminal
-- status's token share so cancelled/failed waste is explicit.
WITH totals AS (
  SELECT sum(COALESCE(tokens, 0)) AS all_tokens
  FROM fact_task WHERE source = 'multica_run'
)
SELECT status,
       count(*)                                        AS runs,
       sum(COALESCE(tokens, 0))                        AS tokens,
       round(100.0 * sum(COALESCE(tokens, 0)) /
             (SELECT all_tokens FROM totals), 1)        AS pct_of_tokens
FROM fact_task
WHERE source = 'multica_run'
GROUP BY status
ORDER BY tokens DESC;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query health/wasted-tokens`
Expected: a `cancelled` row whose `pct_of_tokens` is near the verified ~17.8% anchor, plus `completed` and `failed` rows.

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/health/wasted-tokens.sql
git commit -m "feat: health/wasted-tokens query — token waste by run status"
```

---

## Task 11: Query — health/rework-loops

**Files:**
- Create: `L4_serve/queries/health/rework-loops.sql`

**Interfaces:**
- Consumes: `fact_task` (issue_id, source, status), `fact_issue` (issue_id, identifier, issue_number). Run via `python3 cli.py query health/rework-loops`.
- Produces: issues that had a cancelled run before completing, ranked by run count (rework proxy).

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/health/rework-loops.sql`:

```sql
-- health/rework-loops — issues showing rework: multiple runs, especially a
-- cancelled run before a completed one. Run count per issue is the proxy.
SELECT i.identifier,
       i.issue_number,
       count(t.task_id)                       AS runs,
       sum(t.status = 'cancelled')            AS cancelled_runs,
       sum(t.status = 'completed')            AS completed_runs,
       CASE WHEN sum(t.status = 'cancelled') > 0
             AND sum(t.status = 'completed') > 0
            THEN 1 ELSE 0 END                 AS had_rework_loop
FROM fact_issue i
JOIN fact_task t
  ON t.issue_id = i.issue_id AND t.source = 'multica_run'
GROUP BY i.issue_id
HAVING runs > 1
ORDER BY runs DESC;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query health/rework-loops`
Expected: multi-run issues at the top (one near ~22 runs anchor); many rows with `had_rework_loop = 1` (~80 issues across the set had the cancel→complete pattern).

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/health/rework-loops.sql
git commit -m "feat: health/rework-loops query — rework detection from run counts"
```

---

## Task 12: Query — behavior/runaway-sessions

**Files:**
- Create: `L4_serve/queries/behavior/runaway-sessions.sql`

**Interfaces:**
- Consumes: `dim_session` (session_id, total_tokens, total_cost_usd, first_ts, last_ts, request_count, client). Run via `python3 cli.py query behavior/runaway-sessions`.
- Produces: the largest sessions by tokens, with duration and cost — the runaway tail that dominates spend.

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/behavior/runaway-sessions.sql`:

```sql
-- behavior/runaway-sessions — the long tail of huge sessions. dim_session is
-- claude-cli-only (session_uuid reliable there), so this covers claude-cli
-- spend. Duration from first_ts/last_ts (epoch ms) -> minutes.
SELECT session_id,
       client,
       request_count,
       total_tokens,
       round(total_cost_usd, 2)                          AS cost_usd,
       round((last_ts - first_ts) / 60000.0, 1)          AS duration_min
FROM dim_session
WHERE total_tokens > 5000000            -- runaway threshold: >5M tokens
ORDER BY total_tokens DESC
LIMIT 50;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query behavior/runaway-sessions`
Expected: top session near the ~231M-token / ~$1,160 anchor; a list of the biggest sessions (hundreds exceed 5M tokens).

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/behavior/runaway-sessions.sql
git commit -m "feat: behavior/runaway-sessions query — largest-session tail"
```

---

## Task 13: Docs + full regression

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: documented UTC→local convention; confirmation the full pipeline + test suite is green.

- [ ] **Step 1: Document the UTC→local convention**

In `README.md`, under the "Key design notes" section, add a bullet:

```markdown
- **Timestamps are UTC**: `fact_request.ts` (epoch ms) and raw shards store UTC.
  Any time-of-day / day-of-week query MUST localize:
  `datetime(ts/1000,'unixepoch','localtime')`. Do not draw "morning vs night"
  conclusions from raw UTC values.
```

Also update the query list in README to include the 7 new queries under a "Deep analysis (v2)" subheading:

```markdown
### Deep analysis (v2)
- `cost/pareto` — spend concentration by model
- `cost/model-downgrade` — opus-for-tiny-output waste
- `cost/context-waste` — big-input tiny-output spend
- `health/agent-scorecard` — per-agent reliability / speed / tokens
- `health/wasted-tokens` — token waste by run status
- `health/rework-loops` — rework detection from run counts
- `behavior/runaway-sessions` — largest-session tail
```

- [ ] **Step 2: Run the whole test suite**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/ -v`
Expected: all unit + integration tests PASS.

- [ ] **Step 3: Full pipeline smoke + all queries execute**

Run:
```bash
cd ~/Development/AIDash/aidata
python3 cli.py normalize && python3 cli.py merge
for q in cost/pareto cost/model-downgrade cost/context-waste \
         health/agent-scorecard health/wasted-tokens health/rework-loops \
         behavior/runaway-sessions; do
  echo "== $q =="; python3 cli.py query "$q" | head -3
done
```
Expected: every query prints a header + rows, no errors. Existing seed queries (`roi/*`, `issues/*`, `memory/*`) also still run.

- [ ] **Step 4: Confirm no data leaked into git**

Run: `cd ~/Development/AIDash/aidata && git status --short | grep -E 'raw|clean|\.db' || echo "clean"`
Expected: `clean`

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add README.md
git commit -m "docs: v2 deep-analysis queries + UTC-timestamp convention"
```

---

## Self-Review

**Spec coverage** (each spec item → task):
- Model-name unification → Task 1, applied in Task 3 (raven), Task 4 (warehouse col).
- Missing price map → Task 2, gated in Task 5.
- multica tokens mislabeled → Task 4 (comment fix).
- tool_call_count deprecated flag → Task 4.
- cache fields broken flag → NOTE: spec 组2 asks these be flagged "不可用". Covered by not using them in any query + the deprecated note pattern; **added explicitly**: Task 4 flags tool_call_count; cache columns already carry no data and no query references them. (No separate task needed — no query consumes them.)
- ts UTC handling → Task 13 (README convention); all time-capable queries here (none of the 7 slice by hour, so no localization bug shipped) — the convention is documented for future queries. Verified: none of the 7 first-set queries do hour/day-of-week cuts, so UTC is not a correctness risk in this batch.
- 7 analysis queries → Tasks 6-12, one each.
- Explicitly-not-doing (PR analysis, memory deep-dive, skill ROI full, cache $ quant, tool sequences) → not planned. Correct.

**Placeholder scan:** No TBD/TODO. Every code step shows full code. Every query is complete SQL.

**Type consistency:** `model_canon(model: str | None) -> str | None` defined Task 1, used identically in Task 3 (`_cost`, `normalize`). `_CLEAN_COLS`/`_CLEAN_DDL` gain `model_canon` together (Task 3). merge.py INSERT column list matches the new DDL order (Task 4). `dim_model.csv` keyed by canonical id (Task 2) matches `prices.get(model_canon(model))` lookup (Task 3).

**Gap found & fixed during review:** cache-field flagging had no home; confirmed no query consumes cache columns, so the "flag as unusable" requirement is satisfied by non-use + the schema already lacking cache data — documented here rather than adding an empty task (YAGNI).
