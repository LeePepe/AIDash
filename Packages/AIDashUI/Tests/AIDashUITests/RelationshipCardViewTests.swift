import Testing
import SwiftUI
import Foundation
import AIDashCore
import DesignKit
@testable import AIDashUI

@MainActor
@Suite("RelationshipCardView Tests")
struct RelationshipCardViewTests {

    // MARK: - Fixtures

    static func scatter(points: Int = 5) -> RelationshipPayload {
        RelationshipPayload(
            title: "Cost × outcome",
            visualization: .scatter,
            xAxis: .init(label: "Cost per completed task", unit: "USD"),
            yAxis: .init(label: "First-pass completion proxy", unit: "%"),
            points: (0..<points).map { i in
                .init(
                    label: "project-\(i)",
                    x: Double(i) * 1.5 + 0.5,
                    y: 60 + Double(i) * 6,
                    magnitude: Double(i + 1) * 8,
                    category: i.isMultiple(of: 2) ? "project" : "workspace"
                )
            },
            sampleSize: 34,
            timeWindow: "7d",
            metricDefinition: "completed is a pipeline proxy, not objective correctness",
            summary: "AIDash has the lowest observed cost at the highest completion proxy."
        )
    }

    static func heatmap(values: [Double] = [12, 48, 3, 27]) -> RelationshipPayload {
        RelationshipPayload(
            title: "Rework concentration",
            visualization: .heatmap,
            xAxis: .init(label: "Day"),
            yAxis: .init(label: "Workspace"),
            cells: values.enumerated().map { i, v in
                .init(column: "2026-08-\(10 + i % 2)", row: i < 2 ? "AIDash" : "Financial", value: v)
            },
            sampleSize: 4,
            timeWindow: "7d",
            metricDefinition: "tokens on issues completed after cancellation",
            summary: "Observed rework is concentrated on one day; no causal claim."
        )
    }

    static func slope(items: Int = 3) -> RelationshipPayload {
        RelationshipPayload(
            title: "Before × after",
            visualization: .slope,
            xAxis: .init(label: "Period"),
            yAxis: .init(label: "Tokens per completed task"),
            slopes: (0..<items).map { i in
                .init(label: "series-\(i)", before: 21_000 - Double(i) * 900, after: 18_000 + Double(i) * 400)
            },
            sampleSize: 12,
            timeWindow: "previous 7d vs current 7d",
            metricDefinition: "total tokens divided by completed pipeline tasks",
            summary: "Observed unit token use decreased."
        )
    }

    static func payload(for visualization: RelationshipVisualization) -> RelationshipPayload {
        switch visualization {
        case .scatter: return scatter()
        case .heatmap: return heatmap()
        case .slope:   return slope()
        }
    }

    /// An empty-marks payload. `validateInvariants()` would reject it, but the
    /// router only DECODES (it never validates), so a published payload with
    /// no marks does reach the renderer and must degrade, not crash.
    static func emptyMarks(_ visualization: RelationshipVisualization) -> RelationshipPayload {
        RelationshipPayload(
            title: "Empty",
            visualization: visualization,
            xAxis: .init(label: "X"),
            yAxis: .init(label: "Y"),
            sampleSize: 1,
            timeWindow: "7d",
            metricDefinition: "definition",
            summary: "summary"
        )
    }

    // MARK: - Rendering

    @Test(
        "body materialises for every visualization × size",
        arguments: RelationshipVisualization.allCases, CardSize.allCases
    )
    func bodyRendersEveryVisualizationAndSize(
        visualization: RelationshipVisualization,
        size: CardSize
    ) {
        _ = RelationshipCardView(
            payload: Self.payload(for: visualization), size: size, style: .neutral
        ).body
    }

    @Test("body materialises for every style", arguments: CardStyle.allCases)
    func bodyRendersEveryStyle(style: CardStyle) {
        _ = RelationshipCardView(payload: Self.scatter(), size: .wide, style: style).body
    }

    @Test(
        "a payload with no marks materialises the empty state without crashing",
        arguments: RelationshipVisualization.allCases
    )
    func emptyMarksRender(visualization: RelationshipVisualization) {
        _ = RelationshipCardView(
            payload: Self.emptyMarks(visualization), size: .medium, style: .neutral
        ).body
    }

