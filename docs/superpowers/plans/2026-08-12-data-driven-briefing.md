# Data-Driven Briefing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AIDash choose card type, geometry, and visualization from the data shape; compress the daily briefing into a two-minute first screen/five-minute full page; and add relationship visualizations for cost×outcome, rework concentration, and other genuine cross-data signals.

**Architecture:** `aidata` remains the only author: L4 produces traceable cross-source rows and L5 profiles each dataset before choosing CardType, authored size, and visualization. AIDashCore locks a new semantic `relationship` payload; DesignKit supplies its classification token; AIDashUI renders scatter/heatmap/slope with Apple Charts and keeps effective-size downgrade as a safety net. Changes land as one independently testable commit per layer.

**Tech Stack:** Python 3.13, SQLite SQL, Swift 6 strict concurrency, SwiftUI, Swift Charts, Swift Testing, DesignKit tokens, XPC/CLI JSON schema.

## Global Constraints

- macOS 26 / iPadOS 26 / iOS 26 minimum; no OS 25 compatibility shims.
- App-side LLM calls remain forbidden; `aidata` authors all briefing content.
- CLI remains a thin XPC client and never imports UI or talks to CloudKit directly.
- `type / size / style` remain orthogonal: type owns badge/typography/content density, size owns geometry, style owns only the left stripe.
- Raw colors live only in DesignKit token sources; views consume `Theme` tokens.
- Production code contains no `fatalError`, `try!`, or `as!`.
- Tests are written first. Verification runs through normal `git commit`/`git push` hooks; do not manually repeat full suites.
- Never run host-based `AIDashAppTests` locally.
- Every cross signal includes time window, sample size, comparison baseline, and metric definition; observational correlation is not worded as causation.

---

## File Map

- `.specify/memory/constitution.md`: register the `relationship` visual recipe and bump constitution version.
- `AGENTS.md`: correct the test wording to require hook-driven verification.
- `specs/001-core-briefing-cli/contracts/cardtype-payloads.md`: document the relationship JSON contract.
- `Packages/AIDashCore/.../RelationshipPayload.swift`: schema and invariants.
- `Packages/AIDashCore/.../CardType.swift`: decode dispatch.
- `Packages/AIDashCore/.../EffectiveCardSize.swift`: relationship richness downgrade.
- `Packages/DesignKit/.../ColorSystem.swift`: relationship classification color.
- `Packages/AIDashUI/.../DesignTokens.swift`: relationship badge symbol/classification.
- `Packages/AIDashUI/.../RelationshipCardView.swift`: scatter, heatmap, and slope renderers.
- `Packages/AIDashUI/.../CardRouter.swift`: relationship routing.
- `aidata/L4_serve/queries/attribution/rework-relationship.sql`: workspace×root-cause relationship rows.
- `aidata/L5_apps/digest/card_policy.py`: pure data-profile → card decision rules and information budget.
- `aidata/L5_apps/digest/sources.py`: degrade-safe relationship bundle.
- `aidata/L5_apps/digest/aidash.py`: publish high-value cross signals and suppress weak cards.

---

### Task 1: Constitution, Contract, and Hook-Verification Wording

**Files:**
- Modify: `.specify/memory/constitution.md`
- Modify: `AGENTS.md`
- Modify: `specs/001-core-briefing-cli/contracts/cardtype-payloads.md`

**Interfaces:**
- Consumes: approved design spec `docs/superpowers/specs/2026-08-12-data-driven-briefing-design.md`.
- Produces: authoritative `relationship` recipe and exact JSON examples used by Core/aidata tasks.

- [ ] **Step 1: Amend the constitution recipe and version**

Add a row to the per-type recipe table:

```markdown
| `relationship` | `point.3.connected.trianglepath.dotted` | `.relationship` (cyan) | `.headline` for conclusion | `.caption.monospaced()` for axes/sample/window | Scatter/heatmap/slope; wide uses chart + evidence rail |
```

Add a relationship visualization section stating:

