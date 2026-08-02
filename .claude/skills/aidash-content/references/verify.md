# Verify — real data, not template-only

Never claim a content change is done from a passing template render. The failure
modes live in the seam and the renderer. Verify in this order; stop and fix on the
first failure.

## 1. aidata pure-transform tests (fast, hermetic)

The `build_briefing` transform and all `fetch_*`/mapper helpers are unit-testable
with no app launch.

```bash
cd ~/Development/AIDash/aidata
python3 -m pytest tests/ -q
```

- The digest **template golden test** must stay green (it owns every number).
- The **LLM path is never golden-tested** (non-deterministic); its guard/fallbacks
  are tested instead.
- Add a test for any new mapper function / new `fetch_*` bundle. Assert the card is
  **absent** (not empty) when the source is degraded.

## 2. AIDash Core tests (schema + validator)

```bash
swift test --package-path ~/Development/AIDash/Packages/AIDashCore
```

Covers `CardTypeDecodeTests`, `CardPayloadRoundTripTests`, `SchemaValidatorTests`,
`EffectiveCardSizeTests`. A new/changed payload MUST round-trip and validate here.

## 3. AIDash UI snapshot (renders to PNG, light + dark)

```bash
swift test --package-path ~/Development/AIDash/Packages/AIDashUI \
  --filter SnapshotRenderTests
```

For a new CardType or a reshaped card, add/adjust a `SnapshotRenderTests` case so
the card is actually rendered at the relevant sizes. **Eyeball the PNG** — this is
where a hollow/blank card is caught.

### The EffectiveCardSize trap (most common "looks empty" bug)

`EffectiveCardSize.swift` downgrades a card whose payload is too "thin" for its
authored size (e.g. hero→small). Several small layouts render **title only** — so a
short-body card both shrinks AND loses its body. If your card looks empty:

- Don't force the size. Give the payload real content (e.g. a `digest` needs `≥2`
  sections to stay `hero` — see `_overview_sections` in `aidash.py`).
- Re-check `EffectiveCardSize` rules for the type before concluding the mapper is
  wrong.

## 4. End-to-end push to the REAL app (live check)

Only when a live render is wanted (the unit + snapshot tests are the gate; this is
confirmation):

```bash
cd ~/Development/AIDash/aidata
python3 cli.py digest --date <YYYY-MM-DD> --aidash        # +--llm to also polish
```

Non-fatal by contract (ADR-16/23): the local md archive is written first; a failed
push logs to `~/Development/AIDash/.aidash-state/aidash-push-errors.log` and posts a
desktop notification. The command still exits 0.

### Loading NEW Swift render code

A rebuilt app is required to see new rendering — `open` alone just reactivates the
running instance:

```bash
kill -9 "$(pgrep -f AIDash)" 2>/dev/null || true
# launch the freshly-built DerivedData bundle (NOT `open -a AIDash` by name):
open -n "$(ls -dt ~/Library/Developer/Xcode/DerivedData/AIDash-*/Build/Products/Debug/AIDash.app | head -1)"
```

The XPC listener re-registers on relaunch; the push path has a patient
`xpc_attempts` budget for the cold-start warmup. A Debug-build data store is
separate from any installed build → a fresh launch starts empty; re-push to
populate.

### If XPC is wedged

```bash
bash ~/Development/AIDash/scripts/dev/reset-xpc.sh
```

Health probe: `aidash schema list --quiet` exit 0 == XPC healthy.

## 5. Contract-sync lint

```bash
bash .claude/skills/aidash-content/scripts/contract_check.sh
```

Run after any change to either side (see `contract-sync.md`).

## Definition of done

- [ ] Change starts at the correct upstream layer (Step 0), no skipped layer.
- [ ] aidata pytest green (incl. golden template); new mapper/fetch has a test.
- [ ] AIDashCore tests green; payload round-trips + validates.
- [ ] UI snapshot renders the card correctly at its sizes (PNG eyeballed).
- [ ] contract_check.sh PASS (type present in all four places; required fields emitted).
- [ ] Real push renders the card (not a fallback placeholder, not blank).
- [ ] Both repos' gates pass; layer `tech-context.md` updated if deps/structure changed.
