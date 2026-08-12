import SwiftUI
import Charts
import AIDashCore
import DesignKit

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

    /// Chart summary label. `visibleCount` is how many marks are ACTUALLY
    /// plotted after the density cap — not the payload's total. Announcing the
    /// total while drawing fewer would describe data that is not on screen.
    /// When the two differ, the label says so explicitly.
    static func chartLabel(_ payload: RelationshipPayload, visibleCount: Int) -> String {
        let total = totalMarks(payload)
        let visible = Swift.min(Swift.max(visibleCount, 0), total)
        let base: String
        switch payload.visualization {
        case .scatter: base = scatterChartLabel(payload.title, count: visible)
        case .heatmap: base = heatmapChartLabel(payload.title, count: visible)
        case .slope:   base = slopeChartLabel(payload.title, count: visible)
        }
        guard isTruncated(visible: visible, total: total) else { return base }
        return "\(base) \(truncationNotice(visible: visible, total: total))"
    }

    /// Marks in the collection this payload's `visualization` owns.
    static func totalMarks(_ payload: RelationshipPayload) -> Int {
        switch payload.visualization {
        case .scatter: return payload.points.count
        case .heatmap: return payload.cells.count
        case .slope:   return payload.slopes.count
        }
    }

    /// True when the density cap dropped marks the payload actually carries.
    static func isTruncated(visible: Int, total: Int) -> Bool {
        visible < total
    }

    /// The disclosure both channels share: a sighted user reads it under the
    /// chart, a VoiceOver user hears it appended to the chart label. Carries
    /// BOTH numbers so "how much am I not seeing" is answerable.
    static func truncationNotice(visible: Int, total: Int) -> String {
        String(
            localized: "relationship.a11y.truncated",
            defaultValue: "Showing \(visible) of \(total).",
            bundle: .module,
            comment: "Disclosure shown when a relationship chart plots fewer marks than the payload carries. First placeholder is the number drawn, second is the true total."
        )
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
        yAxis: RelationshipPayload.Axis,
        inMixedPayload: Bool = false
    ) -> String {
        let x = axisReading(axis: xAxis, value: point.x)
        let y = axisReading(axis: yAxis, value: point.y)
        let reading = String(
            localized: "relationship.a11y.point.value",
            defaultValue: "\(x), \(y)",
            bundle: .module,
            comment: "VoiceOver value for one scatter point: the x-axis reading followed by the y-axis reading."
        )
        // In a MIXED payload the symbol's small hollow rendering says "no
        // magnitude" visually; VoiceOver needs that stated in words, or the
        // dimension just silently vanishes for a screen-reader user.
        guard RelationshipSymbolScale.isMissing(
            magnitude: point.magnitude, inMixedPayload: inMixedPayload
        ) else { return reading }
        return "\(reading), \(missingMagnitudeLabel)"
    }

    /// Spoken marker for a point that carries no magnitude while its siblings
    /// do. Reads as absence, never as a zero value.
    static let missingMagnitudeLabel = String(
        localized: "relationship.a11y.point.magnitude_missing",
        defaultValue: "no magnitude available",
        bundle: .module,
        comment: "Appended to a scatter point's VoiceOver value when that point has no magnitude but other points in the same chart do."
    )

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