    @Test("a single-mark payload materialises (degenerate axis domain must not blank the chart)")
    func singleMarkRenders() {
        _ = RelationshipCardView(payload: Self.scatter(points: 1), size: .medium, style: .neutral).body
        _ = RelationshipCardView(payload: Self.heatmap(values: [7]), size: .medium, style: .neutral).body
        _ = RelationshipCardView(payload: Self.slope(items: 1), size: .medium, style: .neutral).body
    }

    // MARK: - Heatmap intensity (flat domain must not divide by zero)

    @Test("flat heatmap domain resolves to the midpoint strength rather than dividing by zero")
    func heatmapFlatDomain() {
        let flat = [12.0, 12.0, 12.0]
        let domain = RelationshipHeatmapScale.domain(flat)
        #expect(domain.min == 12 && domain.max == 12)
        let strength = RelationshipHeatmapScale.strength(for: 12, in: domain)
        #expect(strength == RelationshipHeatmapScale.flatStrength)
        #expect(strength.isFinite)
        // Every flat cell gets the same finite strength — no NaN, no invisible cell.
        for value in flat {
            let s = RelationshipHeatmapScale.strength(for: value, in: domain)
            #expect(s.isFinite && s > 0)
        }
    }

    @Test("heatmap strength maps min→floor, max→ceiling and stays monotonic in between")
    func heatmapStrengthRamp() {
        let domain = RelationshipHeatmapScale.domain([0, 50, 100])
        #expect(domain.min == 0 && domain.max == 100)
        let low = RelationshipHeatmapScale.strength(for: 0, in: domain)
        let mid = RelationshipHeatmapScale.strength(for: 50, in: domain)
        let high = RelationshipHeatmapScale.strength(for: 100, in: domain)
        #expect(low == RelationshipHeatmapScale.minStrength)
        #expect(high == RelationshipHeatmapScale.maxStrength)
        #expect(low < mid && mid < high)
        // Out-of-domain values clamp instead of overshooting into >1 opacity.
        #expect(RelationshipHeatmapScale.strength(for: -10, in: domain) == RelationshipHeatmapScale.minStrength)
        #expect(RelationshipHeatmapScale.strength(for: 999, in: domain) == RelationshipHeatmapScale.maxStrength)
    }

    @Test("heatmap domain of an empty cell set is flat (and its strength is still finite)")
    func heatmapEmptyDomain() {
        let domain = RelationshipHeatmapScale.domain([])
        #expect(domain.min == domain.max)
        #expect(RelationshipHeatmapScale.strength(for: 0, in: domain) == RelationshipHeatmapScale.flatStrength)
    }

    // MARK: - Scatter symbol size

    @Test("scatter symbol size: absent magnitude → uniform base size; present magnitude scales monotonically")
    func scatterSymbolSize() {
        let domain = RelationshipSymbolScale.domain([8, 16, 32])
        #expect(RelationshipSymbolScale.size(for: nil, in: domain) == RelationshipSymbolScale.baseSize)
        let small = RelationshipSymbolScale.size(for: 8, in: domain)
        let mid = RelationshipSymbolScale.size(for: 16, in: domain)
        let large = RelationshipSymbolScale.size(for: 32, in: domain)
        #expect(small < mid && mid < large)
        #expect(small >= RelationshipSymbolScale.minSize, "a scaled symbol must never collapse to invisible")
        #expect(large <= RelationshipSymbolScale.maxSize)
    }

    @Test("scatter symbol size with a flat magnitude domain falls back to the base size")
    func scatterSymbolSizeFlatDomain() {
        let domain = RelationshipSymbolScale.domain([5, 5])
        let size = RelationshipSymbolScale.size(for: 5, in: domain)
        #expect(size == RelationshipSymbolScale.baseSize)
        #expect(size.isFinite)
    }

    // MARK: - Categorical colors come from the theme

