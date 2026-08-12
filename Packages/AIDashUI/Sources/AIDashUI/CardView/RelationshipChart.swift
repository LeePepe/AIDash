import SwiftUI
import Charts
import AIDashCore
import DesignKit

// MARK: - RelationshipHeatmapScale
//
// Maps a cell value to the *strength* (0…1) its rectangle is drawn at. The
// intensity channel is a single-hue ramp on the relationship classification
// tint, so a heatmap never invents a second color language.
//
// The domain is derived from the finite cell values. A FLAT domain (every
// cell equal, or a single cell, or no cells at all) would divide by zero in
// the naive `(v - min) / (max - min)` normalization — and a NaN opacity
// blanks the entire chart, not just one cell. The flat case therefore
// resolves to a fixed midpoint strength: every cell reads identically,
// which is exactly what "all values are equal" means.

enum RelationshipHeatmapScale {

    struct Domain: Equatable {
        let min: Double
        let max: Double

        /// True when the domain has no spread to normalize against.
        var isFlat: Bool { !(max > min) }
    }

    /// Weakest rendered strength. Kept well above zero so the coldest cell is
    /// still a visible mark rather than a hole in the matrix.
    static let minStrength: Double = 0.14
    /// Strongest rendered strength. Below 1 so the hottest cell stays a tinted
    /// surface rather than a saturated block that fights the card chrome.
    static let maxStrength: Double = 0.92
    /// Strength used when the domain is flat — the midpoint of the ramp.
    static let flatStrength: Double = (minStrength + maxStrength) / 2

    /// Domain over the finite values only. Non-finite values are rejected by
    /// `RelationshipPayload.validateInvariants()`, but the renderer decodes
    /// without validating, so they are filtered here too.
    static func domain(_ values: [Double]) -> Domain {
        let finite = values.filter(\.isFinite)
        guard let lo = finite.min(), let hi = finite.max() else {
            return Domain(min: 0, max: 0)
        }
        return Domain(min: lo, max: hi)
    }

    /// Strength for one cell, clamped into `[minStrength, maxStrength]`.
    static func strength(for value: Double, in domain: Domain) -> Double {
        guard value.isFinite else { return flatStrength }
        guard !domain.isFlat else { return flatStrength }
        let t = (value - domain.min) / (domain.max - domain.min)
        let clamped = Swift.min(Swift.max(t, 0), 1)
        return minStrength + clamped * (maxStrength - minStrength)
    }

    /// The single hue the ramp is built on — the card type's own classification
    /// token, resolved from the injected Theme (never a literal).
    static func baseColor(_ theme: Theme) -> Color {
        theme.classificationTint(.relationship)
    }
}

// MARK: - RelationshipSymbolScale
//
// Scatter symbol area from the optional `magnitude` third dimension. Symbol
// AREA is proportional to magnitude (Swift Charts' `symbolSize` takes an
// area), which is the perceptually honest mapping — scaling the radius
// instead exaggerates large values quadratically.
//
// A payload without magnitudes, or with a flat magnitude domain, gets a
// uniform base size: there is no third dimension to encode, so pretending
// there is one would be a lie in ink.

enum RelationshipSymbolScale {

    typealias Domain = RelationshipHeatmapScale.Domain

    /// Symbol area for a uniform (no magnitude) scatter.
    static let baseSize: Double = 60
    /// Floor for a scaled symbol — below this a point stops being clickable
    /// or even visible at card scale.
    static let minSize: Double = 28
    /// Ceiling for a scaled symbol, so one outlier cannot swallow its neighbors.
    static let maxSize: Double = 220

    static func domain(_ magnitudes: [Double]) -> Domain {
        RelationshipHeatmapScale.domain(magnitudes)
    }

    static func size(for magnitude: Double?, in domain: Domain) -> Double {
        guard let magnitude, magnitude.isFinite else { return baseSize }
        guard !domain.isFlat else { return baseSize }
        let t = (magnitude - domain.min) / (domain.max - domain.min)
        let clamped = Swift.min(Swift.max(t, 0), 1)
        return minSize + clamped * (maxSize - minSize)
    }
}

// MARK: - RelationshipCategoryPalette
//
// Resolves a scatter point's optional `category` to a categorical color slot.
// Slots are assigned in FIRST-APPEARANCE order over the payload's own category
// sequence, so the legend reads top-to-bottom in the order the author wrote
// the points. A nil or unknown category is a single-series scatter → slot 0.
//
// The color itself always comes from `Theme.chartCategorical`, whose remap
// keeps the first categories ≥40° apart in hue and clear of the semantic
// hues — the same rule stackedBar's pure-category segments follow.