```markdown
- `relationship` represents a typed relationship, not a chart-shaped CardType.
- `visualization` is `scatter | heatmap | slope` and must match the payload fields.
- Every relationship card carries `sampleSize`, `timeWindow`, and `metricDefinition`.
- A relationship card must never claim causation from observational association.
- Wide/hero may use chart + evidence rail; small/medium reduce visible marks/legend, never font size.
```

Bump `Version` from `1.10.0` to `1.11.0`, set `Last Amended` to `2026-08-12`, and add a changelog entry naming the new CardType and migration obligation.

- [ ] **Step 2: Correct AGENTS.md test language**

Replace the heading and lead paragraph with:

```markdown
## Test through hooks; do not manually repeat suites

**Verification is mandatory and hook-driven.** Do not manually run the same
test suites that `scripts/hooks/pre-commit` and `pre-push` run. Instead, make
normal verified commits and pushes: `pre-commit` runs the affected package
build/tests and lint; `pre-push` runs the repository-wide gates. A hook failure
is the test signal: map its path to the owning layer, fix that layer, and commit
again. Do not bypass hooks for code changes.
```

Keep the host-based test prohibition and hostless exception unchanged.

- [ ] **Step 3: Add the locked contract example**

Document these three valid shapes in `cardtype-payloads.md`:

```json
{"title":"Cost × outcome","visualization":"scatter","xAxis":{"label":"Cost per completed task","unit":"USD"},"yAxis":{"label":"First-pass completion proxy","unit":"%"},"points":[{"label":"AIDash","x":2.1,"y":88,"magnitude":34,"category":"project"}],"sampleSize":34,"timeWindow":"7d","metricDefinition":"completed is a pipeline proxy, not objective correctness","summary":"AIDash has the lowest observed cost at the highest completion proxy."}
```

```json
{"title":"Rework concentration","visualization":"heatmap","xAxis":{"label":"Day"},"yAxis":{"label":"Workspace"},"cells":[{"column":"2026-08-11","row":"AIDash","value":48000}],"sampleSize":4,"timeWindow":"7d","metricDefinition":"tokens on issues completed after cancellation","summary":"Observed rework is concentrated on one day; no causal claim."}
```

```json
{"title":"Before × after","visualization":"slope","xAxis":{"label":"Period"},"yAxis":{"label":"Tokens per completed task"},"slopes":[{"label":"AIDash","before":21000,"after":18000}],"sampleSize":12,"timeWindow":"previous 7d vs current 7d","metricDefinition":"total tokens divided by completed pipeline tasks","summary":"Observed unit token use decreased."}
```

- [ ] **Step 4: Commit and use the docs-only hook result**

```bash
git add .specify/memory/constitution.md AGENTS.md specs/001-core-briefing-cli/contracts/cardtype-payloads.md
git commit -m "docs: define data-driven relationship cards"
```

Expected hook signal: no SPM package change, docs checks pass.

---

### Task 2: AIDashCore Relationship Schema and Effective Size

**Files:**
- Create: `Packages/AIDashCore/Sources/AIDashCore/Models/Payloads/RelationshipPayload.swift`
- Modify: `Packages/AIDashCore/Sources/AIDashCore/Models/CardType.swift`
- Modify: `Packages/AIDashCore/Sources/AIDashCore/Models/EffectiveCardSize.swift`
- Modify: `Packages/AIDashCore/Tests/AIDashCoreTests/CardPayloadRoundTripTests.swift`
- Modify: `Packages/AIDashCore/Tests/AIDashCoreTests/CardTypeDecodeTests.swift`
- Modify: `Packages/AIDashCore/Tests/AIDashCoreTests/SchemaValidatorPayloadInvariantTests.swift`
- Modify: `Packages/AIDashCore/Tests/AIDashCoreTests/EffectiveCardSizeTests.swift`

**Interfaces:**
- Produces: `RelationshipPayload`, `RelationshipVisualization`, `.relationship`, and downgrade behavior consumed by UI and CLI schema advertising.

- [ ] **Step 1: Write failing payload/decode tests**

