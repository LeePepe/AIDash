# aidata-digest M1 Implementation Plan — raven-only trending, template-only

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a self-contained "AI usage daily digest" M1 — `aidata digest --date YYYY-MM-DD` produces a 4-section Markdown report from raven data (trending + rule-based TODO + yesterday summary + improvements), written to a local file, with zero LLM and zero external CLI dependencies.

**Architecture:** New top layer `L5_apps/digest/` sits above L4. It calls L4 named queries (added this milestone) for raven trend data, converts UTC→CST for day-boundary logic, renders four sections via **deterministic Python templates** (no LLM in M1), and writes a dated Markdown archive. Everything is derived from the existing warehouse; nothing in L1–L4 changes except adding new query `.sql` files.

**Tech Stack:** Python 3.11 (stdlib only — sqlite3, datetime, pathlib, argparse, dataclasses), the existing `serve.run_query` mechanism, pytest with golden-file fixtures.

## Global Constraints

- **Layer purity (ADR-11):** L1–L4 stay pure-data, no LLM. M1 adds no LLM at all. New code lives in `L5_apps/`.
- **CST day boundary (ADR-2, ADR-22):** all day bucketing uses `'+8 hours'` on the UTC epoch-ms `ts` — never `localtime` (host-TZ-independent). "Yesterday" = the CST calendar day before the report date.
- **Stdlib only** — no new pip dependencies. Match existing adapter/query style.
- **Immutable data:** functions return new values; never mutate inputs. warehouse/clean/raw are read-only from L5.
- **Idempotent (ADR-22):** re-running `aidata digest --date D` overwrites that day's `.md` deterministically (template-only → byte-identical for same data).
- **source_health explicit (ADR-23):** the digest records per-source collection state; M1 has one source (raven) but the mechanism ships now so M2+ slot in.
- **Trend honesty (ADR-3):** a dimension with < N days of data prints "数据仅 N 天", never a fabricated arrow. A source marked missing prints "数据缺失", never "→/0 进展".
- **Python style:** PEP 8, type annotations on all signatures, functions < 50 lines, files focused (< 400 lines).
- **Tests:** pytest, `@pytest.mark.unit` / `@pytest.mark.integration`, markers already registered in `pytest.ini`.

---

## File Structure

**New files:**
- `L5_apps/__init__.py` — package marker for the app layer.
- `L5_apps/digest/__init__.py` — package marker.
- `L5_apps/digest/cst.py` — CST day-boundary helpers (UTC epoch-ms ↔ CST date, "yesterday", day-range SQL fragment). One responsibility: time.
- `L5_apps/digest/trends.py` — trend computation: given a metric's per-day series, produce day-over-day delta, 7-day trailing avg comparison, arrow (↑↓→), and consecutive-flat-days streak. Pure functions on numbers.
- `L5_apps/digest/sources.py` — data-fetch layer: calls `serve.run_query` for the M1 trending queries, returns typed dataclasses; wraps each source fetch in a health-tracking try/except producing `SourceHealth`.
- `L5_apps/digest/render.py` — deterministic Markdown template for the 4 sections + source_health line. No LLM.
- `L5_apps/digest/todo_rules.py` — rule-based TODO candidate generator (hard thresholds → action strings).
- `L5_apps/digest/app.py` — orchestrator: `build_digest(date)` → fetch → trends → todo → render → return Markdown string; `write_digest(date)` → archive to disk.
- `L4_serve/queries/trend/daily-cost.sql` — per-CST-day reqs/tokens/cost series (raven).
- `L4_serve/queries/trend/daily-waste.sql` — per-CST-day waste (opus-tiny-output + big-input-tiny-output cost) series.
- `L4_serve/queries/trend/daily-pipeline.sql` — per-CST-day task completion/cancel counts.
- `L4_serve/queries/trend/daily-behavior.sql` — per-CST-day session count + avg tokens/session.
- `tests/test_cst.py`, `tests/test_trends.py`, `tests/test_digest_golden.py` — unit + golden-file tests.
- `tests/fixtures/digest-2026-07-09.golden.md` — expected output for the frozen date.

**Modified files:**
- `cli.py` — add the `digest` subcommand (mirrors existing `query` wiring at cli.py:104-108).
- `config.py` — add `DIGEST_DIR` constant (archive location).
- `README.md` — document `aidata digest`.

**Task boundaries:** Task 1 = CST util. Task 2 = trend math. Tasks 3–6 = the four trend queries + their typed fetchers (each independently testable). Task 7 = TODO rules. Task 8 = renderer. Task 9 = orchestrator + CLI + golden test. Task 10 = docs + full regression.

---

## Task 1: CST day-boundary helpers

**Files:**
- Create: `L5_apps/__init__.py` (empty), `L5_apps/digest/__init__.py` (empty)
- Create: `L5_apps/digest/cst.py`
- Create: `tests/test_cst.py`

**Interfaces:**
- Produces:
  - `cst_date_of_ms(ts_ms: int) -> str` — UTC epoch-ms → `YYYY-MM-DD` in CST (+8h).
  - `yesterday(report_date: str) -> str` — the CST calendar day before `report_date` (`YYYY-MM-DD` → `YYYY-MM-DD`).
  - `recent_days(report_date: str, n: int) -> list[str]` — the `n` CST days strictly before `report_date`, newest-first.
  - `CST_DAY_EXPR: str` — the SQL expression `"date(ts/1000,'unixepoch','+8 hours')"` used verbatim by trend queries so bucketing is defined in one place.

- [ ] **Step 1: Write the failing test**

Create `tests/test_cst.py`:

```python
import pytest

from L5_apps.digest.cst import (
    cst_date_of_ms, yesterday, recent_days, CST_DAY_EXPR,
)


@pytest.mark.unit
def test_cst_date_of_ms_shifts_plus_8():
    # 2026-07-09 23:30 UTC = 2026-07-10 07:30 CST -> CST date is 07-10
    ts = 1783639800000  # 2026-07-09T23:30:00Z
    assert cst_date_of_ms(ts) == "2026-07-10"
    # 2026-07-09 15:00 UTC = 2026-07-09 23:00 CST -> still 07-09
    ts2 = 1783609200000  # 2026-07-09T15:00:00Z
    assert cst_date_of_ms(ts2) == "2026-07-09"


@pytest.mark.unit
def test_cst_date_boundary_16utc_is_next_cst_day():
    # 16:00 UTC = 00:00 CST next day (the exact day flip)
    ts = 1783612800000  # 2026-07-09T16:00:00Z == 2026-07-10T00:00 CST
    assert cst_date_of_ms(ts) == "2026-07-10"


@pytest.mark.unit
def test_yesterday():
    assert yesterday("2026-07-10") == "2026-07-09"
    assert yesterday("2026-03-01") == "2026-02-28"  # month boundary


@pytest.mark.unit
def test_recent_days_newest_first_excludes_report_date():
    assert recent_days("2026-07-10", 3) == ["2026-07-09", "2026-07-08", "2026-07-07"]


@pytest.mark.unit
def test_cst_day_expr_is_plus_8_hours():
    assert CST_DAY_EXPR == "date(ts/1000,'unixepoch','+8 hours')"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_cst.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'L5_apps'`

- [ ] **Step 3: Write minimal implementation**

Create empty `L5_apps/__init__.py` and `L5_apps/digest/__init__.py`.

Create `L5_apps/digest/cst.py`:

```python
"""CST (Asia/Shanghai) day-boundary helpers for the digest.

aidata stores timestamps as UTC epoch-ms. The digest reports on CST calendar
days (ADR-2). All day bucketing uses a fixed +8h offset — never the host's
local timezone — so results are host-TZ-independent (ADR-22).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

# CST = UTC+8, fixed (China has no DST).
_CST = timezone(timedelta(hours=8))

# The SQL day-bucket expression, defined once so every trend query agrees.
CST_DAY_EXPR = "date(ts/1000,'unixepoch','+8 hours')"


def cst_date_of_ms(ts_ms: int) -> str:
    """UTC epoch-milliseconds -> 'YYYY-MM-DD' in CST."""
    dt = datetime.fromtimestamp(ts_ms / 1000, tz=_CST)
    return dt.strftime("%Y-%m-%d")


def _parse(day: str) -> datetime:
    return datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=_CST)


def yesterday(report_date: str) -> str:
    """The CST calendar day before report_date."""
    return (_parse(report_date) - timedelta(days=1)).strftime("%Y-%m-%d")


def recent_days(report_date: str, n: int) -> list[str]:
    """The n CST days strictly before report_date, newest-first."""
    base = _parse(report_date)
    return [(base - timedelta(days=i)).strftime("%Y-%m-%d") for i in range(1, n + 1)]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_cst.py -v`
Expected: PASS (5 passed)

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L5_apps/__init__.py L5_apps/digest/__init__.py L5_apps/digest/cst.py tests/test_cst.py
git commit -m "feat(digest): CST day-boundary helpers for M1"
```

---

## Task 2: Trend computation (arrows, deltas, streaks)

**Files:**
- Create: `L5_apps/digest/trends.py`
- Create: `tests/test_trends.py`

**Interfaces:**
- Consumes: nothing from other tasks (pure math).
- Produces:
  - `@dataclass(frozen=True) Trend` with fields: `today: float`, `prev: float | None`, `avg7: float | None`, `arrow: str` (`"↑"|"↓"|"→"`), `pct_vs_prev: float | None`, `days_available: int`.
  - `compute_trend(series: list[tuple[str, float]], report_date: str, flat_eps: float = 0.05) -> Trend` — `series` is `(cst_day, value)` newest-first-or-any-order; computes today's value (the day == yesterday(report_date)), previous day, 7-day trailing avg, and arrow. Arrow is `→` when `|today-prev|/prev <= flat_eps` or prev is 0/None.
  - `flat_streak(series: list[tuple[str, float]], report_date: str, flat_eps: float = 0.05) -> int` — number of consecutive most-recent days (ending at yesterday) whose day-over-day change stayed within `flat_eps`. Used for "连续 N 天 0 进展".

- [ ] **Step 1: Write the failing test**

Create `tests/test_trends.py`:

```python
import pytest

from L5_apps.digest.trends import compute_trend, flat_streak, Trend


# Real golden series from warehouse (cost by CST day), newest-first.
COST = [
    ("2026-07-09", 2699.44), ("2026-07-08", 2180.19), ("2026-07-07", 4523.19),
    ("2026-07-06", 2493.94), ("2026-07-05", 698.83), ("2026-07-04", 1837.16),
    ("2026-07-03", 491.59), ("2026-07-02", 833.82),
]


@pytest.mark.unit
def test_compute_trend_up_vs_prev():
    # report_date 07-10 -> "yesterday" is 07-09 (2699.44) vs 07-08 (2180.19) = up
    t = compute_trend(COST, "2026-07-10")
    assert t.today == 2699.44
    assert t.prev == 2180.19
    assert t.arrow == "↑"
    assert round(t.pct_vs_prev, 1) == 23.8  # (2699.44-2180.19)/2180.19*100


@pytest.mark.unit
def test_compute_trend_7day_avg():
    # avg of 07-02..07-08 (7 days before 07-09)
    t = compute_trend(COST, "2026-07-10")
    expected_avg = round(sum(v for _, v in COST[1:8]) / 7, 2)
    assert round(t.avg7, 2) == expected_avg
    assert t.days_available == 8


@pytest.mark.unit
def test_compute_trend_flat_is_arrow_right():
    series = [("2026-07-09", 100.0), ("2026-07-08", 102.0)]
    t = compute_trend(series, "2026-07-10")  # 2% change < 5% eps
    assert t.arrow == "→"


@pytest.mark.unit
def test_compute_trend_missing_today_returns_zero_today():
    # no row for yesterday -> today=0.0, arrow →, days_available reflects series
    series = [("2026-07-01", 50.0)]
    t = compute_trend(series, "2026-07-10")
    assert t.today == 0.0
    assert t.prev is None