enum RelationshipCategoryPalette {

    /// Distinct categories in first-appearance order.
    static func ordered(_ categories: [String?]) -> [String] {
        var seen: Set<String> = []
        var order: [String] = []
        for case let category? in categories where !category.isEmpty {
            if seen.insert(category).inserted { order.append(category) }
        }
        return order
    }

    static func slot(for category: String?, in categories: [String?]) -> Int {
        guard let category, !category.isEmpty else { return 0 }
        return ordered(categories).firstIndex(of: category) ?? 0
    }

    static func color(slot: Int, theme: Theme) -> Color {
        theme.chartCategorical(slot)
    }
}

// MARK: - RelationshipDensity
//
// `size` is geometry and visible density ONLY (constitution §Size = Geometry
// Only): a smaller card plots fewer marks and stands shorter, but every mark
// it does plot is drawn at the same type scale. Nothing here returns a Font.

enum RelationshipDensity {

    /// How many marks a given geometry plots before truncating. Monotonic in
    /// the size ladder — a bigger card never shows fewer marks.
    static func visibleMarkCap(_ size: CardSize) -> Int {
        switch size {
        case .small:  return 8
        case .medium: return 16
        case .wide:   return 40
        case .hero:   return 80
        }
    }

    /// Plot height. Monotonic in the size ladder, and always below the size's
    /// own min-height so the evidence rail still has room to sit beside or
    /// under the chart.
    static func chartHeight(_ size: CardSize) -> CGFloat {
        switch size {
        case .small:  return 96
        case .medium: return 120
        case .wide:   return 160
        case .hero:   return 220
        }
    }

    /// Minimum width the evidence rail needs before `ViewThatFits` is willing
    /// to place it BESIDE the chart. Narrower than this and the horizontal
    /// candidate is rejected, so the rail drops below the chart at full width
    /// rather than squeezing into an unreadable column.
    static let evidenceRailMinWidth: CGFloat = 200
    /// Minimum width the chart itself needs in the side-by-side candidate.
    static let chartMinWidth: CGFloat = 220
}

// MARK: - RelationshipEvidence
//
// The evidence rail's content. Constitution §Relationship visualization makes
// `sampleSize`, `timeWindow`, and `metricDefinition` mandatory *and* the
// summary is the card's actual claim — so all four rows render at EVERY size.
// Density reduction is a mark-count lever, never an evidence lever: dropping
// `n=` on a small card would turn an evidenced association back into a bare
// assertion.

struct RelationshipEvidence: Equatable {
    let summary: String
    let sampleText: String
    let windowText: String
    let definitionText: String

    init(payload: RelationshipPayload) {
        summary = payload.summary
        sampleText = Self.sampleLabel(payload.sampleSize)
        windowText = Self.windowLabel(payload.timeWindow)
        definitionText = Self.definitionLabel(payload.metricDefinition)
    }

    /// The four rows in render order. Every one is non-empty by construction
    /// (the payload's invariants require non-empty text and a positive count).
    var rows: [String] { [summary, sampleText, windowText, definitionText] }

    // MARK: Localized strings

    static func sampleLabel(_ sampleSize: Int) -> String {
        String(
            localized: "relationship.evidence.sample",
            defaultValue: "n=\(sampleSize)",
            bundle: .module,
            comment: "Sample-size row of a relationship card's evidence rail. The integer is the number of underlying observations."
        )
    }

    static func windowLabel(_ timeWindow: String) -> String {
        String(
            localized: "relationship.evidence.window",
            defaultValue: "Window: \(timeWindow)",
            bundle: .module,
            comment: "Observation-window row of a relationship card's evidence rail. The placeholder is an author-written window such as `7d`."
        )
    }

    static func definitionLabel(_ metricDefinition: String) -> String {
        String(
            localized: "relationship.evidence.definition",
            defaultValue: "Measures: \(metricDefinition)",
            bundle: .module,
            comment: "Metric-definition row of a relationship card's evidence rail. The placeholder states what the plotted metric actually measures."
        )
    }
}

// MARK: - RelationshipAccessibility
//
// VoiceOver strings. Swift Charts renders one composite image by default, so
// each mark is given its own combined accessibility element (label = what it
// is, value = the numbers) and the plot as a whole carries a summary label.

enum RelationshipAccessibility {

    // MARK: Chart-level

