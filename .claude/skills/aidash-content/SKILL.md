---
name: aidash-content
description: Use when adding or changing content that shows up in the AIDash daily briefing — a new card, a new metric/indicator, a new data source, or reshaping an existing card. Enforces layer-through implementation across the pipeline (aidata data-production → AIDash display) so you never patch only the last layer (a hollow card with no upstream data). Trigger phrases include "AIDash 加一张卡/加个指标/改卡片", "在 briefing 里显示 X", "aidash 数据不对/是空的", "从 aidata 到 AIDash 加内容", "新增数据源到日报". Also covers the contract-sync check (aidata payload ↔ AIDashCore schema), the verify+push loop, and scaffolding a brand-new CardType.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# AIDash Content — layer-through change router

**Announce at start:** "I'm using the aidash-content skill."

AIDash briefing content spans **two layers of one repo** (Python data production →
Swift display). The #1 failure mode is patching only
the seam (`aidash.py`) or only the renderer (`<Type>CardView`) — producing a card
with no real upstream data (a *hollow* card). This skill routes every content
change to its **true upstream starting layer** and drives it down to the renderer,
then verifies with real data.

**The rule (铁律):** the moment you touch the seam (`aidata/L5_apps/digest/aidash.py`)
or a renderer (`<Type>CardView`), ask: *does this value actually exist in L1–L4?* If
not, you started too low — go back up.

> Both layers now live in **one repo** (`~/Development/AIDash`), so a content
> change can — and should — land as a single atomic commit spanning Python and
> Swift. The layer-through discipline below is unchanged; it was never about
> repo count.

## The pipeline (one repo, two layers)

```
aidata/  (Python)                          — DATA PRODUCTION
  L1_collect   adapters/<source>.py         → raw/<source>/<date>.jsonl   (append-only, redacted, source-of-truth)
  L2_normalize (same adapter cleans)         → clean/<source>.db          (each source independent)
  L3_merge     merge.py + schema/warehouse.sql → warehouse.db (fact_*/dim_*; only mergeable sources)
  L4_serve     L4_serve/queries/*.sql         → named queries
  L5_apps      L5_apps/digest/sources.py      → fetch_* → dataclass series/bundles (into DigestSources)
               L5_apps/digest/aidash.py       → ★ build_briefing() maps sources → Container/Card payloads
                                                 push_briefing()  → best-effort XPC push to the CLI
                        ── XPC seam ──
Swift side                                 — DISPLAY CONSUMPTION
  aidash CLI   thin XPC client (Core only, never imports UI)
  AIDashCore   Models/Payloads/<Type>Payload.swift  ★ schema single source
               Models/CardType.swift               (enum + decode/validate switch)
               XPCService/XPCHandlers.swift         payloadSchemas[...]  (SchemaList advertises schema)
  AIDashUI     CardView/<Type>CardView.swift + CardView/CardRouter.swift  (render switch)
  AIDashApp    macOS/iPadOS/iOS app (owns CloudKit; SwiftData is a discardable mirror)
```

Absolute paths are pinned in `references/anchors.md`. Read it — do not guess file
locations.

## Step 0 — classify the change (pick the STARTING layer)

Ask what the new content's **most-upstream** origin is, then start there:

| What you're adding | Starting layer | Layers to touch (upstream → downstream) |
|---|---|---|
| Show an **existing** L4 metric in a card | `sources.py` | sources.py → aidash.py → (Core payload only if a field is missing) → UI |
| **New indicator** from data already collected | L3 `warehouse.sql` | (merge/warehouse if fact col missing) → L4 `queries/*.sql` → sources.py → aidash.py → Core payload (if new field) → UI |
| **Brand-new data source** | L1 `adapters/` | adapters/<source>.py → L2 clean → (L3 if mergeable) → L4 query → sources.py → aidash.py → Core → UI |
| **Brand-new CardType** | Core schema | Core (CardType+Payload+decode+Validator+payloadSchemas) → UI (CardView+CardRouter) → aidash.py mapper ← upstream data |
| Reshape an **existing** card (copy/layout/fields) | wherever the field lives | If a NEW field: Core payload first, then UI + mapper. If only rewording: mapper (+ maybe UI). |

Then follow the matching playbook in `references/playbooks.md`. Do not skip an
upstream layer because it "looks like a one-liner at the seam."

## Step 1 — read before touching (read contract)

- **Always:** `references/anchors.md` (paths), and the target layer's own
  `tech-context.md` on the AIDash side (`Packages/<X>/tech-context.md`) when you
  touch a Swift package. AIDash's `AGENTS.md` layer-routing rule is authoritative
  there.
- **aidata side:** `L5_apps/digest/aidash.py` is the seam — read its module
  docstring; it explains the pure-transform vs non-fatal-push split (ADR-16/17/23).
- **Card schema truth:** the Swift `Models/Payloads/<Type>Payload.swift` file wins
  over any doc. The human mirror is `AIDash/specs/001-core-briefing-cli/contracts/cardtype-payloads.md`.