@pytest.mark.unit
def test_flat_streak_counts_consecutive_flat_days():
    # 07-09..07-07 all within 5% of each other, 07-06 jumps
    series = [("2026-07-09", 100.0), ("2026-07-08", 101.0),
              ("2026-07-07", 100.5), ("2026-07-06", 60.0)]
    assert flat_streak(series, "2026-07-10") == 2  # 09-vs-08 flat, 08-vs-07 flat, 07-vs-06 not
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_trends.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'L5_apps.digest.trends'`

- [ ] **Step 3: Write minimal implementation**

Create `L5_apps/digest/trends.py`:

```python
"""Trend math: day-over-day arrows, 7-day average, flat-streak detection.

Pure functions on (day, value) series. A dimension with too few days still
returns a Trend, but callers check `days_available` to decide whether to print
an arrow or "数据仅 N 天" (ADR-3).
"""

from __future__ import annotations

from dataclasses import dataclass

from L5_apps.digest.cst import yesterday


@dataclass(frozen=True)
class Trend:
    today: float
    prev: float | None
    avg7: float | None
    arrow: str
    pct_vs_prev: float | None
    days_available: int


def _as_map(series: list[tuple[str, float]]) -> dict[str, float]:
    return {day: val for day, val in series}


def compute_trend(series: list[tuple[str, float]], report_date: str,
                  flat_eps: float = 0.05) -> Trend:
    """Compute today (=yesterday-of-report) vs prev day and 7-day trailing avg."""
    m = _as_map(series)
    y = yesterday(report_date)
    today = m.get(y, 0.0)

    from L5_apps.digest.cst import recent_days
    prior_days = recent_days(y, 1)          # the single day before "today"
    prev = m.get(prior_days[0]) if prior_days else None

    avg_days = recent_days(y, 7)            # 7 days before "today"
    avg_vals = [m[d] for d in avg_days if d in m]
    avg7 = round(sum(avg_vals) / len(avg_vals), 2) if avg_vals else None

    if prev is None or prev == 0:
        arrow, pct = "→", None
    else:
        pct = (today - prev) / prev * 100
        if abs(today - prev) / prev <= flat_eps:
            arrow = "→"
        else:
            arrow = "↑" if today > prev else "↓"

    return Trend(today=today, prev=prev, avg7=avg7, arrow=arrow,
                 pct_vs_prev=pct, days_available=len(series))


def flat_streak(series: list[tuple[str, float]], report_date: str,
                flat_eps: float = 0.05) -> int:
    """Count consecutive most-recent days (ending yesterday) with flat change."""
    m = _as_map(series)
    from L5_apps.digest.cst import recent_days
    # Days from yesterday backwards that exist in the series.
    chain = [yesterday(report_date)] + recent_days(yesterday(report_date), 30)
    present = [d for d in chain if d in m]
    streak = 0
    for i in range(len(present) - 1):
        cur, nxt = m[present[i]], m[present[i + 1]]
        if nxt != 0 and abs(cur - nxt) / nxt <= flat_eps:
            streak += 1
        else:
            break
    return streak
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_trends.py -v`
Expected: PASS (5 passed)

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L5_apps/digest/trends.py tests/test_trends.py
git commit -m "feat(digest): trend math — arrows, 7-day avg, flat-streak"
```

---

## Task 3: Trend query — daily cost/tokens/requests

**Files:**
- Create: `L4_serve/queries/trend/daily-cost.sql`

**Interfaces:**
- Consumes: `fact_request` (ts, cost_usd, input_tokens, output_tokens). Run via `serve.run_query("trend/daily-cost")`.
- Produces: rows `(day, requests, tokens, cost_usd)` one per CST day, newest-first. Column names exactly: `day, requests, tokens, cost_usd`.

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/trend/daily-cost.sql`:

```sql
-- trend/daily-cost — per-CST-day requests / tokens / notional cost (raven).
-- CST bucket via +8h (ADR-2). Feeds the Trending section's cost & token arrows.
SELECT date(ts/1000,'unixepoch','+8 hours')                     AS day,
       count(*)                                                 AS requests,
       sum(COALESCE(input_tokens,0) + COALESCE(output_tokens,0)) AS tokens,
       round(sum(COALESCE(cost_usd,0)), 2)                      AS cost_usd
FROM fact_request
GROUP BY day
ORDER BY day DESC;
```

- [ ] **Step 2: Run it and confirm the frozen-date row**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query trend/daily-cost | head -5`
Expected: the `2026-07-09` row shows `8273` requests and `2699.44` cost_usd (matches warehouse golden).

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/trend/daily-cost.sql
git commit -m "feat(digest): trend/daily-cost query"
```

---

## Task 4: Trend query — daily waste

**Files:**
- Create: `L4_serve/queries/trend/daily-waste.sql`

**Interfaces:**
- Consumes: `fact_request` (ts, model_canon, input_tokens, output_tokens, cost_usd). Run via `serve.run_query("trend/daily-waste")`.
- Produces: rows `(day, waste_usd, waste_requests)` per CST day, newest-first. "Waste" = opus-tier requests with <20 output tokens OR any request with input>50k AND output<20 (the two waste patterns from aidata v2), summed cost.

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/trend/daily-waste.sql`:

