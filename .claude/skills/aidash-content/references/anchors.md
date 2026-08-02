# Anchors — exact file locations (do not guess)

One repo (`~/Development/AIDash`), two layers. Absolute paths.

## aidata (~/Development/AIDash/aidata) — data production

| Layer | Path | Role |
|---|---|---|
| L1/L2 | `adapters/<source>.py` | collect raw jsonl + normalize to `clean/<source>.db` (one file per source) |
| L1 raw | `L1_collect/raw/<source>/<date>.jsonl` | append-only source of truth |
| L2 clean | `L2_normalize/clean/<source>.db` | cleaned per-source sqlite |
| L3 merge | `merge.py` + `schema/warehouse.sql` | build `L3_merge/warehouse.db` (`fact_*`/`dim_*`) |
| L4 serve | `L4_serve/queries/<group>/<name>.sql` | named queries; run via `serve.run_query("group/name")` |
| L4 runner | `serve.py` | `run_query(name, params)` → `(rows, cols)`. **stdlib sqlite 3.19 — NO window functions/LAG**; use correlated subqueries |
| L5 sources | `L5_apps/digest/sources.py` | `fetch_*()` → frozen dataclasses; assembled into `DigestSources` |
| L5 seam | `L5_apps/digest/aidash.py` | ★ `build_briefing()` (pure map → Container/Card) + `push_briefing()` (non-fatal XPC) |
| L5 orchestrate | `L5_apps/digest/app.py` | `_fetch_sources()` → `build_digest()` / `write_digest()` / `_push_to_aidash()` |
| L5 render (md) | `L5_apps/digest/render.py`, `must_see.py` | markdown archive + compact fold |
| dim table | `schema/dim_model.csv` | model → price (cost is derived, no cost field in raw) |
| tests | `tests/` | pytest; pure transform is hermetic, never launches the app |
| cron runner | `scripts/aidata_digest_run.sh` | collect→normalize→merge→`digest --llm --aidash` (04:00 job) |

`DigestSources` dataclass fields (each is what `build_briefing` consumes):
`raven, multica, ado, automation, cost_improvement, value_efficiency,
work_by_project, action_inbox, repo_radar`. Add a new bundle here + a `fetch_*` in
`_fetch_sources()` (`app.py`) when introducing a new source.

`aidash.py` builder functions (per container): `_overview_container`,
`_work_container`, `_metric_items` (+`_metric_item`/`_ratio_item`),
`_prose_containers`, `_radar_containers`. `build_briefing()` assembles them in order.

## AIDash (~/Development/AIDash) — display consumption

Module dep direction (enforced by SPM boundaries):
`AIDashCore ← AIDashUI ← AIDashApp`; `DesignKit ← AIDashUI`; `AIDashCore ← aidash CLI` (CLI never imports UI).

| Layer | Path | Role |
|---|---|---|
| Core enum | `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift` | enum + `decode()`/`validate()` switch (one arm per type) |
| Core payloads | `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/<Type>Payload.swift` | ★ schema single source (Codable, Sendable) |
| Core protocol | `.../Models/Payloads/CardPayloadProtocol.swift` | `validateInvariants()` contract |
| Core validator | `.../Validation/SchemaValidator.swift` | payload invariants |
| Core sizes/styles | `.../Models/CardSize.swift`, `CardStyle.swift`, `ContainerLayout.swift` | enums advertised by SchemaList |
| Core size resolver | `.../Models/EffectiveCardSize.swift` | thin-payload downgrade (hero→small); watch for vanishing bodies |
| App schema ad | `Apps/AIDashApp/Sources/XPCService/XPCHandlers.swift` | `handleSchemaList` + `payloadSchemas: [String:String]` (JSON Schema per type) |
| CLI schema render | `CLI/aidash/Sources/SchemaListRendering.swift` | builds `SchemaListResult` for the CLI |
| CLI surface | `AIDash/specs/001-core-briefing-cli/contracts/cli-surface.md` | subcommands + exit codes (0 ok, 2 xpc, 3 app-side) |
| UI router | `Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift` | `routedView(for:)` switch — one `case let p as <Type>Payload` per type |
| UI card views | `Packages/AIDashUI/Sources/AIDashUI/CardView/<Type>CardView.swift` | renders per size (small/medium/wide/hero) |
| UI snapshot test | `Packages/AIDashUI/Tests/AIDashUITests/SnapshotRenderTests.swift` | renders card → PNG (light+dark) |
| contract mirror | `AIDash/specs/001-core-briefing-cli/contracts/cardtype-payloads.md` | human mirror of payload schemas (Swift wins) |
| layer docs | `Packages/<X>/tech-context.md` | per-package red_lines/deps; read before editing that package |
| project map | `AIDash/AGENTS.md`, `AIDash/tech-context.md` | layer routing + hard constraints |
| XPC reset | `AIDash/scripts/dev/reset-xpc.sh` | clear a wedged XPC listener |
| push-error log | `AIDash/.aidash-state/aidash-push-errors.log` | where a failed push records (loud-fail sink) |

Current CardTypes (as of skill authoring — verify with `CardType.allCases`):
`metric, insight, agentSummary, todoList, trending, digest, sectionHeader`.

## The seam contract

- CLI verbs (from `push_briefing`): `briefing put`, `container put`, `card put
  --type <t> --size <s> --style <st> --payload @<file.json>`, `briefing publish`.
- Card payload reaches the app as **raw JSON**; the app decodes via
  `CardType.decode(data)`. Unknown JSON keys are ignored (Codable) → adding an
  optional field is zero-migration and back-compatible.
- Health probe: `aidash schema list --quiet` exit 0 == XPC healthy.
