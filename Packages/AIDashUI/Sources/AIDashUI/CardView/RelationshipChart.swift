import SwiftUI
import Charts
import AIDashCore
import DesignKit

// MARK: - RelationshipPointSymbol
//
// One scatter mark. A point WITH a magnitude is a solid disc whose area
// encodes that magnitude; a point in a mixed payload WITHOUT one is a small
// hollow ring. Two channels carry the distinction (fill and size), so it
// survives grayscale and does not rely on color alone.
//
// Swift Charts does not apply `.symbolSize` to a custom symbol view, so the
// area→diameter conversion happens here: diameter = 2√(area/π).

struct RelationshipPointSymbol: View {
    let area: Double
    let isMissing: Bool
    let color: Color

    var body: some View {
        Group {
            if isMissing {
                Circle().strokeBorder(color, lineWidth: Self.ringWidth)
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// Diameter of a disc with this area — the honest inverse of the
    /// area-proportional scale, so a doubled magnitude looks twice as big
    /// rather than four times.
    var diameter: CGFloat {
        CGFloat(2 * (max(area, 0) / Double.pi).squareRoot())
    }

    /// Ring stroke for the hollow "no magnitude" symbol. Thin relative to the
    /// symbol's own diameter so the centre stays visibly open — at
    /// `missingSize` this leaves a ~6.6pt hole, which reads as empty rather
    /// than as a small solid dot.
    static let ringWidth: CGFloat = 1.2
}

// MARK: - RelationshipChartAxis
//
// north-star §7: "图表克制:无网格、无标签喧宾夺主". Swift Charts' default axis
// content is `AxisGridLine` + `AxisTick` + `AxisValueLabel`, and the grid line
// is the part §7 rules out. This helper emits the other two so every
// relationship plot drops its grid the SAME way — three copies of an inline
// `.chartXAxis { … }` block is exactly how one of them ends up keeping its grid.

enum RelationshipChartAxis {

    /// Axis marks with ticks and value labels but NO grid line.
    static func gridless() -> some AxisContent {
        AxisMarks { _ in
            AxisTick()
            AxisValueLabel()
        }
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
            // The VISIBLE count, not the payload total: announcing marks the
            // plot never drew would describe data that is not on screen.
            .accessibilityLabel(RelationshipAccessibility.chartLabel(payload, visibleCount: visibleMarkCount))
    }

    /// How many marks this chart actually plots after the density cap.
    var visibleMarkCount: Int {
        Swift.min(RelationshipAccessibility.totalMarks(payload), cap)
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
        let magnitudes = points.compactMap(\.magnitude)
        let symbolDomain = RelationshipSymbolScale.domain(magnitudes)
        // Mixed = some points carry a magnitude and some do not. Only then does
        // absence need its own visual treatment; see RelationshipSymbolScale.
        let isMixed = RelationshipSymbolScale.hasMixedMagnitudes(points)
        // The legend keys the COLOR channel, which `category` drives.
        let legend = RelationshipCategoryPalette.legend(for: points)
        return Chart(Array(points.enumerated()), id: \.offset) { index, point in
            let isMissing = RelationshipSymbolScale.isMissing(
                magnitude: point.magnitude, inMixedPayload: isMixed
            )
            let area = RelationshipSymbolScale.size(
                for: point.magnitude, in: symbolDomain, inMixedPayload: isMixed
            )
            let tint = legend.color(for: point, theme: theme)
            PointMark(
                x: .value(payload.xAxis.label, point.x),
                y: .value(payload.yAxis.label, point.y)
            )
            // A magnitude-less point in a mixed payload renders as a small
            // HOLLOW ring: unfilled plus undersized, so "no data" is carried
            // by two channels and survives grayscale. A solid mid-size symbol
            // would read as a genuine mid-low reading.
            //
            // A custom symbol view supplies its own geometry — `.symbolSize`
            // does not scale it — so the view converts the area itself.
            .symbol {
                RelationshipPointSymbol(area: area, isMissing: isMissing, color: tint)
            }
            // Keying the style BY the category is what makes Swift Charts emit
            // a legend at all: a plain `.foregroundStyle(color)` is an opaque
            // value with no scale behind it, which is why the color channel
            // rendered unkeyed. The explicit scale below pins each key to the
            // same slot color the symbol draws, so this keys the existing
            // colors rather than recoloring anything.
            .foregroundStyle(by: .value(Self.categoryFieldLabel, legend.key(for: point)))
            .accessibilityIdentifier("relationship.point.\(index)")
            .accessibilityLabel(RelationshipAccessibility.pointLabel(point))
            .accessibilityValue(
                RelationshipAccessibility.pointValue(
                    point, xAxis: payload.xAxis, yAxis: payload.yAxis, inMixedPayload: isMixed
                )
            )
        }
        .chartForegroundStyleScale(
            domain: legend.domain,
            range: legend.colors(theme: theme)
        )
        .chartXAxisLabel(payload.xAxis.label, position: .bottom)
        .chartYAxisLabel(payload.yAxis.label, position: .top, alignment: .leading)
        // north-star §7 "图表克制:无网格" — Swift Charts draws a grid line per
        // tick by default, and on a handful of points that grid is the loudest
        // thing in the plot. Ticks and their VALUE LABELS stay (a scatter with
        // unreadable axes is not restraint, it is data loss); only the
        // `AxisGridLine` is dropped, on both axes.
        .chartXAxis { RelationshipChartAxis.gridless() }
        .chartYAxis { RelationshipChartAxis.gridless() }
        // Shown only when `category` actually discriminates something. One key
        // means color carries no information, and a one-row legend would be
        // chrome that explains nothing.
        .chartLegend(legend.isKeyed ? .visible : .hidden)
    }

    /// Field name for the scatter's color dimension — the legend's own title.
    static let categoryFieldLabel = String(
        localized: "relationship.scatter.category",
        defaultValue: "Category",
        bundle: .module,
        comment: "Legend title for the color dimension of a relationship scatter chart; each entry is one of the payload's point categories."
    )

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
                    y: .value(payload.yAxis.label, reading.value),
                    // Swift Charts groups marks into series by THIS argument —
                    // not by the enclosing ForEach and not by foregroundStyle.
                    // Without it every entity's points land in one series and
                    // the renderer connects entity A's "after" to entity B's
                    // "before", drawing a zigzag that reads as a real trend but
                    // is pure artifact.
                    series: .value(Self.seriesFieldLabel, Self.seriesKey(index: index, slope: slope))
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

    /// The series identity of one slope entity — what Swift Charts groups its
    /// `LineMark`s by, so each entity gets its own 2-point line.
    ///
    /// The entity's own index is part of the key on purpose. Two entities can
    /// legitimately carry the SAME label (the same repo under two orgs, the
    /// same workspace name in two accounts), and keying on the label alone
    /// would silently merge them back into one line — the same defect this
    /// helper exists to prevent, just harder to spot. The label stays in the
    /// key so a rendered chart is still debuggable by eye.
    static func seriesKey(index: Int, slope: RelationshipPayload.Slope) -> String {
        "\(index)·\(slope.label)"
    }

    /// Field name for the series dimension. Not user-visible — the legend is
    /// hidden and each entity is announced through its own accessibility
    /// element — so it is a stable identifier, not a localized string.
    static let seriesFieldLabel = "Entity"

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