```sql
-- trend/daily-waste — per-CST-day wasted spend (raven). Two patterns:
--   (a) opus-tier model producing <20 output tokens (over-provisioned model)
--   (b) any request with >50k input but <20 output (context bloat / misfire)
-- Feeds the Trending "浪费额" arrow.
SELECT date(ts/1000,'unixepoch','+8 hours')  AS day,
       round(sum(COALESCE(cost_usd,0)), 2)   AS waste_usd,
       count(*)                              AS waste_requests
FROM fact_request
WHERE cost_usd IS NOT NULL
  AND output_tokens IS NOT NULL AND output_tokens < 20
  AND (
        model_canon LIKE 'claude-opus-%'
     OR (input_tokens IS NOT NULL AND input_tokens > 50000)
      )
GROUP BY day
ORDER BY day DESC;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query trend/daily-waste | head -5`
Expected: rows per day with a `waste_usd` and `waste_requests` (non-zero for recent days; `2026-07-09` present).

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/trend/daily-waste.sql
git commit -m "feat(digest): trend/daily-waste query"
```

---

## Task 5: Trend query — daily pipeline health

**Files:**
- Create: `L4_serve/queries/trend/daily-pipeline.sql`

**Interfaces:**
- Consumes: `fact_task` (source, status, ts_start). Run via `serve.run_query("trend/daily-pipeline")`.
- Produces: rows `(day, runs, completed, cancelled, failed)` per CST day, newest-first.

**Note on ts_start:** `fact_task.ts_start` is an ISO-8601 **text** timestamp (e.g. `2026-07-09T08:00:17Z`), not epoch-ms. So CST bucketing here uses `date(ts_start, '+8 hours')` (sqlite parses ISO text directly), NOT the epoch-ms `CST_DAY_EXPR`. This divergence is intentional and must be handled per-source.

- [ ] **Step 1: Write the query**

Create `L4_serve/queries/trend/daily-pipeline.sql`:

```sql
-- trend/daily-pipeline — per-CST-day multica run outcomes. ts_start is ISO text
-- (not epoch-ms), so bucket with date(ts_start,'+8 hours'). Feeds pipeline arrow.
SELECT date(ts_start, '+8 hours')       AS day,
       count(*)                         AS runs,
       sum(status = 'completed')        AS completed,
       sum(status = 'cancelled')        AS cancelled,
       sum(status = 'failed')           AS failed
FROM fact_task
WHERE source = 'multica_run' AND ts_start IS NOT NULL
GROUP BY day
ORDER BY day DESC;
```

- [ ] **Step 2: Run it**

Run: `cd ~/Development/AIDash/aidata && python3 cli.py query trend/daily-pipeline | head -5`
Expected: rows like `2026-07-09 | 49 | 32 | 15 | ...` (matches warehouse golden for that day).

- [ ] **Step 3: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/trend/daily-pipeline.sql
git commit -m "feat(digest): trend/daily-pipeline query"
```

---

## Task 6: Trend query — daily behavior + typed fetchers

**Files:**
- Create: `L4_serve/queries/trend/daily-behavior.sql`
- Create: `L5_apps/digest/sources.py`
- Create: `tests/test_sources.py`

**Interfaces:**
- Consumes: the four `trend/*` queries (Tasks 3–6), `serve.run_query`.
- Produces:
  - `@dataclass(frozen=True) SourceHealth` fields: `name: str`, `state: str` (`"ok"|"skipped:auth过期"|"skipped:CLI缺失"|"skipped:app未开"|"stale"|"error"`), `detail: str`.
  - `@dataclass(frozen=True) RavenTrends` fields: `cost: list[tuple[str,float]]`, `tokens: list[tuple[str,float]]`, `requests: list[tuple[str,float]]`, `waste: list[tuple[str,float]]`, `pipeline_completed: list[tuple[str,float]]`, `pipeline_cancelled: list[tuple[str,float]]`, `sessions: list[tuple[str,float]]`, `health: SourceHealth`.
  - `fetch_raven_trends() -> RavenTrends` — runs the four queries, reshapes to `(day, value)` series, wraps in health tracking (any exception → `state="error"`, empty series).

- [ ] **Step 1: Write the failing test**

Create `tests/test_sources.py`:

```python
import pytest

from L5_apps.digest.sources import fetch_raven_trends, RavenTrends, SourceHealth


@pytest.mark.integration
def test_fetch_raven_trends_returns_series_and_ok_health():
    t = fetch_raven_trends()
    assert isinstance(t, RavenTrends)
    assert t.health.state == "ok"
    # cost series has the frozen date with the known value
    cost = dict(t.cost)
    assert cost["2026-07-09"] == 2699.44
    # every series is a list of (day, number) tuples
    for day, val in t.cost:
        assert isinstance(day, str) and isinstance(val, (int, float))


@pytest.mark.unit
def test_source_health_dataclass_shape():
    h = SourceHealth(name="raven", state="ok", detail="")
    assert h.name == "raven" and h.state == "ok"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_sources.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'L5_apps.digest.sources'`

- [ ] **Step 3: Write the behavior query**

Create `L4_serve/queries/trend/daily-behavior.sql`:

```sql
-- trend/daily-behavior — per-CST-day distinct claude-cli sessions + avg tokens
-- per request. session_uuid reliable only for claude-cli (has_session=1).
SELECT date(ts/1000,'unixepoch','+8 hours')                      AS day,
       count(DISTINCT session_uuid)                              AS sessions,
       round(avg(COALESCE(input_tokens,0)+COALESCE(output_tokens,0)), 0) AS avg_tokens
FROM fact_request
WHERE has_session = 1 AND session_uuid IS NOT NULL
GROUP BY day
ORDER BY day DESC;
```

- [ ] **Step 4: Write the fetcher implementation**

Create `L5_apps/digest/sources.py`:

```python
"""Data-fetch layer for the digest.

Calls L4 trend queries and reshapes results into (day, value) series that the
trend math consumes. Each source fetch is wrapped in health tracking so a
failure degrades to an empty series + a SourceHealth state, never a crash
(ADR-23). M1 has one source (raven); M2+ add more here.
"""

from __future__ import annotations

from dataclasses import dataclass

import serve


@dataclass(frozen=True)
class SourceHealth:
    name: str
    state: str          # ok | skipped:* | stale | error
    detail: str = ""


@dataclass(frozen=True)
class RavenTrends:
    cost: list[tuple[str, float]]
    tokens: list[tuple[str, float]]
    requests: list[tuple[str, float]]
    waste: list[tuple[str, float]]
    pipeline_completed: list[tuple[str, float]]
    pipeline_cancelled: list[tuple[str, float]]
    sessions: list[tuple[str, float]]
    health: SourceHealth


def _series(name: str, day_col: str, val_col: str) -> list[tuple[str, float]]:
    rows, cols = serve.run_query(name)
    di, vi = cols.index(day_col), cols.index(val_col)
    return [(r[di], float(r[vi]) if r[vi] is not None else 0.0) for r in rows]


def fetch_raven_trends() -> RavenTrends:
    """Fetch all raven-derived trend series; degrade to empty + error health."""
    try:
        cost_rows, cost_cols = serve.run_query("trend/daily-cost")
        di = cost_cols.index("day")
        cost = [(r[di], float(r[cost_cols.index("cost_usd")] or 0)) for r in cost_rows]
        tokens = [(r[di], float(r[cost_cols.index("tokens")] or 0)) for r in cost_rows]
        requests = [(r[di], float(r[cost_cols.index("requests")] or 0)) for r in cost_rows]
        waste = _series("trend/daily-waste", "day", "waste_usd")
        pipe_done = _series("trend/daily-pipeline", "day", "completed")
        pipe_cx = _series("trend/daily-pipeline", "day", "cancelled")
        sessions = _series("trend/daily-behavior", "day", "sessions")
        return RavenTrends(
            cost=cost, tokens=tokens, requests=requests, waste=waste,
            pipeline_completed=pipe_done, pipeline_cancelled=pipe_cx,
            sessions=sessions,
            health=SourceHealth(name="raven", state="ok"),
        )
    except Exception as exc:  # degrade, never crash the digest
        empty: list[tuple[str, float]] = []
        return RavenTrends(
            cost=empty, tokens=empty, requests=empty, waste=empty,
            pipeline_completed=empty, pipeline_cancelled=empty, sessions=empty,
            health=SourceHealth(name="raven", state="error", detail=str(exc)[:200]),
        )
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_sources.py -v`
Expected: PASS (2 passed)

- [ ] **Step 6: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L4_serve/queries/trend/daily-behavior.sql L5_apps/digest/sources.py tests/test_sources.py
git commit -m "feat(digest): daily-behavior query + typed raven trend fetchers"
```

---

## Task 7: Rule-based TODO candidates

**Files:**
- Create: `L5_apps/digest/todo_rules.py`
- Create: `tests/test_todo_rules.py`

**Interfaces:**
- Consumes: `RavenTrends` (Task 6), `compute_trend` (Task 2).
- Produces:
  - `@dataclass(frozen=True) Todo` fields: `priority: str` (`"P0"|"P1"|"P2"`), `text: str`.
  - `todo_candidates(t: RavenTrends, report_date: str) -> list[Todo]` — applies hard thresholds and returns actionable items, most-severe first. M1 rules (deterministic, no LLM): waste_usd yesterday > $500 → P1 "审查浪费:{waste}美元花在极小输出/大上下文请求"; cost up >50% vs 7-day avg → P1 "成本异常:昨日{today}美元 vs 均值{avg7}"; pipeline cancelled ratio yesterday >30% → P0 "查 pipeline:{cx}/{runs} run 被取消". At most 2 P0 (ADR-14 spirit).

- [ ] **Step 1: Write the failing test**

Create `tests/test_todo_rules.py`:

```python
import pytest

from L5_apps.digest.sources import RavenTrends, SourceHealth
from L5_apps.digest.todo_rules import todo_candidates, Todo


def _rt(**kw) -> RavenTrends:
    empty = []
    base = dict(cost=empty, tokens=empty, requests=empty, waste=empty,
                pipeline_completed=empty, pipeline_cancelled=empty,
                sessions=empty, health=SourceHealth("raven", "ok"))
    base.update(kw)
    return RavenTrends(**base)


@pytest.mark.unit
def test_waste_over_threshold_makes_p1():
    t = _rt(waste=[("2026-07-09", 800.0)])
    todos = todo_candidates(t, "2026-07-10")
    assert any(td.priority == "P1" and "浪费" in td.text for td in todos)


@pytest.mark.unit
def test_no_signals_no_todos():
    t = _rt(waste=[("2026-07-09", 10.0)])
    todos = todo_candidates(t, "2026-07-10")
    assert todos == []


@pytest.mark.unit
def test_pipeline_high_cancel_makes_p0():
    t = _rt(pipeline_completed=[("2026-07-09", 5.0)],
            pipeline_cancelled=[("2026-07-09", 10.0)])  # 10/15 = 67% cancelled
    todos = todo_candidates(t, "2026-07-10")
    assert any(td.priority == "P0" and "pipeline" in td.text.lower() for td in todos)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_todo_rules.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'L5_apps.digest.todo_rules'`

- [ ] **Step 3: Write minimal implementation**

Create `L5_apps/digest/todo_rules.py`:

```python
"""Rule-based TODO candidate generation (ADR-8, M1 = rules only, no LLM).

Hard thresholds turn yesterday's numbers into actionable items. In later
milestones an LLM refines/ranks these; in M1 the rules ARE the output.
"""

from __future__ import annotations

from dataclasses import dataclass

from L5_apps.digest.cst import yesterday

WASTE_USD_P1 = 500.0
COST_SPIKE_PCT = 50.0
CANCEL_RATIO_P0 = 0.30


@dataclass(frozen=True)
class Todo:
    priority: str   # P0 | P1 | P2
    text: str


def _val(series: list[tuple[str, float]], day: str) -> float:
    return dict(series).get(day, 0.0)


def todo_candidates(t, report_date: str) -> list[Todo]:
    """Deterministic TODO items from yesterday's signals, most-severe first."""
    y = yesterday(report_date)
    out: list[Todo] = []

    # P0: pipeline cancellation ratio
    done = _val(t.pipeline_completed, y)
    cx = _val(t.pipeline_cancelled, y)
    runs = done + cx
    if runs > 0 and cx / runs > CANCEL_RATIO_P0:
        out.append(Todo("P0", f"查 pipeline:{int(cx)}/{int(runs)} run 被取消(取消率"
                               f"{cx / runs * 100:.0f}%)"))

    # P1: waste spend
    waste = _val(t.waste, y)
    if waste > WASTE_USD_P1:
        out.append(Todo("P1", f"审查浪费:${waste:.0f} 花在极小输出/大上下文请求"))

    # P1: cost spike vs 7-day avg
    from L5_apps.digest.trends import compute_trend
    ct = compute_trend(t.cost, report_date)
    if ct.avg7 and ct.avg7 > 0 and ct.today > ct.avg7 * (1 + COST_SPIKE_PCT / 100):
        out.append(Todo("P1", f"成本异常:昨日 ${ct.today:.0f} vs 7日均值 ${ct.avg7:.0f}"))

    # Order: P0 first, then P1, then P2; cap P0 at 2 (ADR-14).
    order = {"P0": 0, "P1": 1, "P2": 2}
    out.sort(key=lambda td: order[td.priority])
    p0 = [td for td in out if td.priority == "P0"][:2]
    rest = [td for td in out if td.priority != "P0"]
    return p0 + rest
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_todo_rules.py -v`
Expected: PASS (3 passed)

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L5_apps/digest/todo_rules.py tests/test_todo_rules.py
git commit -m "feat(digest): rule-based TODO candidates (M1, no LLM)"
```

