# aidata-digest M4 Implementation Plan — LLM slot-filling + number-verification guard

> **For agentic workers:** TDD task-by-task. Each task = failing test → implement → pass → commit. Full unit suite green after each. The template golden test (`test_digest_golden.py`) MUST stay byte-identical.

**Goal (ADR-18):** Add an OPTIONAL LLM polish layer on top of the deterministic template, WITHOUT letting the LLM touch any number. The template stays the source of all numbers; the LLM fills only bounded free-text slots (an overall TL;DR "点评" line + refined TODO wording). A deterministic number-verification guard rejects any polished output that alters/invents a number, falling back to the pure template. Raven 7024 (`claude-haiku-4.5`) unavailable / errors / timeout / fails-verification → template fallback. The local archive is a 必成 sink: it ALWAYS produces, LLM or not.

**Architecture:** The LLM dependency is isolated in one network-boundary module `L5_apps/digest/llm.py` (stdlib `urllib.request`, no new dep). Pure logic lives in `L5_apps/digest/verify.py` (number guard) and `L5_apps/digest/polish.py` (prompt build, response parse, slot apply). `app.build_digest` gains `use_llm: bool = False`; default keeps M1–M3 behavior exactly. CLI gains `--llm`. L1–L4 stay pure-data; the LLM call lives ONLY in L5.

**Tech Stack:** Python 3.11 stdlib (`urllib.request`, `json`, `re`, `os`, `dataclasses`), pytest. Tests are hermetic — a fake/monkeypatched client, never real network. Any real-raven test is `@pytest.mark.integration` and skippable.

## Global Constraints

- **Numbers are template-owned, never LLM-owned (ADR-18).** The number-bearing template lines are ground truth. The LLM only produces qualitative commentary + rephrased TODO wording; a guard verifies no number was altered/invented.
- **Determinism of the template path preserved.** `build_digest(date)` with `use_llm=False` returns byte-identical M1–M3 output. The golden test stays unchanged and green.
- **Degrade-not-crash (ADR-23).** raven down / no key / timeout / bad JSON / failed verification → template fallback, never crash.
- **Layer purity (ADR-11).** LLM network I/O only in `llm.py`. `verify.py`/`polish.py` are pure (polish takes a client by dependency injection).
- **Secrets.** Read `ANTHROPIC_API_KEY`/`RAVEN_API_KEY` from env; never log or commit it.
- **Char budget (ADR-14).** LLM slots are hard length-capped: TL;DR ≤ 150 chars, each refined TODO ≤ 120 chars.
- **Style.** PEP 8, type annotations, functions < 50 lines, files < 400 lines, immutable frozen dataclasses.

---

## File Structure

**New files:**
- `L5_apps/digest/llm.py` — the single LLM network boundary: `LLMConfig`, `config_from_env`, `LLMError`, `LLMClient` protocol, `RavenClient` (urllib POST to `{base_url}/v1/messages`), `default_client`.
- `L5_apps/digest/verify.py` — `extract_numbers(text) -> frozenset[str]`, `VerificationResult`, `verify_numbers(template_md, polished_md) -> VerificationResult`. THE safety guard. Pure, hermetic.
- `L5_apps/digest/polish.py` — `PolishSlots`, `build_prompt(template_md)`, `parse_slots(raw)`, `truncate(text, n)`, `apply_slots(template_md, slots)`, `polish_digest(template_md, client)`. Pure except `polish_digest` takes an injected client.
- `tests/test_verify.py`, `tests/test_llm.py`, `tests/test_polish.py`, `tests/test_digest_llm.py`.

**Modified files:**
- `L5_apps/digest/app.py` — `build_digest(report_date, use_llm=False, client=None)`; `write_digest(report_date, use_llm=False)`. Fallback-wrapped LLM path.
- `cli.py` — `digest --llm` flag.
- `README.md` — document `--llm`, the guard, and fallback.

**Task boundaries:** Task 1 = number-verification guard (the core). Task 2 = LLM client boundary. Task 3 = polish (prompt/parse/truncate/apply). Task 4 = app wiring (use_llm + fallback) + CLI + LLM-path tests. Task 5 = docs + full regression + live smoke.

---

## Task 1: Number-verification guard (`verify.py`) — the core safety mechanism

**Produces:**
- `extract_numbers(text: str) -> frozenset[str]` — all numeric tokens via `-?\d+(?:\.\d+)?`.
- `@dataclass(frozen=True) VerificationResult` — `ok: bool`, `introduced: frozenset[str]` (numbers in polished not in template = hallucination), `missing: frozenset[str]` (template numbers absent from polished = alteration/drop), `reason: str`.
- `verify_numbers(template_md, polished_md) -> VerificationResult` — `ok` iff both `introduced` and `missing` are empty.

**Tests (`tests/test_verify.py`):** extract catches ints/decimals/negatives/percentages; a clean polished (template + qualitative commentary with no new numbers) passes; a polished that changes `32%`→`45%` is rejected (45 introduced, 32 missing); a polished that invents `$500` is rejected; a polished that drops a template number is rejected. All `@pytest.mark.unit`.

**Commit:** `feat(digest): number-verification guard (ADR-18)`

---

## Task 2: LLM client boundary (`llm.py`)