Add tests that construct each visualization, encode/decode it, and dispatch via `CardType.relationship.decode`. Use this exact public API:

```swift
let payload = RelationshipPayload(
    title: "Cost × outcome",
    visualization: .scatter,
    xAxis: .init(label: "Cost", unit: "USD"),
    yAxis: .init(label: "Completion proxy", unit: "%"),
    points: [.init(label: "AIDash", x: 2.1, y: 88, magnitude: 34, category: "project")],
    cells: [],
    slopes: [],
    sampleSize: 34,
    timeWindow: "7d",
    metricDefinition: "pipeline completion proxy",
    summary: "Observed frontier candidate."
)
```

Expected first commit attempt: Core hook fails because the type does not exist.

- [ ] **Step 2: Write failing invariant tests**

Cover:

```swift
// scatter rejects empty points and non-empty cells/slopes
// heatmap rejects empty cells and non-empty points/slopes
// slope rejects empty slopes and non-empty points/cells
// sampleSize rejects values < 1
// timeWindow, metricDefinition, axis labels reject trimmed-empty strings
// x/y/value/before/after/magnitude reject non-finite values; magnitude rejects <= 0
```

Assert `XPCError.code == "schema.payload_decode_failed"` and the exact offending field.

- [ ] **Step 3: Implement the minimal schema**

Create:

```swift
public enum RelationshipVisualization: String, Codable, Sendable {
    case scatter, heatmap, slope
}

public struct RelationshipPayload: CardPayloadProtocol {
    public struct Axis: Codable, Sendable { public let label: String; public let unit: String? }
    public struct Point: Codable, Sendable {
        public let label: String; public let x: Double; public let y: Double
        public let magnitude: Double?; public let category: String?
    }
    public struct Cell: Codable, Sendable { public let column: String; public let row: String; public let value: Double }
    public struct Slope: Codable, Sendable { public let label: String; public let before: Double; public let after: Double }
    public let title: String
    public let visualization: RelationshipVisualization
    public let xAxis: Axis
    public let yAxis: Axis
    public let points: [Point]
    public let cells: [Cell]
    public let slopes: [Slope]
    public let sampleSize: Int
    public let timeWindow: String
    public let metricDefinition: String
    public let summary: String
}
```

Implement public initializers and `validateInvariants()` exactly as specified by Step 2. Add `.relationship` and decode dispatch in `CardType.swift`.

- [ ] **Step 4: Add effective-size tests and implementation**

Required behavior:

```swift
// one scatter point: hero/wide -> medium
// two to four scatter points: hero/wide -> medium
// five or more scatter points: wide remains wide; hero -> wide
// heatmap below 2 rows or 2 columns -> medium
// heatmap with >= 2 rows and >= 2 columns -> wide
// slope with 1 item -> medium; 2+ -> wide
// authored small/medium never grows
```

Add `relationshipSize(_:)` to `EffectiveCardSize`; do not treat relationship as pass-through.

- [ ] **Step 5: Commit through the Core hook**

```bash
git add Packages/AIDashCore
git commit -m "feat(AIDashCore): add relationship payload"
```

Expected: pre-commit runs AIDashCore build/tests and passes.

---

### Task 3: DesignKit Relationship Classification

**Files:**
- Modify: `Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift`
- Modify: `Packages/DesignKit/Tests/DesignKitTests/ColorSystemTests.swift`

**Interfaces:**
- Produces: `Classification.relationship` consumed by AIDashUI.

- [ ] **Step 1: Write the failing classification test**

Add a golden-value test asserting the new classification resolves to cyan-family colors that remain distinct from metric blue and digest teal:

```swift
#expect(Classification.relationship.color(isDark: false).hexRGB == "#0891B2")
#expect(Classification.relationship.color(isDark: true).hexRGB == "#22D3EE")
```

- [ ] **Step 2: Implement the token**

Add `relationship` to `Classification` and only in this token source map light `#0891B2`, dark `#22D3EE`. Do not add colors in AIDashUI.