    static func chartLabel(_ payload: RelationshipPayload) -> String {
        switch payload.visualization {
        case .scatter: return scatterChartLabel(payload.title, count: payload.points.count)
        case .heatmap: return heatmapChartLabel(payload.title, count: payload.cells.count)
        case .slope:   return slopeChartLabel(payload.title, count: payload.slopes.count)
        }
    }

    static func scatterChartLabel(_ title: String, count: Int) -> String {
        String(
            localized: "relationship.a11y.chart.scatter",
            defaultValue: "\(title). Scatter plot of \(count) points.",
            bundle: .module,
            comment: "VoiceOver label for a relationship card's scatter plot. First placeholder is the card title, second is the number of plotted points."
        )
    }

    static func heatmapChartLabel(_ title: String, count: Int) -> String {
        String(
            localized: "relationship.a11y.chart.heatmap",
            defaultValue: "\(title). Heatmap of \(count) cells.",
            bundle: .module,
            comment: "VoiceOver label for a relationship card's heatmap. First placeholder is the card title, second is the number of cells."
        )
    }

    static func slopeChartLabel(_ title: String, count: Int) -> String {
        String(
            localized: "relationship.a11y.chart.slope",
            defaultValue: "\(title). Slope chart of \(count) series.",
            bundle: .module,
            comment: "VoiceOver label for a relationship card's slope chart. First placeholder is the card title, second is the number of before/after series."
        )
    }

    // MARK: Mark-level

    static func pointLabel(_ point: RelationshipPayload.Point) -> String {
        point.label
    }

    static func pointValue(
        _ point: RelationshipPayload.Point,
        xAxis: RelationshipPayload.Axis,
        yAxis: RelationshipPayload.Axis
    ) -> String {
        let x = axisReading(axis: xAxis, value: point.x)
        let y = axisReading(axis: yAxis, value: point.y)
        return String(
            localized: "relationship.a11y.point.value",
            defaultValue: "\(x), \(y)",
            bundle: .module,
            comment: "VoiceOver value for one scatter point: the x-axis reading followed by the y-axis reading."
        )
    }

    static func cellLabel(_ cell: RelationshipPayload.Cell) -> String {
        String(
            localized: "relationship.a11y.cell.label",
            defaultValue: "\(cell.row), \(cell.column)",
            bundle: .module,
            comment: "VoiceOver label for one heatmap cell: its row then its column."
        )
    }

    static func cellValue(_ cell: RelationshipPayload.Cell) -> String {
        RelationshipFormat.value(cell.value)
    }

    static func slopeLabel(_ slope: RelationshipPayload.Slope) -> String {
        slope.label
    }

    static func slopeValue(_ slope: RelationshipPayload.Slope) -> String {
        String(
            localized: "relationship.a11y.slope.value",
            defaultValue: "before \(RelationshipFormat.value(slope.before)), after \(RelationshipFormat.value(slope.after))",
            bundle: .module,
            comment: "VoiceOver value for one slope series: its before reading then its after reading."
        )
    }

    /// "<axis label> <value><unit>" — the unit is display-only and appended
    /// verbatim, exactly as the payload contract specifies (no conversion).
    static func axisReading(axis: RelationshipPayload.Axis, value: Double) -> String {
        let reading = RelationshipFormat.value(value)
        guard let unit = axis.unit, !unit.isEmpty else {
            return "\(axis.label) \(reading)"
        }
        return "\(axis.label) \(reading) \(unit)"
    }
}

// MARK: - RelationshipFormat
//
// Compact numeric read-out shared by the axis labels and the VoiceOver
// strings, so a value never reads one way on screen and another aloud.

enum RelationshipFormat {
    static func value(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        if v == v.rounded() && abs(v) < 1_000_000 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }
}

// MARK: - RelationshipChart
//
// The plot itself. One `Chart` per visualization, each drawing ONLY the mark
// collection its `visualization` discriminator owns — the same exclusivity
// `RelationshipPayload.validateMarkSet()` enforces on the schema side.
//
// Marks are capped by `RelationshipDensity.visibleMarkCap(size)`: geometry
// controls how much of the payload is plotted, never how large the type is.

struct RelationshipChart: View {
    let payload: RelationshipPayload
    let size: CardSize
    @Environment(\.theme) private var theme

    var body: some View {
        chart
            .frame(height: RelationshipDensity.chartHeight(size))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(RelationshipAccessibility.chartLabel(payload))
    }

    @ViewBuilder
    private var chart: some View {
        switch payload.visualization {
        case .scatter: scatterChart
        case .heatmap: heatmapChart
        case .slope:   slopeChart
        }
    }