## Step 2 — implement upstream→downstream

Work strictly top-down so each layer has data before the next consumes it. Detailed
per-scenario steps (with the exact functions to edit — `fetch_*`, `_metric_items`,
`build_briefing`, the `DigestSources` field, the `CardType` switch arms, the
`payloadSchemas` entry, the `CardRouter` case) are in `references/playbooks.md`.

**Immutability & style (project rule):** payload dataclasses in `aidash.py` are
`@dataclass(frozen=True)`; build new dicts/tuples, never mutate. Keep Swift payload
structs `Codable, Sendable` with `let` fields. New optional payload fields must be
**optional** (`?` in Swift, absent-safe in the mapper) so old app builds stay
back-compatible (Codable ignores unknown keys → zero migration).

## Step 3 — contract-sync check (aidata payload ↔ AIDash schema)

The seam is untyped JSON, so drift is silent. After changing either side, verify
they agree. Run the helper:

```bash
bash .claude/skills/aidash-content/scripts/contract_check.sh
```

It cross-checks, for each `CardType`: the raw value appears in aidata's mapper, in
`CardType.swift`, in `XPCHandlers.payloadSchemas`, and in `CardRouter.swift`. It
flags any card type present on one side but missing on another, and any payload
`required` field the mapper never emits. Treat any FAIL as a blocker — read
`references/contract-sync.md` for how to resolve each class of drift.

## Step 4 — verify with REAL data + push

Never claim done from a template render alone. Follow `references/verify.md`:

1. **aidata unit tests** (pure transform is fully testable, hermetic):
   `cd ~/Development/AIDash/aidata && python3 -m pytest tests/ -q`
2. **AIDash Core tests** (schema/validator): `swift test --package-path
   ~/Development/AIDash/Packages/AIDashCore`
3. **AIDash UI snapshot** (renders the card to PNG, light+dark):
   `SnapshotRenderTests` in `Packages/AIDashUI` — add/adjust a case for a new card.
4. **End-to-end push to the real app** (only when a live check is wanted):
   `cd ~/Development/AIDash/aidata && python3 cli.py digest --date <YYYY-MM-DD> --aidash`
   The push is best-effort/non-fatal; a stale mirror logs to
   `~/Development/AIDash/.aidash-state/aidash-push-errors.log` and posts a desktop
   notification. To load NEW Swift render code you must relaunch the freshly-built
   app (`kill -9` old pid, then launch the DerivedData `AIDash.app`) — `open` alone
   just reactivates the running instance. XPC re-registers on relaunch.

## Step 5 — respect the gates before committing

Each layer has its own gates (do NOT bypass):

- **aidata (Python):** `/usr/bin/python3 -m pytest aidata/tests/ -q`, ruff; the
  digest template golden test must stay green; the LLM path is never golden-tested.
  Gated in CI by the `aidata (pytest + ruff)` job, which also runs a
  degrade-not-crash probe with no `config_local.py` — so a new source must
  degrade to a no-op (ADR-23), and a new fetch must be frozen in the golden
  fixture or it will leak live data and fail there.
- **AIDash (Swift):** pre-commit (incremental per-package build+test+swiftlint), pre-push
  (frontmatter anti-corrosion, "改代码必带测试" gate, full swiftlint + Core tests +
  xcodegen + xcodebuild for app AND CLI), and GitHub Actions on `macos-26`. If you
  changed `Packages/<X>/**` structure/deps, update that layer's `tech-context.md`
  frontmatter or the anti-corrosion check fails.

Both layers live in **one repo**, so a content change spanning Python and Swift
should land as **one atomic commit** — that is the whole point of the merge. Run
both gates before committing.

## Scaffolding a brand-new CardType

When Step 0 lands on "brand-new CardType," run:

```bash
bash .claude/skills/aidash-content/scripts/scaffold_cardtype.sh <lowerCamelName>
```

It prints a checklist of every anchor to edit (Core payload struct + decode arm +
validator + payloadSchemas JSON entry + CLI SchemaListRendering + UI CardView +
CardRouter case + aidata mapper function + DigestSources field) with the file
paths, and emits starter stubs to stdout for you to adapt. It does **not** edit
files — you place the code, matching surrounding idiom. See
`references/playbooks.md → New CardType`.

## Anti-patterns (reject these)

- Editing `<Type>CardView` to show data that no payload field carries → hollow.
- Adding a mapper field in `aidash.py` with no `sources.py`/L4 origin → fabricated.
- Adding a payload field on the Swift side without updating `payloadSchemas` →
  SchemaList lies to the CLI.
- Widening a card without checking `EffectiveCardSize` — a thin payload gets
  downgraded (hero→small) and the body vanishes. See `references/verify.md`.
- Bumping only one layer and calling it done. Content changes almost always span
  both Python and Swift; if yours doesn't, say explicitly why.