- [ ] **Step 3: Commit through the DesignKit hook**

```bash
git add Packages/DesignKit
git commit -m "feat(DesignKit): add relationship classification"
```

Expected: DesignKit build/tests and root SwiftLint pass.

---

### Task 4: AIDashUI Relationship Renderer

**Files:**
- Create: `Packages/AIDashUI/Sources/AIDashUI/CardView/RelationshipCardView.swift`
- Modify: `Packages/AIDashUI/Sources/AIDashUI/CardView/CardRouter.swift`
- Modify: `Packages/AIDashUI/Sources/AIDashUI/DesignTokens.swift`
- Modify: `Packages/AIDashUI/Sources/AIDashUI/Resources/Localizable.xcstrings`
- Create: `Packages/AIDashUI/Tests/AIDashUITests/RelationshipCardViewTests.swift`
- Modify: `Packages/AIDashUI/Tests/AIDashUITests/CardRouterTests.swift`
- Modify: `Packages/AIDashUI/Tests/AIDashUITests/DesignTokensFoundationTests.swift`
- Modify: `Packages/AIDashUI/Tests/AIDashUITests/DesignTokensComplianceTests.swift`
- Modify: `Packages/AIDashUI/Tests/AIDashUITests/SnapshotRenderTests.swift`

**Interfaces:**
- Consumes: `RelationshipPayload`, `Classification.relationship`.
- Produces: accessible scatter/heatmap/slope views with size-invariant typography.

- [ ] **Step 1: Write failing routing/token compliance tests**

Assert:

```swift
#expect(CardType.relationship.iconSymbol == "point.3.connected.trianglepath.dotted")
#expect(CardType.relationship.classification == .relationship)
```

Add a router test with valid scatter JSON. Extend the compliance renderer map to `RelationshipCardView`; require exactly one `.cardChrome` and `CardTypeBadge(type: .relationship)`, and reject inline color literals.

- [ ] **Step 2: Implement badge mapping and routing**

Add `.relationship` cases to `DesignTokens.swift` and:

```swift
case let payload as RelationshipPayload:
    RelationshipCardView(payload: payload, size: effectiveSize, style: card.style)
```

- [ ] **Step 3: Implement the chart shell**

`RelationshipCardView` structure:

```swift
VStack(alignment: .leading, spacing: AIDashSpace.s12) {
    header // badge + title + sample/window metadata
    responsiveContent // chart plus evidence rail when width supports it
}
.cardChrome(size: size, style: style)
```

Use `ViewThatFits(in: .horizontal)` for `HStack(chart, evidenceRail)` then `VStack(chart, evidenceRail)`. This is viewport adaptation, not a `size` typography branch.

- [ ] **Step 4: Implement visualization-specific marks**

- Scatter: `PointMark(x:y:)`, symbol size from optional magnitude, foreground from `theme.chart(categoryIndex)`.
- Heatmap: `RectangleMark(x:y:)`, opacity/intensity normalized against finite min/max; a flat domain uses the midpoint token strength rather than division by zero.
- Slope: `LineMark` and `PointMark` for before/after, one categorical color per item.
- Hide axes only where labels would repeat payload metadata; otherwise use localized axis labels.
- Evidence rail always shows `summary`, `n=<sampleSize>`, `timeWindow`, and `metricDefinition`.

- [ ] **Step 5: Add accessibility and previews**

Add String Catalog keys for chart summaries and VoiceOver values. Combine each point/cell/slope into one accessibility element. Add at least two previews per visualization: medium and wide, with light/dark coverage across the set.

- [ ] **Step 6: Commit through the AIDashUI hook**

```bash
git add Packages/AIDashUI
git commit -m "feat(AIDashUI): render relationship cards"
```

Expected: AIDashUI build/tests and SwiftLint pass.

---

### Task 5: aidata Data Profiling, Information Budget, and Relationship Production