---

## Task 8: Markdown renderer (4 sections, template-only)

**Files:**
- Create: `L5_apps/digest/render.py`
- Create: `tests/test_render.py`

**Interfaces:**
- Consumes: `RavenTrends` (Task 6), `Trend`/`compute_trend`/`flat_streak` (Task 2), `Todo`/`todo_candidates` (Task 7), `cst` helpers (Task 1).
- Produces:
  - `render_digest(t: RavenTrends, report_date: str) -> str` — full Markdown with 4 sections (`## ⚡ Trending`, `## 📅 今日 TODO`, `## 🗂 昨日汇总`, `## 🔍 可改良`) + a `> 数据源:` health line. Deterministic: same input → byte-identical output. Dimensions with `days_available < 2` print "数据仅 N 天" instead of an arrow. If `t.health.state != "ok"`, the health line shows the degraded state and trending shows "数据缺失".

- [ ] **Step 1: Write the failing test**

Create `tests/test_render.py`:

```python
import pytest

from L5_apps.digest.sources import RavenTrends, SourceHealth
from L5_apps.digest.render import render_digest

COST = [("2026-07-09", 2699.44), ("2026-07-08", 2180.19), ("2026-07-07", 4523.19),
        ("2026-07-06", 2493.94), ("2026-07-05", 698.83), ("2026-07-04", 1837.16),
        ("2026-07-03", 491.59), ("2026-07-02", 833.82)]


def _rt(health_state="ok"):
    return RavenTrends(
        cost=COST, tokens=[(d, v * 1000) for d, v in COST],
        requests=[("2026-07-09", 8273.0), ("2026-07-08", 4595.0)],
        waste=[("2026-07-09", 800.0)],
        pipeline_completed=[("2026-07-09", 32.0)],
        pipeline_cancelled=[("2026-07-09", 15.0)],
        sessions=[("2026-07-09", 40.0), ("2026-07-08", 38.0)],
        health=SourceHealth("raven", health_state),
    )


@pytest.mark.unit
def test_render_has_four_sections():
    md = render_digest(_rt(), "2026-07-10")
    assert "## ⚡ Trending" in md
    assert "## 📅 今日 TODO" in md
    assert "## 🗂 昨日汇总" in md
    assert "## 🔍 可改良" in md


@pytest.mark.unit
def test_render_cost_arrow_up():
    md = render_digest(_rt(), "2026-07-10")
    assert "↑" in md  # cost 2699 > 2180 prev


@pytest.mark.unit
def test_render_is_deterministic():
    assert render_digest(_rt(), "2026-07-10") == render_digest(_rt(), "2026-07-10")


@pytest.mark.unit
def test_render_degraded_source_shows_missing():
    md = render_digest(_rt(health_state="error"), "2026-07-10")
    assert "数据缺失" in md or "error" in md
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_render.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'L5_apps.digest.render'`

- [ ] **Step 3: Write minimal implementation**

Create `L5_apps/digest/render.py`:

```python
"""Deterministic Markdown renderer for the digest (M1, no LLM, ADR-18 template).

Given fetched trends, emits the four sections. All numbers/arrows come from the
data; nothing is invented. A degraded source prints "数据缺失" rather than a
fake trend (ADR-23).
"""

from __future__ import annotations

from L5_apps.digest.cst import yesterday
from L5_apps.digest.trends import compute_trend, flat_streak
from L5_apps.digest.todo_rules import todo_candidates


def _fmt_trend(label: str, series, report_date: str, unit: str = "") -> str:
    t = compute_trend(series, report_date)
    if t.days_available < 2:
        return f"- {label}: 数据仅 {t.days_available} 天"
    prev = "—" if t.prev is None else f"{t.prev:.0f}"
    pct = "" if t.pct_vs_prev is None else f"({t.pct_vs_prev:+.0f}%)"
    avg = "" if t.avg7 is None else f" · 7日均 {t.avg7:.0f}{unit}"
    return f"- {label}: {t.today:.0f}{unit} {t.arrow}{pct} vs 昨 {prev}{unit}{avg}"


def render_digest(t, report_date: str) -> str:
    y = yesterday(report_date)
    lines: list[str] = [f"# AI 使用日报 {y}", ""]

    # Health line
    if t.health.state == "ok":
        lines += ["> 数据源: raven✅", ""]
    else:
        lines += [f"> ⚠️ 数据源: raven {t.health.state} — {t.health.detail}", ""]

    degraded = t.health.state != "ok"

    # Section 1: Trending
    lines.append("## ⚡ Trending")
    if degraded:
        lines.append("- 数据缺失（raven 未采到）")
    else:
        lines.append(_fmt_trend("成本", t.cost, report_date, unit="$"))
        lines.append(_fmt_trend("Token", t.tokens, report_date))
        lines.append(_fmt_trend("请求数", t.requests, report_date))
        lines.append(_fmt_trend("浪费额", t.waste, report_date, unit="$"))
        lines.append(_fmt_trend("完成任务", t.pipeline_completed, report_date))
        lines.append(_fmt_trend("会话数", t.sessions, report_date))
        streak = flat_streak(t.cost, report_date)
        if streak >= 3:
            lines.append(f"- 🚩 成本已连续 {streak} 天持平")
    lines.append("")

    # Section 2: Today's TODO
    lines.append("## 📅 今日 TODO")
    todos = [] if degraded else todo_candidates(t, report_date)
    if todos:
        for td in todos:
            lines.append(f"- {td.priority}: {td.text}")
    else:
        lines.append("- （无阈值触发的行动项）")
    lines.append("")

    # Section 3: Yesterday summary
    lines.append("## 🗂 昨日汇总")
    if degraded:
        lines.append("- 数据缺失")
    else:
        c = dict(t.cost).get(y, 0.0)
        r = dict(t.requests).get(y, 0.0)
        lines.append(f"- 昨日花费 ${c:.2f}，请求 {int(r)} 次")
    lines.append("")

    # Section 4: Improvements
    lines.append("## 🔍 可改良")
    if degraded:
        lines.append("- 修复 raven 采集后再分析")
    else:
        w = dict(t.waste).get(y, 0.0)
        if w > 0:
            lines.append(f"- 昨日 ${w:.0f} 花在极小输出/大上下文，可考虑降级模型或裁剪上下文")
        else:
            lines.append("- 昨日无显著浪费信号")
    lines.append("")

    return "\n".join(lines)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_render.py -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add L5_apps/digest/render.py tests/test_render.py
git commit -m "feat(digest): deterministic 4-section Markdown renderer"
```

