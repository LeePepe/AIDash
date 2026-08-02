# Playbooks — per-scenario, upstream→downstream

Always work top-down. Each step below leaves data ready for the next layer to
consume. File paths: see `anchors.md`.

---

## A. Show an EXISTING L4 metric in a card

Upstream data already exists; you're only surfacing it.

1. **sources.py** — if a `fetch_*` bundle already carries the series, reuse it.
   Otherwise add a `fetch_<x>()` returning a `@dataclass(frozen=True)` with the
   series + a `SourceHealth`, and wire it into `_fetch_sources()` in `app.py` and
   the `DigestSources` dataclass (default_factory = a skipped/empty bundle so old
   callers/tests keep working).
2. **aidash.py** — add the item to the right builder (`_metric_items` for a metric
   card, or a `_*_container`). Guard on `health.state == "ok"` and on the reported
   day having a value (return `None`/skip → the card degrades, never fabricates).
3. **Core payload** — only if the value needs a field the payload lacks. Usually
   `MetricPayload.Item` (label/value/unit/trend/series/ratio/higherIsBetter/context)
   already covers it → no Swift change.
4. **UI** — no change if the existing card renders the field.
5. Contract-sync (Step 3) + verify (Step 4).

---

## B. NEW indicator from data already collected

The raw data exists but no L4 query exposes the number.

1. **L3 (only if the fact column is missing)** — add the column to
   `schema/warehouse.sql` and populate it in `merge.py`. Re-run `python3 cli.py
   merge`. Idempotent (PK dedup). Keep the merge one-way (reads L2, writes L3).
2. **L4** — add `L4_serve/queries/<group>/<name>.sql`. Remember **sqlite 3.19**:
   no window functions; use correlated subqueries (see `radar/latest.sql` for the
   star-delta pattern). Test with `python3 cli.py query <group>/<name>`.
3. **sources.py** — `fetch_<x>()` calling `serve.run_query("<group>/<name>")`,
   returning a frozen dataclass; wire into `_fetch_sources()` + `DigestSources`.
4. **aidash.py** — map into a card item/container (see A.2).
5. **Core payload** — add an optional field ONLY if needed (see D).
6. **UI** — render the new field if a payload field was added.
7. Contract-sync + verify.

---

## C. BRAND-NEW data source

Nothing collected yet. Start at L1.

1. **adapters/<source>.py** — implement collect (append redacted rows to
   `L1_collect/raw/<source>/<date>.jsonl`, watermark for idempotency) + normalize
   (write `L2_normalize/clean/<source>.db`). Follow an existing adapter
   (`adapters/github_repo.py` is a good template: gh-api fetch, degrade-not-crash,
   composite-PK snapshot). **redaction.py** must strip secrets before raw — verify
   no plaintext secret lands in raw.
2. **Register the source** — add it to the collect/normalize source lists and (if
   mergeable) the 04:00 cron `SOURCES`. Memory-like sources stop at L2 and are
   queried directly (not merged).
3. **L3 (only if mergeable)** — add `fact_<x>` / `dim_<x>` to `warehouse.sql` +
   merge logic in `merge.py`. Decide the grain and PK. If the source is queried
   directly (like Hermes state.db / memory sources), skip L3.
4. **L4** — named query over the new table.
5. **sources.py → aidash.py → Core → UI** — as in B.3–B.6.
6. Contract-sync + verify. Add unit tests for the adapter (hermetic).

---

## D. NEW payload FIELD on an existing card (reshape)

1. **Core payload** — add the field to `<Type>Payload.swift` as **optional**
   (`let foo: Foo?`). Keep `Codable, Sendable`. Update `validateInvariants()` only
   if the field has an invariant (e.g. `ratio` in 0...1).
2. **payloadSchemas** — add the field to the JSON Schema string in
   `XPCHandlers.payloadSchemas[CardType.<t>.rawValue]` (and keep the CLI
   `SchemaListRendering` consistent). Optional → NOT in `required`.
3. **contract mirror** — update `cardtype-payloads.md` (human doc; Swift wins).
4. **UI** — render the field in `<Type>CardView` (guard `if let`), across the sizes
   where it belongs.
5. **aidash.py mapper** — emit the field only when upstream data provides it
   (`if value is not None: item["foo"] = ...`). See `_radar_item` for the
   optional-field pattern (`delta`/`category`/`reason`).
6. Because the field is optional and Codable ignores unknown keys, **old app builds
   stay compatible** — zero migration. Push can precede the Swift render landing.
7. Contract-sync + verify.

---

## E. BRAND-NEW CardType

The heaviest change — a new rendered card kind. Run
`scripts/scaffold_cardtype.sh <name>` first for the checklist. Order:

**AIDashCore (schema first — everyone depends on it):**
1. `Models/Payloads/<Type>Payload.swift` — new struct (Codable, Sendable, `let`
   fields), conform to `CardPayloadProtocol`, implement `validateInvariants()`.
2. `Models/CardType.swift` — add the enum case + a `decode` arm + (implicitly) the
   `validate` path.
3. `Validation/SchemaValidator.swift` — wire any cross-field invariants if needed.
4. `XPCService/XPCHandlers.swift` — add `payloadSchemas[CardType.<t>.rawValue]` JSON
   Schema string. `CardType.allCases` auto-advertises the raw value.
5. `CLI/aidash/Sources/SchemaListRendering.swift` — keep the CLI's SchemaListResult
   in sync if it enumerates types.
6. Core tests: `CardTypeDecodeTests`, `CardPayloadRoundTripTests`,
   `SchemaValidatorTests` — add cases.

**AIDashUI (renderer):**
7. `CardView/<Type>CardView.swift` — new view rendering small/medium/wide/hero.
   Own its chrome via `.cardChrome` (CardRouter must NOT add a second background).
8. `CardView/CardRouter.swift` — add `case let p as <Type>Payload:
   <Type>CardView(payload: p, size: effectiveSize, style: card.style)`.
9. `Tests/AIDashUITests/<Type>CardViewTests.swift` + a `SnapshotRenderTests` case.

**aidata (producer/mapper) — last, because it needs the type to exist:**
10. `L5_apps/digest/aidash.py` — a `_<x>_container(...)` builder returning a
    `Container` with `Card(..., type="<t>", ...)`; call it from `build_briefing`.
    Guard on health; degrade to no-container (never empty card).
11. `sources.py` — the `fetch_*` bundle feeding it (if not already present).
12. aidata unit tests for the new mapper (pure, hermetic).

Then contract-sync (Step 3) + full verify (Step 4). A new CardType MUST appear in
all four places or `contract_check.sh` fails: aidata mapper, `CardType.swift`,
`payloadSchemas`, `CardRouter.swift`.

---

## Cross-cutting reminders

- **UUID discipline:** container/card IDs in `aidash.py` are deterministic
  (`_cuid`/`_kuid` from the reported mmdd). If you retarget a briefing to another
  date, remap the UUIDs too, or the app rejects `Container id already exists under
  a different briefing` (UUIDs are globally unique).
- **Effective size trap:** a short/section-less payload gets downgraded
  (hero→small) and small layouts may render title-only → body vanishes. If a card
  "looks empty," give it real sections (see `_overview_sections`) rather than
  forcing the size. Check `EffectiveCardSize.swift`.
- **Degrade, never crash:** every `fetch_*` and every mapper guards on
  `SourceHealth` + presence, returning empty/None so a missing source yields no
  card — never a fabricated 0 or an empty card.