**Files:**
- Create: `aidata/L4_serve/queries/attribution/rework-relationship.sql`
- Create: `aidata/L5_apps/digest/card_policy.py`
- Modify: `aidata/L5_apps/digest/sources.py`
- Modify: `aidata/L5_apps/digest/aidash.py`
- Create: `aidata/tests/test_card_policy.py`
- Create: `aidata/tests/test_relationship_sources.py`
- Modify: `aidata/tests/test_digest_aidash.py`
- Modify: `aidata/tests/test_digest_golden.py`
- Modify: `aidata/tests/test_batch2_cards.py`

**Interfaces:**
- Consumes: relationship JSON contract from Task 2.
- Produces: a briefing capped by value budget, with relationship cards only when the data genuinely supports them.

- [ ] **Step 1: Write failing pure-policy tests**

Define and test:

```python
@dataclass(frozen=True)
class DataProfile:
    semantic: Literal["scalar", "timeseries", "ranking", "composition", "relationship", "narrative", "actions"]
    item_count: int
    dimensions: int
    row_count: int = 0
    column_count: int = 0
    relationship_kind: Literal["scatter", "heatmap", "slope"] | None = None

@dataclass(frozen=True)
class CardDecision:
    card_type: str
    size: str
    visualization: str | None
    reason: str

@dataclass(frozen=True)
class CardCandidate:
    card: Card
    order: int
    requires_action: bool
    is_anomaly: bool
    cross_signal_strength: int
    freshness: int
    source_coverage: int
    reading_cost: int

def choose_card(profile: DataProfile) -> CardDecision:
    if profile.item_count < 1:
        raise ValueError("item_count must be positive")
    if profile.semantic in {"scalar", "timeseries"}:
        size = "small" if profile.item_count == 1 else "medium" if profile.item_count <= 4 else "wide"
        return CardDecision("metric", size, "series" if profile.semantic == "timeseries" else None, "numeric metric shape")
    if profile.semantic == "ranking":
        return CardDecision("barList", "medium" if profile.item_count <= 4 else "wide", None, "ordered Top-N shape")
    if profile.semantic == "composition":
        return CardDecision("stackedBar", "medium" if profile.item_count <= 4 else "wide", None, "parts-of-whole shape")
    if profile.semantic == "relationship":
        if profile.dimensions != 2 or profile.relationship_kind is None:
            raise ValueError("relationship requires two dimensions and an explicit kind")
        rich = profile.item_count >= 5 or (profile.row_count >= 2 and profile.column_count >= 2)
        return CardDecision("relationship", "wide" if rich else "medium", profile.relationship_kind, "typed two-dimensional relationship")
    if profile.semantic == "actions":
        return CardDecision("todoList", "medium" if profile.item_count <= 3 else "wide", None, "bounded action set")
    return CardDecision("digest" if profile.item_count > 1 else "insight", "wide" if profile.item_count > 1 else "medium", None, "narrative content")

def select_with_budget(candidates: Sequence[CardCandidate], max_cards: int = 10, first_screen: int = 6) -> list[CardCandidate]:
    ranked = sorted(
        candidates,
        key=lambda candidate: (
            -int(candidate.requires_action),
            -int(candidate.is_anomaly),
            -candidate.cross_signal_strength,
            -candidate.freshness,
            -candidate.source_coverage,
            candidate.reading_cost,
            candidate.order,
            candidate.card.id,
        ),
    )
    selected = ranked[:max_cards]
    lead = selected[:first_screen]
    tail = sorted(selected[first_screen:], key=lambda candidate: (candidate.order, candidate.card.id))
    return lead + tail
```

Test the approved matrix: scalar→metric/small; ranking→barList with medium/wide by count; composition→stackedBar; two-dimensional relationship→relationship with scatter/heatmap/slope selected from explicit relationship kind; narrative→insight/digest; actions→todoList capped at 3. Reject invalid dimensions and never choose hero from count alone.

- [ ] **Step 2: Implement the minimal policy**

Use explicit mappings and named thresholds. Candidate priority tuple:

```python
(requires_action, is_anomaly, cross_signal_strength, freshness, source_coverage, -reading_cost)
```