    // MARK: Scatter

    private var scatterChart: some View {
        let points = Array(payload.points.prefix(cap))
        let categories = points.map(\.category)
        let magnitudes = points.compactMap(\.magnitude)
        let symbolDomain = RelationshipSymbolScale.domain(magnitudes)
        return Chart(Array(points.enumerated()), id: \.offset) { index, point in
            PointMark(
                x: .value(payload.xAxis.label, point.x),
                y: .value(payload.yAxis.label, point.y)
            )
            .symbolSize(RelationshipSymbolScale.size(for: point.magnitude, in: symbolDomain))
            .foregroundStyle(
                RelationshipCategoryPalette.color(
                    slot: RelationshipCategoryPalette.slot(for: point.category, in: categories),
                    theme: theme
                )
            )
            .accessibilityIdentifier("relationship.point.\(index)")
            .accessibilityLabel(RelationshipAccessibility.pointLabel(point))
            .accessibilityValue(
                RelationshipAccessibility.pointValue(
                    point, xAxis: payload.xAxis, yAxis: payload.yAxis
                )
            )
        }
        .chartXAxisLabel(payload.xAxis.label, position: .bottom)
        .chartYAxisLabel(payload.yAxis.label, position: .top, alignment: .leading)
        .chartLegend(.hidden)
    }

    // MARK: Heatmap

    private var heatmapChart: some View {
        let cells = Array(payload.cells.prefix(cap))
        let domain = RelationshipHeatmapScale.domain(cells.map(\.value))
        let base = RelationshipHeatmapScale.baseColor(theme)
        return Chart(Array(cells.enumerated()), id: \.offset) { index, cell in
            RectangleMark(
                x: .value(payload.xAxis.label, cell.column),
                y: .value(payload.yAxis.label, cell.row)
            )
            // Single-hue intensity ramp on the classification tint. `strength`
            // is finite for every input, including a flat domain — see
            // RelationshipHeatmapScale.
            .foregroundStyle(base.opacity(RelationshipHeatmapScale.strength(for: cell.value, in: domain)))
            .accessibilityIdentifier("relationship.cell.\(index)")
            .accessibilityLabel(RelationshipAccessibility.cellLabel(cell))
            .accessibilityValue(RelationshipAccessibility.cellValue(cell))
        }
        // The heatmap's own axes ARE its row/column keys, so the axis-label
        // captions would only repeat what each tick already says. Axis marks
        // stay; the redundant caption is what's dropped.
        .chartLegend(.hidden)
    }

    // MARK: Slope

    private var slopeChart: some View {
        let slopes = Array(payload.slopes.prefix(cap))
        return Chart(Array(slopes.enumerated()), id: \.offset) { index, slope in
            ForEach(Self.periods(for: slope), id: \.period) { reading in
                LineMark(
                    x: .value(payload.xAxis.label, reading.period),
                    y: .value(payload.yAxis.label, reading.value)
                )
                .foregroundStyle(RelationshipCategoryPalette.color(slot: index, theme: theme))
                PointMark(
                    x: .value(payload.xAxis.label, reading.period),
                    y: .value(payload.yAxis.label, reading.value)
                )
                .foregroundStyle(RelationshipCategoryPalette.color(slot: index, theme: theme))
            }
            .accessibilityIdentifier("relationship.slope.\(index)")
            .accessibilityLabel(RelationshipAccessibility.slopeLabel(slope))
            .accessibilityValue(RelationshipAccessibility.slopeValue(slope))
        }
        .chartYAxisLabel(payload.yAxis.label, position: .top, alignment: .leading)
        .chartLegend(.hidden)
    }

    /// A slope's two readings, keyed by their localized period names — the
    /// x-axis of a slope chart is always exactly "before" then "after".
    static func periods(for slope: RelationshipPayload.Slope) -> [SlopeReading] {
        [
            SlopeReading(period: beforeLabel, value: slope.before),
            SlopeReading(period: afterLabel, value: slope.after),
        ]
    }

    struct SlopeReading {
        let period: String
        let value: Double
    }

    private var cap: Int { RelationshipDensity.visibleMarkCap(size) }

    static let beforeLabel = String(
        localized: "relationship.slope.before",
        defaultValue: "Before",
        bundle: .module,
        comment: "X-axis category for the earlier reading of a relationship slope chart."
    )

    static let afterLabel = String(
        localized: "relationship.slope.after",
        defaultValue: "After",
        bundle: .module,
        comment: "X-axis category for the later reading of a relationship slope chart."
    )
}