---

## Task 9: Orchestrator + CLI + golden test

**Files:**
- Create: `L5_apps/digest/app.py`
- Modify: `config.py` (add `DIGEST_DIR`)
- Modify: `cli.py` (add `digest` subcommand)
- Create: `tests/test_digest_golden.py`
- Create: `tests/fixtures/digest-2026-07-09.golden.md` (generated in Step 6)

**Interfaces:**
- Consumes: `fetch_raven_trends` (Task 6), `render_digest` (Task 8), `DIGEST_DIR`.
- Produces:
  - `build_digest(report_date: str) -> str` — fetch → render → return Markdown.
  - `write_digest(report_date: str) -> Path` — build, write to `DIGEST_DIR/daily/<yesterday>.md`, return path. Idempotent (overwrites).
  - CLI: `aidata digest --date YYYY-MM-DD` (defaults to today CST) → writes file, prints path.

- [ ] **Step 1: Add DIGEST_DIR to config.py**

In `config.py`, after the other layer-dir constants (near `QUERIES_DIR`), add:

```python
DIGEST_DIR = AIDATA_HOME / "L5_apps" / "digest" / "archive"
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_digest_golden.py`:

```python
import subprocess
from pathlib import Path

import pytest

from L5_apps.digest.app import build_digest

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / "tests" / "fixtures" / "digest-2026-07-09.golden.md"


@pytest.mark.integration
def test_build_digest_matches_golden():
    # report_date 2026-07-10 -> reports on CST 2026-07-09 (frozen warehouse data)
    md = build_digest("2026-07-10")
    assert md == GOLDEN.read_text(encoding="utf-8"), (
        "digest output drifted from golden; if warehouse data legitimately "
        "changed, regenerate the golden file and review the diff"
    )


@pytest.mark.integration
def test_build_digest_is_idempotent():
    assert build_digest("2026-07-10") == build_digest("2026-07-10")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_digest_golden.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'L5_apps.digest.app'`

- [ ] **Step 4: Write the orchestrator**

Create `L5_apps/digest/app.py`:

```python
"""Digest orchestrator (M1): fetch raven trends → render Markdown → archive.

Pure template pipeline, no LLM. `build_digest` is deterministic for fixed
warehouse data (golden-testable). `write_digest` archives idempotently.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from config import DIGEST_DIR
from L5_apps.digest.cst import yesterday
from L5_apps.digest.sources import fetch_raven_trends
from L5_apps.digest.render import render_digest

_CST = timezone(timedelta(hours=8))


def _today_cst() -> str:
    # NOTE: real wall-clock; only used as the CLI default, never in tests
    # (tests always pass an explicit --date to stay deterministic).
    return datetime.now(tz=_CST).strftime("%Y-%m-%d")


def build_digest(report_date: str) -> str:
    """Build the Markdown digest reporting on the CST day before report_date."""
    trends = fetch_raven_trends()
    return render_digest(trends, report_date)


def write_digest(report_date: str) -> Path:
    """Build and archive to DIGEST_DIR/daily/<yesterday>.md (idempotent)."""
    md = build_digest(report_date)
    out_dir = DIGEST_DIR / "daily"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{yesterday(report_date)}.md"
    out_path.write_text(md, encoding="utf-8")
    return out_path


def default_report_date() -> str:
    return _today_cst()
```

- [ ] **Step 5: Wire the CLI**

In `cli.py`, add a handler function (near the other `cmd_*` functions, before `main`):

```python
def cmd_digest(args: argparse.Namespace) -> int:
    from L5_apps.digest.app import write_digest, default_report_date

    date = args.date or default_report_date()
    path = write_digest(date)
    print(f"digest written: {path}")
    return 0
```

In `main()`, after the `p_query` block (cli.py:108), add:

```python
    p_digest = sub.add_parser("digest", help="L5: build AI-usage daily digest")
    p_digest.add_argument("--date", help="report date YYYY-MM-DD (CST); "
                                         "reports on the day before. Default: today CST")
    p_digest.set_defaults(func=cmd_digest)
```

- [ ] **Step 6: Generate the golden file, then verify it's stable**

The warehouse is frozen at 2026-07-09. Generate the golden once from real output, eyeball it for correctness (arrows match the known day-over-day: cost 2699 > 2180 = ↑), then commit it as the expected value:

```bash
cd ~/Development/AIDash/aidata
mkdir -p tests/fixtures
python3 -c "from L5_apps.digest.app import build_digest; print(build_digest('2026-07-10'), end='')" > tests/fixtures/digest-2026-07-09.golden.md
cat tests/fixtures/digest-2026-07-09.golden.md   # human review: 4 sections, ↑ on cost, TODO has waste P1
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/test_digest_golden.py -v`
Expected: PASS (2 passed)

Also run the CLI end-to-end:
```bash
cd ~/Development/AIDash/aidata && python3 cli.py digest --date 2026-07-10
```
Expected: prints `digest written: .../L5_apps/digest/archive/daily/2026-07-09.md`