`select_with_budget` must preserve deterministic ordering, cap the first-screen set at 6 and total at 10, and omit stable detail cards with no action/anomaly/cross value.

- [ ] **Step 3: Write the failing L4 relationship-source test**

Use a temporary SQLite fixture containing issues/runs/workspaces/root causes. Assert query rows expose:

```text
workspace_id, root_cause, issues, rework_tokens, sample_size, window_start, window_end
```

Assert totals do not duplicate one issue's tokens across multiple root causes.

- [ ] **Step 4: Implement the SQL and degrade-safe source bundle**

Add:

```python
@dataclass(frozen=True)
class RelationshipCell:
    row: str
    column: str
    value: float

@dataclass(frozen=True)
class ReworkRelationship:
    cells: list[RelationshipCell]
    sample_size: int
    time_window: str
    health: SourceHealth
```

`fetch_rework_relationship()` returns an empty bundle plus non-ok health on missing DB/query failure and never raises.

- [ ] **Step 5: Write failing briefing tests**

Test:

- fewer than two rows or columns omits/downgrades relationship output;
- a 2×2+ matrix emits `type="relationship"`, `size="wide"`, `visualization="heatmap"`;
- payload includes sample size, time window, metric definition, and correlation-safe summary;
- briefing contains at most 6 first-screen candidates and 10 total cards;
- actions are capped at 3;
- redundant raw token/cost cards are omitted when a stronger outcome×token signal exists;
- missing sources still produce a valid overview briefing.

- [ ] **Step 6: Integrate the policy into `build_briefing`**

Replace unconditional container appends with candidate construction plus `select_with_budget`. Preserve stable UUID generation. Keep news/reference candidates at tail priority. Build relationship payloads directly from structured bundles, never by parsing prose.

- [ ] **Step 7: Update frozen fixtures and golden output**

Freeze every new `fetch_*` seam in `test_digest_golden.py`; regenerate the expected semantic golden content deliberately. The test must assert the new card count and relationship payload, not only Markdown text.

- [ ] **Step 8: Commit through the aidata hook**

```bash
git add aidata
git commit -m "feat(aidata): choose briefing cards from data shape"
```

Expected: Python-relevant hook/CI checks see tests and code together; no Swift package is modified in this commit.

---

### Task 6: Contract Sync, Rendered Review, and Push Gate

**Files:**
- Modify only if a gate exposes drift: the owning layer files from Tasks 1–5.
- Create: `design/prototype-shots/data-driven-briefing-dark.png`
- Create: `design/prototype-shots/data-driven-briefing-light.png`

**Interfaces:**
- Consumes: the complete cross-layer feature.
- Produces: contract evidence, rendered screenshots, design-review score, and pre-push verification.

- [ ] **Step 1: Run the cross-language contract lint**

```bash
.claude/skills/aidash-content/scripts/contract_check.sh
```

Expected: aidata mapper, Core CardType, XPC schema list, and CardRouter all include `relationship`.

- [ ] **Step 2: Render production screenshots**

Use the existing hostless snapshot/render path from `SnapshotRenderTests` or its rendering helper. Produce light/dark screenshots with real-shaped fixture data, including small metrics, one medium ranking, and a wide relationship card. Do not launch host-based `AIDashAppTests`.

- [ ] **Step 3: Run the my-designer objective gate**

Give both PNGs and `design/north-star.md` to `design-reviewer`. Required result: at least 30/35, zero P0. Fix any P0/P1 in the owning layer and commit that layer separately.

- [ ] **Step 4: Push normally to trigger the full pre-push gate**

```bash
git push -u origin feat/token-eval-dashboard
```

Expected pre-push signal: frontmatter, require-tests, root SwiftLint, AIDashCore tests, XcodeGen, AIDashApp build, and aidash CLI build all pass. Never use `--no-verify` for these code changes.

- [ ] **Step 5: Report evidence**

Record commit hashes by layer, hook summaries, contract-check result, design-review score, and any remaining data gaps (especially objective eval coverage and provider cache pricing coverage).