**Produces:**
- `@dataclass(frozen=True) LLMConfig` — `base_url, api_key, model, timeout_s, max_tokens`.
- `config_from_env() -> LLMConfig | None` — reads `ANTHROPIC_BASE_URL` (default `http://localhost:7024`), `ANTHROPIC_API_KEY` or `RAVEN_API_KEY`, `ANTHROPIC_SMALL_FAST_MODEL` (default `claude-haiku-4.5`). Returns `None` when no key (→ caller falls back).
- `class LLMError(Exception)`.
- `LLMClient` Protocol: `complete(system: str, user: str) -> str`.
- `RavenClient` — urllib POST to `{base_url}/v1/messages` with `x-api-key`, `anthropic-version`; parses `content[0].text`; raises `LLMError` on any network/timeout/HTTP/parse failure. Never logs the key.
- `default_client() -> LLMClient | None`.

**Tests (`tests/test_llm.py`):** `config_from_env` reads env (monkeypatched) and returns None without a key; `RavenClient.complete` parses a fake `urlopen` JSON body into text; network/HTTP/malformed → `LLMError`; the key never appears in an exception string. One `@pytest.mark.integration` test hits real raven and is skipped when unreachable.

**Commit:** `feat(digest): raven LLM client boundary (stdlib urllib, ADR-11)`

---

## Task 3: Polish orchestration (`polish.py`)

**Produces:**
- `@dataclass(frozen=True) PolishSlots` — `tldr: str`, `todos: tuple[str, ...]`.
- `MAX_TLDR = 150`, `MAX_TODO = 120` (ADR-14 caps).
- `build_prompt(template_md) -> tuple[str, str]` — (system, user). System forbids inventing/altering/restating numbers and asks for qualitative commentary in strict JSON `{"tldr": "...", "todos": ["..."]}`.
- `parse_slots(raw) -> PolishSlots` — tolerant JSON parse (strips ``` fences); raises `LLMError` on unparseable.
- `truncate(text, n) -> str` — hard char cap (adds `…` when cut).
- `apply_slots(template_md, slots) -> str` — inserts `> 💡 点评: {tldr}` after the title; replaces each `- {P?}: {text}` TODO line's wording with the next refined todo (priority prefix preserved from the template, never from the LLM). Pure.
- `polish_digest(template_md, client) -> str` — build → `client.complete` → parse → apply. Propagates `LLMError`.

**Tests (`tests/test_polish.py`):** prompt contains a no-numbers instruction; `parse_slots` handles fenced/garbage JSON; `truncate` enforces the cap; `apply_slots` preserves the `P0:`/`P1:` priority prefix and leaves number lines untouched; `polish_digest` with a fake client returns assembled markdown. `@pytest.mark.unit`.

**Commit:** `feat(digest): LLM slot polish — prompt/parse/truncate/apply (ADR-14/18)`

---

## Task 4: App wiring + CLI + fallback/guard integration tests

**Produces:**
- `build_digest(report_date, use_llm=False, client=None) -> str` — `use_llm=False` returns template md (unchanged). `use_llm=True`: resolve client (`client or default_client()`); if none → template. Else try `polish_digest`; run `verify_numbers(template, polished)`; on `LLMError` OR `not result.ok` → return template (fallback). Never crashes.
- `write_digest(report_date, use_llm=False) -> Path`.
- CLI: `digest --llm` opt-in flag.

**Tests (`tests/test_digest_llm.py`, all `@pytest.mark.unit`, fake clients, reuse the golden's frozen fetch fixture):**
- `use_llm=False` output == template output (no regression).
- Happy path: a fake client returning clean slots → polished md contains `💡 点评` and refined TODO wording, and passes verification.
- Fallback on error: a fake client raising `LLMError` → output == template.
- Fallback on hallucination: a fake client that injects a NEW number → `verify_numbers` rejects → output == template. (Proves the guard drives the fallback.)
- `default_client()` None (no key) → template.

**Commit:** `feat(digest): --llm opt-in polish with verify-guarded template fallback (ADR-16/18/23)`

---

## Task 5: Docs + full regression + live smoke

- README: document `aidata digest --llm`, the number guard, and the template-floor fallback.
- `python3 -m pytest tests/ -q -m unit` all green; golden test unchanged.
- Live smoke: `python3 cli.py digest --date 2026-07-11` (template) and `... --llm` (polish or clean fallback). Either outcome acceptable.
- Ledger `.superpowers/sdd/m4-ledger.md`.

**Commit:** `docs(digest): document M4 LLM polish + guard; M4 ledger`

---

## Self-Review / spec coverage (M4 per ADR-18)

- Template owns all numbers; LLM fills only TL;DR + TODO wording slots → Tasks 3–4. ✓
- Number-verification guard, deterministic + tested against a hallucinated output → Task 1 + Task 4. ✓
- Fallback on unavailable/error/timeout/failed-verification → Task 4, tested. ✓
- `--llm` opt-in, default template-only (golden unchanged) → Task 4. ✓
- Char budget length-caps (ADR-14) → Task 3. ✓
- LLM isolated in one module, L1–L4 untouched (ADR-11) → Task 2. ✓
- Secret from env, never logged → Task 2. ✓
- codex CLI is present (`which codex`) but the primary guard is the deterministic programmatic check (hermetic, testable); codex is left as an optional future secondary (noted for M5).

## Deferred to M5
- AIDash push (cron wakes app), new `aidata-digest` cron, disable old `unified-daily-digest`, optional `codex:review` secondary verification, full 必看层 ≤1500 formatting/folding.