    @Test("scatter categories map to chartCategorical slots in first-appearance order")
    func categoryPaletteOrder() {
        let labels = ["project", "workspace", "project", "agent"]
        #expect(RelationshipCategoryPalette.slot(for: "project", in: labels) == 0)
        #expect(RelationshipCategoryPalette.slot(for: "workspace", in: labels) == 1)
        #expect(RelationshipCategoryPalette.slot(for: "agent", in: labels) == 2)
        // An absent / nil category is a single-series scatter — slot 0.
        #expect(RelationshipCategoryPalette.slot(for: nil, in: labels) == 0)
        #expect(RelationshipCategoryPalette.slot(for: "unknown", in: labels) == 0)
    }

    @Test("every color the renderer resolves comes from theme tokens, never a literal")
    func colorsComeFromTheme() {
        let theme = Theme(seed: .lime, neutral: .slate, isDark: true)
        #expect(RelationshipCategoryPalette.color(slot: 0, theme: theme) == theme.chartCategorical(0))
        #expect(RelationshipCategoryPalette.color(slot: 1, theme: theme) == theme.chartCategorical(1))
        #expect(RelationshipHeatmapScale.baseColor(theme) == theme.classificationTint(.relationship))
    }

    // MARK: - Evidence rail (always complete)

    @Test(
        "evidence rail always carries summary, n=<sampleSize>, timeWindow and metricDefinition",
        arguments: RelationshipVisualization.allCases
    )
    func evidenceRailIsComplete(visualization: RelationshipVisualization) {
        let payload = Self.payload(for: visualization)
        let evidence = RelationshipEvidence(payload: payload)
        #expect(evidence.summary == payload.summary)
        #expect(evidence.sampleText.contains("\(payload.sampleSize)"))
        #expect(evidence.sampleText.contains("n="), "sample count must read as `n=<count>`")
        #expect(evidence.windowText.contains(payload.timeWindow))
        #expect(evidence.definitionText.contains(payload.metricDefinition))
        // All four are non-empty for every visualization — the rail never degrades.
        #expect(evidence.rows.count == 4)
        #expect(evidence.rows.allSatisfy { !$0.isEmpty })
    }