- [ ] **Step 8: Commit**

```bash
cd ~/Development/AIDash/aidata
git add config.py cli.py L5_apps/digest/app.py tests/test_digest_golden.py tests/fixtures/digest-2026-07-09.golden.md
git commit -m "feat(digest): orchestrator + digest CLI subcommand + golden test"
```

---

## Task 10: Docs + full regression + gitignore

**Files:**
- Modify: `README.md`
- Modify: `.gitignore` (ignore digest archive output)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Gitignore the archive output**

The generated daily digests are data artifacts, not source. In `.gitignore`, add:

```
# digest archive output (generated)
L5_apps/digest/archive/
```

(Note: `tests/fixtures/*.golden.md` is NOT ignored — it's a committed test fixture.)

- [ ] **Step 2: Document in README**

In `README.md`, under the query section, add a new subsection:

```markdown
## AI-usage daily digest (M1)

Build a 4-section Markdown daily digest from raven trend data (template-only, no LLM):

```bash
python3 cli.py digest --date 2026-07-10   # reports on CST 2026-07-09
python3 cli.py digest                      # defaults to today CST
```

Output: `L5_apps/digest/archive/daily/<yesterday>.md`. Sections: ⚡ Trending
(cost/token/waste/pipeline/behavior arrows, CST day-over-day + 7-day avg),
📅 今日 TODO (rule-based), 🗂 昨日汇总, 🔍 可改良. Run `collect → normalize →
merge` first so the warehouse has the day being reported on. Later milestones
(M2–M5) add multica/ADO/state.db sources, LLM polish, and AIDash push.
```

- [ ] **Step 3: Full test suite**

Run: `cd ~/Development/AIDash/aidata && python3 -m pytest tests/ -v`
Expected: all pass (existing v2 tests + new digest tests), no warnings.

- [ ] **Step 4: Confirm no data staged**

Run: `cd ~/Development/AIDash/aidata && git status --short | grep -E 'archive/|warehouse.db|clean/|raw/' || echo "clean"`
Expected: `clean` (archive output gitignored; only golden fixture is tracked)

- [ ] **Step 5: Commit**

```bash
cd ~/Development/AIDash/aidata
git add README.md .gitignore
git commit -m "docs(digest): document M1 digest command + gitignore archive"
```

---

## Self-Review

**Spec coverage (M1 scope per ADR-20):**
- raven-only trending → Tasks 3–6 (cost/token/waste/pipeline/behavior queries + fetchers) + Task 2 (arrows/streak). ✓
- template-only, no LLM (ADR-18 M1 slice) → Task 8 renderer is pure Python; no LLM import anywhere. ✓
- CST day boundary `+8 hours` (ADR-2/22) → Task 1, used by all queries and math. ✓ (Task 5 note: ISO-text `ts_start` uses `date(ts_start,'+8 hours')`, epoch-ms uses `CST_DAY_EXPR` — divergence called out.)
- 4 sections (ADR-14) → Task 8. Char-budget (600/400/300/200) is a **必看层** concern deferred to M4/M5 push formatting; M1 writes the full local archive (ADR-16 必成 sink), so no truncation needed yet — noted, not a gap.
- rule-based TODO (ADR-8) → Task 7. ✓
- source_health (ADR-23) → Task 6 `SourceHealth` + Task 8 health line + "数据缺失" degradation. ✓
- trend honesty (ADR-3) → Task 8 "数据仅 N 天" when `days_available < 2`. ✓
- local md archive + idempotent (ADR-16/22) → Task 9 `write_digest` overwrites; golden test asserts determinism. ✓
- retention (ADR-21) → M1 reads warehouse as-is; no change needed. ✓
- golden test fixed date 2026-07-09 → Task 9. ✓

**Deferred to M2–M5 (correctly out of M1 scope):** multica project_id/updated_since/multi-ws, ADO PR source, state.db source, LLM slot-filling, codex:review verification, AIDash push, cron rewire, char-budget必看层 formatting. Listed below.

**Placeholder scan:** No TBD/TODO-as-placeholder. Every code step has complete code. Every query is complete SQL. (The `todo_rules.py` module is named "todo" but contains real rules — not a placeholder.)

**Type consistency:** `RavenTrends`/`SourceHealth` defined in Task 6, consumed with identical field names in Tasks 7/8/9. `Trend` defined Task 2, used in Task 8. `Todo(priority, text)` defined Task 7, rendered in Task 8 as `td.priority`/`td.text`. `CST_DAY_EXPR` defined Task 1, referenced in query-writing notes. `build_digest(report_date)`/`write_digest(report_date)` consistent across Task 9 + tests. `serve.run_query` signature matches serve.py:42 (`(name, params) -> (rows, cols)`).

**One gap found & fixed during review:** Task 6's `_series` helper and the inline reshaping in `fetch_raven_trends` both parse query columns — I kept both because `fetch_raven_trends` needs three series (cost/tokens/requests) from ONE query (daily-cost) while `_series` handles one-series-per-query; documented so the implementer doesn't "DRY" them into a broken single helper.

---

## Subsequent Milestones (NOT part of this plan — future plans)

- **M2** — multica EXT-1/2/3: add `project_id` + `updated_at` to fact_issue, switch multica_issue adapter to `updated_since` window read (ADR-19) with per-workspace watermarks (workspace-a+my), add "今日完成/活跃" trend + per-workspace grouping.
- **M3** — ADO PR source (`fact_ado_pr` table, creator=`me@example.com` resolved id, ADR-6/22) + Hermes `state.db` source (L2-only, automation-ratio dimension, ADR-7/13).
- **M4** — L5 LLM slot-filling (raven `claude-haiku-4.5`, bounded free-text slots + truncation, ADR-18) + `codex:review` number-verification pass + must-see-layer ≤1500-char formatting (600/400/300/200 budget, ADR-14).
- **M5** — AIDash push (cron wakes app: `open -a AIDash` + XPC readiness poll, non-fatal, ADR-16/17/23) + new Hermes cron job `aidata-digest` @ 04:00 CST, disable old `unified-daily-digest` (ADR-12).