    @Test("the evidence rail is size-invariant — the same four rows at every geometry")
    func evidenceRailSizeInvariant() {
        let payload = Self.scatter()
        let rows = RelationshipEvidence(payload: payload).rows
        for size in CardSize.allCases {
            _ = RelationshipCardView(payload: payload, size: size, style: .neutral).body
            #expect(RelationshipEvidence(payload: payload).rows == rows,
                    "size=\(size) must not drop or reword an evidence row")
        }
    }

    // MARK: - Slope series isolation (regression: cross-entity connections)
    //
    // A slope chart draws one 2-point line PER ENTITY. Swift Charts groups
    // marks into series by the `series:` argument, NOT by the enclosing
    // ForEach or by foregroundStyle — so without an explicit discriminator
    // every entity's points collapse into a single series and the renderer
    // connects entity A's "after" to entity B's "before". That produces a
    // zigzag that reads as a real trend but is pure rendering artifact, which
    // is exactly the kind of misleading ink the constitution forbids.
    //
    // These tests pin the series KEY, because the key is what Swift Charts
    // actually groups on. They deliberately include a duplicate-label payload:
    // keying on `slope.label` alone would silently re-merge two same-named
    // entities back into one line.

    @Test("every slope reading carries the series key of its own entity — no two entities share one")
    func slopeSeriesKeysAreUniquePerEntity() {
        let payload = Self.slope(items: 4)
        let keys = payload.slopes.indices.map { RelationshipChart.seriesKey(index: $0, slope: payload.slopes[$0]) }
        #expect(Set(keys).count == payload.slopes.count,
                "each entity must get a distinct series key, else Swift Charts joins them into one line")
    }

    @Test("two entities sharing a display label still get distinct series keys (duplicate-label regression)")
    func slopeSeriesKeysSurviveDuplicateLabels() {
        // Two entities legitimately named the same (e.g. same repo in two
        // orgs). Keying purely on the label would connect them into one line.
        let duplicated = RelationshipPayload(
            title: "Before × after",
            visualization: .slope,
            xAxis: .init(label: "Period"),
            yAxis: .init(label: "Tokens"),
            slopes: [
                .init(label: "AIDash", before: 21_000, after: 18_000),
                .init(label: "AIDash", before: 12_000, after: 15_500),
            ],
            sampleSize: 12,
            timeWindow: "previous 7d vs current 7d",
            metricDefinition: "total tokens divided by completed pipeline tasks",
            summary: "Observed unit token use decreased."
        )
        let keys = duplicated.slopes.indices.map {
            RelationshipChart.seriesKey(index: $0, slope: duplicated.slopes[$0])
        }
        #expect(keys[0] != keys[1],
                "two entities with the same label must NOT collapse into a single series")
        #expect(keys.allSatisfy { $0.contains("AIDash") },
                "the series key must still carry the entity label so the chart stays debuggable")
    }

    @Test("a slope's two readings share ONE series key — the before→after line must connect")
    func slopeReadingsShareTheirOwnSeries() {
        let payload = Self.slope(items: 3)
        var keysSeen: [String] = []
        for (index, slope) in payload.slopes.enumerated() {
            let readings = RelationshipChart.periods(for: slope)
            #expect(readings.count == 2, "a slope is exactly before + after")
            #expect(readings[0].period == RelationshipChart.beforeLabel)
            #expect(readings[1].period == RelationshipChart.afterLabel)
            #expect(readings[0].value == slope.before)
            #expect(readings[1].value == slope.after)
            // The whole entity — both readings — sits under ONE key. Within an
            // entity the line MUST connect; only ACROSS entities must it not.
            keysSeen.append(RelationshipChart.seriesKey(index: index, slope: slope))
        }
        #expect(keysSeen.count == 3)
        #expect(Set(keysSeen).count == 3, "one key per entity, and no key shared between entities")
    }

    @Test("the renderer passes an explicit per-entity series to every slope LineMark")
    func slopeRendererDeclaresSeries() throws {
        let source = try DesignTokensComplianceTests.cardViewSource(named: "RelationshipChart")
        #expect(source.contains("series: .value("),
                "slope LineMarks must declare an explicit series, or Swift Charts joins all entities into one line")
        #expect(source.contains("seriesKey(index:"),
                "the series value must come from the per-entity seriesKey helper")
    }

    @Test("a multi-entity slope payload materialises with every entity isolated")
    func multiEntitySlopeRenders() {
        let payload = Self.slope(items: 5)
        let keys = payload.slopes.indices.map { RelationshipChart.seriesKey(index: $0, slope: payload.slopes[$0]) }
        #expect(Set(keys).count == 5)
        for size in CardSize.allCases {
            _ = RelationshipCardView(payload: payload, size: size, style: .neutral).body
        }
    }

    // MARK: - Accessibility

    @Test("each scatter point becomes one accessible element carrying its label and both axis values")
    func scatterAccessibility() {
        let payload = Self.scatter(points: 2)
        let point = payload.points[0]
        let label = RelationshipAccessibility.pointLabel(point)
        let value = RelationshipAccessibility.pointValue(point, xAxis: payload.xAxis, yAxis: payload.yAxis)
        #expect(label == point.label)
        #expect(value.contains(payload.xAxis.label))
        #expect(value.contains(payload.yAxis.label))
        #expect(!value.isEmpty)
    }

    @Test("each heatmap cell becomes one accessible element naming its row, column and value")
    func heatmapAccessibility() {
        let payload = Self.heatmap()
        let cell = payload.cells[0]
        let label = RelationshipAccessibility.cellLabel(cell)
        #expect(label.contains(cell.row))
        #expect(label.contains(cell.column))
        #expect(RelationshipAccessibility.cellValue(cell).isEmpty == false)
    }

    @Test("each slope becomes one accessible element naming its before and after values")
    func slopeAccessibility() {
        let payload = Self.slope(items: 1)
        let slope = payload.slopes[0]
        let label = RelationshipAccessibility.slopeLabel(slope)
        let value = RelationshipAccessibility.slopeValue(slope)
        #expect(label == slope.label)
        #expect(!value.isEmpty)
    }

    @Test("the chart itself carries a localized summary label for every visualization",
          arguments: RelationshipVisualization.allCases)
    func chartAccessibilityLabel(visualization: RelationshipVisualization) {
        let payload = Self.payload(for: visualization)
        let label = RelationshipAccessibility.chartLabel(payload, visibleCount: Self.markCount(payload))
        #expect(!label.isEmpty)
        #expect(label.contains(payload.title))
    }

    static func markCount(_ payload: RelationshipPayload) -> Int {
        switch payload.visualization {
        case .scatter: return payload.points.count
        case .heatmap: return payload.cells.count
        case .slope:   return payload.slopes.count
        }
    }

    // MARK: - Truncation honesty (regression: capped plot vs announced count)
    //
    // `visibleMarkCap(size)` plots only `prefix(cap)` marks, but the chart's
    // VoiceOver label used to announce the FULL payload count. A sighted user
    // saw 8 points on a small card while VoiceOver said "40 points" — the
    // screen-reader description asserted data that was not on screen. Worse,
    // neither channel disclosed that anything had been dropped at all.

    @Test("when marks are capped, the label announces visible-of-total, not the full payload count")
    func cappedChartLabelReportsBothCounts() {
        let total = 40
        let payload = Self.scatter(points: total)
        let cap = RelationshipDensity.visibleMarkCap(.small)
        #expect(cap < total, "fixture must actually exceed the small-card cap for this to test anything")

        let label = RelationshipAccessibility.chartLabel(payload, visibleCount: cap)
        #expect(label.contains("\(cap)"), "the label must state how many marks are actually plotted")
        #expect(label.contains("\(total)"), "the label must still disclose the true total")
        #expect(RelationshipAccessibility.isTruncated(visible: cap, total: total))
    }

    @Test("when nothing is capped, the label does not claim a truncation")
    func uncappedChartLabelOmitsTruncation() {
        let payload = Self.scatter(points: 5)
        let cap = RelationshipDensity.visibleMarkCap(.wide)
        #expect(cap >= payload.points.count)

        let label = RelationshipAccessibility.chartLabel(payload, visibleCount: payload.points.count)
        #expect(label.contains("\(payload.points.count)"))
        #expect(!RelationshipAccessibility.isTruncated(visible: payload.points.count, total: payload.points.count))
    }

    @Test(
        "every visualization reports a consistent visible-vs-total count when capped",
        arguments: RelationshipVisualization.allCases
    )
    func cappedLabelIsConsistentAcrossVisualizations(visualization: RelationshipVisualization) {
        // Build a payload that exceeds the smallest cap for each shape.
        let cap = RelationshipDensity.visibleMarkCap(.small)
        let payload: RelationshipPayload
        switch visualization {
        case .scatter: payload = Self.scatter(points: cap + 5)
        case .heatmap: payload = Self.heatmap(values: (0..<(cap + 5)).map { Double($0) })
        case .slope:   payload = Self.slope(items: cap + 5)
        }
        let total = Self.markCount(payload)
        #expect(total > cap)

        let label = RelationshipAccessibility.chartLabel(payload, visibleCount: cap)
        #expect(label.contains("\(cap)") && label.contains("\(total)"),
                "\(visualization) must announce both the plotted count and the true total")
    }

    @Test("the renderer passes the CAPPED count to the accessibility label, not the raw payload count")
    func rendererPassesVisibleCount() throws {
        let source = try DesignTokensComplianceTests.cardViewSource(named: "RelationshipChart")
        #expect(source.contains("chartLabel(payload, visibleCount:"),
                "the chart label must be built from the visible (capped) count, or VoiceOver will announce marks that aren't drawn")
    }

    @Test("a truncated card discloses the overflow visually, not only to VoiceOver")
    func truncationIsVisiblyDisclosed() throws {
        let source = try DesignTokensComplianceTests.cardViewSource(named: "RelationshipCardView")
        #expect(source.contains("truncationNotice") || source.contains("RelationshipTruncation"),
                "a sighted user must also be told marks were dropped — VoiceOver-only disclosure is not parity")
        // The notice text itself must carry both numbers.
        let notice = RelationshipAccessibility.truncationNotice(visible: 8, total: 40)
        #expect(notice.contains("8") && notice.contains("40"))
    }

    // MARK: - Missing magnitude must be visually distinct (regression)
    //
    // `magnitude` is optional per point, so a payload can mix points that have
    // it with points that don't. Rendering a missing magnitude as a solid
    // mid-size symbol makes ABSENT data indistinguishable from a genuine
    // mid-low reading — the chart states a third dimension it does not have.
    // Missing values therefore get a distinct treatment (a small hollow
    // symbol), not a medium solid one.

    @Test("in a mixed payload, a missing magnitude does not collide with any real magnitude's symbol size")
    func missingMagnitudeIsNotAMidSizedSymbol() {
        // Domain spans 10...100. Under the plain scale a missing magnitude fell
        // back to `baseSize` (60) — which is exactly what a real reading at
        // ~17% of this domain renders, so absence was indistinguishable from
        // data. The mixed-aware overload is what the renderer actually calls.
        let domain = RelationshipSymbolScale.domain([10, 55, 100])
        let missing = RelationshipSymbolScale.size(for: nil, in: domain, inMixedPayload: true)
        for real in [10.0, 25.0, 55.0, 80.0, 100.0] {
            let realSize = RelationshipSymbolScale.size(for: real, in: domain, inMixedPayload: true)
            #expect(missing != realSize,
                    "a missing magnitude renders the same symbol area as a real reading of \(real)")
        }
        #expect(missing < RelationshipSymbolScale.size(for: 10, in: domain, inMixedPayload: true),
                "missing data must read as smaller than the smallest real reading, never as mid-sized")
        // Pin the old bug explicitly: the mixed path must NOT return baseSize.
        #expect(missing != RelationshipSymbolScale.baseSize,
                "regression: a magnitude-less point must not fall back to the mid-range base size")
    }

    @Test("a missing magnitude renders hollow while every real magnitude renders solid")
    func missingMagnitudeIsHollow() {
        let domain = RelationshipSymbolScale.domain([10, 55, 100])
        #expect(RelationshipSymbolScale.isMissing(magnitude: nil))
        #expect(!RelationshipSymbolScale.isMissing(magnitude: 55))
        // A non-finite magnitude is missing data too, not a zero-size point.
        #expect(RelationshipSymbolScale.isMissing(magnitude: Double.nan))
        _ = domain
    }

    @Test("a payload where NO point carries a magnitude stays uniformly solid (no third dimension claimed)")
    func absentMagnitudeDimensionStaysUniform() {
        // Distinct from the MIXED case: if nobody has a magnitude there is no
        // third dimension at all, so every point is an ordinary solid symbol
        // at the base size — flagging them all as "missing" would be noise.
        let payload = RelationshipPayload(
            title: "No magnitudes",
            visualization: .scatter,
            xAxis: .init(label: "X"), yAxis: .init(label: "Y"),
            points: [
                .init(label: "a", x: 1, y: 2),
                .init(label: "b", x: 2, y: 3),
            ],
            sampleSize: 2, timeWindow: "7d",
            metricDefinition: "definition", summary: "summary"
        )
        #expect(!RelationshipSymbolScale.hasMixedMagnitudes(payload.points))
        for point in payload.points {
            #expect(!RelationshipSymbolScale.isMissing(magnitude: point.magnitude, inMixedPayload: false))
        }
        _ = RelationshipCardView(payload: payload, size: .medium, style: .neutral).body
    }

    @Test("a mixed payload IS detected as mixed, and only the magnitude-less points are flagged")
    func mixedMagnitudeDetection() {
        let mixed: [RelationshipPayload.Point] = [
            .init(label: "has", x: 1, y: 2, magnitude: 30),
            .init(label: "missing", x: 2, y: 3),
        ]
        #expect(RelationshipSymbolScale.hasMixedMagnitudes(mixed))
        #expect(!RelationshipSymbolScale.isMissing(magnitude: mixed[0].magnitude, inMixedPayload: true))
        #expect(RelationshipSymbolScale.isMissing(magnitude: mixed[1].magnitude, inMixedPayload: true))
    }

    @Test("VoiceOver names a missing magnitude rather than silently omitting the dimension")
    func missingMagnitudeIsAnnounced() {
        let withMagnitude = RelationshipPayload.Point(label: "has", x: 1, y: 2, magnitude: 30)
        let without = RelationshipPayload.Point(label: "missing", x: 2, y: 3)
        let axis = RelationshipPayload.Axis(label: "Cost", unit: "USD")

        let announced = RelationshipAccessibility.pointValue(
            without, xAxis: axis, yAxis: axis, inMixedPayload: true
        )
        #expect(announced.lowercased().contains("no ") || announced.lowercased().contains("unavailable"),
                "a mixed payload must tell a VoiceOver user this point has no magnitude")
        let normal = RelationshipAccessibility.pointValue(
            withMagnitude, xAxis: axis, yAxis: axis, inMixedPayload: true
        )
        #expect(!normal.lowercased().contains("unavailable"))
    }

    @Test("the point symbol converts area to diameter honestly (2√(area/π)), so doubled magnitude is not 4× bigger")
    func pointSymbolGeometry() {
        let small = RelationshipPointSymbol(area: 60, isMissing: false, color: .clear)
        let doubled = RelationshipPointSymbol(area: 120, isMissing: false, color: .clear)
        // Area doubles → diameter grows by √2, not by 2.
        let ratio = doubled.diameter / small.diameter
        #expect(abs(ratio - 2.0.squareRoot()) < 0.001,
                "symbol area must map to diameter as 2√(area/π); got ratio \(ratio)")
        #expect(small.diameter > 0)
        // A missing symbol is visibly smaller than any real one.
        let missing = RelationshipPointSymbol(
            area: RelationshipSymbolScale.missingSize, isMissing: true, color: .clear
        )
        let smallestReal = RelationshipPointSymbol(
            area: RelationshipSymbolScale.minSize, isMissing: false, color: .clear
        )
        #expect(missing.diameter < smallestReal.diameter)
        _ = missing.body
        _ = smallestReal.body
    }

    @Test("the hollow 'no magnitude' ring has a perceptible open centre, not a 1pt pinhole")
    func missingSymbolRingIsActuallyHollow() {
        // Regression on the first attempt at this fix: missingSize was 14pt²,
        // giving a 4.2pt disc that a 1.5pt stroke nearly filled — a ~1.2pt
        // hole, which rendered as a tiny SOLID dot. The hollow channel existed
        // in code and was invisible on screen. Caught in the rendered snapshot.
        let missing = RelationshipPointSymbol(
            area: RelationshipSymbolScale.missingSize, isMissing: true, color: .clear
        )
        let hole = missing.diameter - 2 * RelationshipPointSymbol.ringWidth
        #expect(hole >= 4.0,
                "the ring's open centre is \(hole)pt — too small to read as hollow rather than solid")
        // And it must still be smaller than the smallest real symbol.
        let smallestReal = RelationshipPointSymbol(
            area: RelationshipSymbolScale.minSize, isMissing: false, color: .clear
        )
        #expect(missing.diameter < smallestReal.diameter)
    }

    @Test("a mixed-magnitude scatter materialises at every size")
    func mixedMagnitudeRenders() {
        let payload = RelationshipPayload(
            title: "Mixed",
            visualization: .scatter,
            xAxis: .init(label: "X"), yAxis: .init(label: "Y"),
            points: [
                .init(label: "a", x: 1, y: 2, magnitude: 30),
                .init(label: "b", x: 2, y: 3),
                .init(label: "c", x: 3, y: 4, magnitude: 90),
            ],
            sampleSize: 3, timeWindow: "7d",
            metricDefinition: "definition", summary: "summary"
        )
        for size in CardSize.allCases {
            _ = RelationshipCardView(payload: payload, size: size, style: .neutral).body
        }
    }

    // MARK: - Size = geometry + density only (never typography)

    @Test("mark density grows with geometry and never shrinks", arguments: CardSize.allCases)
    func markDensityLadder(size: CardSize) {
        let cap = RelationshipDensity.visibleMarkCap(size)
        #expect(cap >= 1, "every size must show at least one mark")
        #expect(RelationshipDensity.chartHeight(size) > 0)
    }

    @Test("the density ladder is monotonic across the size ladder")
    func markDensityMonotonic() {
        let caps = CardSize.allCases.map { RelationshipDensity.visibleMarkCap($0) }
        let heights = CardSize.allCases.map { RelationshipDensity.chartHeight($0) }
        // CardSize.allCases is declared small → medium → wide → hero.
        #expect(caps == caps.sorted(), "visible mark cap must not decrease as geometry grows")
        #expect(heights == heights.sorted(), "chart height must not decrease as geometry grows")
    }

    @Test("size never changes typography — the recipe is keyed on type only", arguments: CardSize.allCases)
    func typographyIsSizeInvariant(size: CardSize) throws {
        let recipe = AIDashTypography.detail(for: .relationship)
        #expect(recipe.primary == AIDashTypography.detail(for: .relationship).primary)
        #expect(recipe.secondary == AIDashTypography.detail(for: .relationship).secondary)

        // Source guard: no `.font(` may live inside a `switch size` branch.
        let source = try DesignTokensComplianceTests.rendererSource(for: .relationship)
        if let branch = try? DesignTokensComplianceTests.body(
            of: source,
            forCaseLabel: ".\(DesignTokensComplianceTests.rawCase(for: size))",
            inSwitchKey: "size"
        ) {
            #expect(!branch.contains(".font("),
                    "relationship renderer must not select a font inside a `switch size` branch (size=\(size))")
        }
    }

    // MARK: - Renderer chrome / token contract

    @Test("renderer applies the shared cardChrome exactly once and renders the relationship badge")
    func rendererChromeContract() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .relationship)
        #expect(source.contains(".cardChrome(size: size, style: style"),
                "relationship renderer must apply the shared cardChrome modifier")
        #expect(source.contains("CardTypeBadge(type: .relationship)"),
                "relationship renderer must render the shared type badge")
        let chromeCount = source.components(separatedBy: ".cardChrome(").count - 1
        #expect(chromeCount == 1, "relationship renderer must apply cardChrome exactly once")
        let badgeCount = source.components(separatedBy: "CardTypeBadge(type: .relationship)").count - 1
        #expect(badgeCount == 1, "relationship renderer must render exactly one CardTypeBadge")
    }

    @Test("no relationship source file inlines a color literal or a font literal")
    func noInlineColorOrFontLiterals() throws {
        // All FOUR files, not just the two the renderer started as: the token
        // guards must follow the code when it splits, or a literal can hide in
        // whichever file the list forgot.
        for name in [
            "RelationshipCardView", "RelationshipChart",
            "RelationshipScales", "RelationshipEvidence",
        ] {
            let source = try DesignTokensComplianceTests.cardViewSource(named: name)
            #expect(!source.contains("Color(hex:"),
                    "\(name) must not inline hex colors — resolve them from the Theme")
            #expect(!source.contains("Color(red:"),
                    "\(name) must not inline RGB colors — resolve them from the Theme")
            #expect(!source.contains(".font(.system(size:"),
                    "\(name) must not hardcode a font size — read AIDashTypography.detail(for:)")
        }
    }

    @Test("renderer reads typography from the per-type recipe and colors from the injected Theme")
    func rendererReadsTokens() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .relationship)
        #expect(source.contains("AIDashTypography.detail(for: .relationship)"),
                "relationship renderer must read typography from the per-type recipe")
        #expect(source.contains("@Environment(\\.theme)"),
                "relationship renderer must resolve colors from the injected Theme")
    }

    @Test("layout adapts responsively via ViewThatFits, not by branching typography on size")
    func responsiveLayoutContract() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .relationship)
        #expect(source.contains("ViewThatFits(in: .horizontal)"),
                "the chart + evidence rail must adapt via ViewThatFits(in: .horizontal)")
        #expect(!source.contains("switch style"),
                "style is consumed by the shared cardChrome modifier, not the renderer")
    }

    @Test("relationship spacing comes from the ladder, not freshly-typed numbers")
    func spacingComesFromLadder() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .relationship)
        #expect(source.contains("AIDashSpace."),
                "relationship renderer must take its spacing from the AIDashSpace ladder")
        #expect(!source.contains(".padding(16)") && !source.contains(".padding(12)"),
                "relationship renderer must not inline raw padding values")
    }
}
