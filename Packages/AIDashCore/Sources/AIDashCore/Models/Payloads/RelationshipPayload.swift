import Foundation

/// Which mark collection a `relationship` card populates. This is a *locked*
/// discriminator, not a free-form chart hint: each case binds to exactly one
/// of `points` / `cells` / `slopes`, and `validateInvariants()` rejects any
/// payload whose populated marks disagree with it.
public enum RelationshipVisualization: String, Codable, Sendable, CaseIterable {
    /// Two continuous axes, one mark per entity (`points`).
    case scatter
    /// A categorical row × column matrix of intensities (`cells`).
    case heatmap
    /// A before/after pair per entity (`slopes`).
    case slope
}

/// A typed two-dimensional relationship (card type `relationship`) — cost ×
/// outcome, rework concentration by workspace × day, before × after unit cost.
///
/// ## Why this is one CardType and not three
///
/// `relationship` is a *semantic* type ("these two dimensions are related"),
/// not a chart-shaped one. The renderer picks marks from `visualization`; the
/// author picks `visualization` from the data's shape. Splitting it into
/// `scatterCard` / `heatmapCard` / `slopeCard` would leak presentation into
/// the schema and force publishers to re-author when the shape changes.
///
/// ## Evidence is mandatory, causation is not claimed
///
/// Every relationship card carries `sampleSize`, `timeWindow`, and
/// `metricDefinition` so a reader can judge whether the association means
/// anything. These are required, not optional: an association without its
/// sample size and window is a claim without evidence. `summary` states what
/// was *observed* — per the constitution, an observational association must
/// never be worded as causation.
public struct RelationshipPayload: CardPayloadProtocol {

    /// One chart axis. `unit` is display-only — the app never converts units.
    public struct Axis: Codable, Sendable {
        public let label: String
        public let unit: String?

        public init(label: String, unit: String? = nil) {
            self.label = label
            self.unit = unit
        }
    }

    /// A `scatter` mark: one entity at (`x`, `y`).
    public struct Point: Codable, Sendable {
        public let label: String
        public let x: Double
        public let y: Double
        /// Optional third dimension driving symbol size (e.g. sample count).
        /// Absent → uniform symbols. Must be strictly positive when present:
        /// symbol area is proportional to it, so `0` renders an invisible mark.
        public let magnitude: Double?
        /// Optional grouping key driving the categorical color slot. Absent →
        /// a single-series scatter.
        public let category: String?

        public init(
            label: String,
            x: Double,
            y: Double,
            magnitude: Double? = nil,
            category: String? = nil
        ) {
            self.label = label
            self.x = x
            self.y = y
            self.magnitude = magnitude
            self.category = category
        }
    }

    /// A `heatmap` mark: one cell of the row × column matrix.
    public struct Cell: Codable, Sendable {
        public let column: String
        public let row: String
        public let value: Double

        public init(column: String, row: String, value: Double) {
            self.column = column
            self.row = row
            self.value = value
        }
    }

    /// A `slope` mark: one entity's before/after pair.
    public struct Slope: Codable, Sendable {
        public let label: String
        public let before: Double
        public let after: Double

        public init(label: String, before: Double, after: Double) {
            self.label = label
            self.before = before
            self.after = after
        }
    }

    public let title: String
    public let visualization: RelationshipVisualization
    public let xAxis: Axis
    public let yAxis: Axis
    public let points: [Point]
    public let cells: [Cell]
    public let slopes: [Slope]
    /// Number of underlying observations. Positive — a relationship drawn from
    /// nothing is not a relationship.
    public let sampleSize: Int
    /// Human-readable observation window (e.g. `7d`, `previous 7d vs current 7d`).
    public let timeWindow: String
    /// What the plotted metric actually measures, including its proxies and
    /// their limits. Required so a proxy is never read as ground truth.
    public let metricDefinition: String
    /// The observed conclusion, worded as observation rather than cause.
    public let summary: String

    public init(
        title: String,
        visualization: RelationshipVisualization,
        xAxis: Axis,
        yAxis: Axis,
        points: [Point] = [],
        cells: [Cell] = [],
        slopes: [Slope] = [],
        sampleSize: Int,
        timeWindow: String,
        metricDefinition: String,
        summary: String
    ) {
        self.title = title
        self.visualization = visualization
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.points = points
        self.cells = cells
        self.slopes = slopes
        self.sampleSize = sampleSize
        self.timeWindow = timeWindow
        self.metricDefinition = metricDefinition
        self.summary = summary
    }

    // MARK: - Decoding
    //
    // The three mark arrays default to empty when the key is absent: an author
    // publishing a scatter writes only `points`, exactly as the contract
    // examples in `cardtype-payloads.md` do. Synthesized decoding would reject
    // those documents for the two arrays they legitimately omit.

    private enum CodingKeys: String, CodingKey {
        case title, visualization, xAxis, yAxis, points, cells, slopes
        case sampleSize, timeWindow, metricDefinition, summary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        visualization = try container.decode(RelationshipVisualization.self, forKey: .visualization)
        xAxis = try container.decode(Axis.self, forKey: .xAxis)
        yAxis = try container.decode(Axis.self, forKey: .yAxis)
        points = try container.decodeIfPresent([Point].self, forKey: .points) ?? []
        cells = try container.decodeIfPresent([Cell].self, forKey: .cells) ?? []
        slopes = try container.decodeIfPresent([Slope].self, forKey: .slopes) ?? []
        sampleSize = try container.decode(Int.self, forKey: .sampleSize)
        timeWindow = try container.decode(String.self, forKey: .timeWindow)
        metricDefinition = try container.decode(String.self, forKey: .metricDefinition)
        summary = try container.decode(String.self, forKey: .summary)
    }

    // MARK: - Invariants

    public func validateInvariants() throws {
        try Self.requireText(title, field: "title")
        try Self.requireText(xAxis.label, field: "xAxis.label")
        try Self.requireText(yAxis.label, field: "yAxis.label")
        try Self.requireText(timeWindow, field: "timeWindow")
        try Self.requireText(metricDefinition, field: "metricDefinition")
        try Self.requireText(summary, field: "summary")
        guard sampleSize >= 1 else {
            throw Self.invalid("sampleSize must be at least 1", field: "sampleSize")
        }
        try validateMarkSet()
        try validatePointValues()
        try validateCellValues()
        try validateSlopeValues()
    }

    /// `visualization` and the populated mark collection must agree exactly:
    /// the required collection is non-empty and the other two are empty. A
    /// mismatch means the renderer would draw an empty chart while the data
    /// sits in an array it never reads.
    private func validateMarkSet() throws {
        let required = Self.markField(for: visualization)
        let counts = [("points", points.count), ("cells", cells.count), ("slopes", slopes.count)]

        for (field, count) in counts {
            if field == required {
                guard count > 0 else {
                    throw Self.invalid(
                        "\(visualization.rawValue) requires at least one entry in '\(field)'",
                        field: field
                    )
                }
            } else if count > 0 {
                throw Self.invalid(
                    "\(visualization.rawValue) must not carry '\(field)'; use '\(required)'",
                    field: field
                )
            }
        }
    }

    /// The mark collection a visualization owns.
    private static func markField(for visualization: RelationshipVisualization) -> String {
        switch visualization {
        case .scatter: return "points"
        case .heatmap: return "cells"
        case .slope:   return "slopes"
        }
    }

    private func validatePointValues() throws {
        for point in points {
            try Self.requireText(point.label, field: "points.label")
            try Self.requireFinite(point.x, field: "points.x")
            try Self.requireFinite(point.y, field: "points.y")
            guard let magnitude = point.magnitude else { continue }
            try Self.requireFinite(magnitude, field: "points.magnitude")
            guard magnitude > 0 else {
                throw Self.invalid(
                    "points.magnitude must be greater than 0 (symbol area is proportional to it)",
                    field: "points.magnitude"
                )
            }
        }
    }

    private func validateCellValues() throws {
        for cell in cells {
            try Self.requireText(cell.column, field: "cells.column")
            try Self.requireText(cell.row, field: "cells.row")
            try Self.requireFinite(cell.value, field: "cells.value")
        }
    }

    private func validateSlopeValues() throws {
        for slope in slopes {
            try Self.requireText(slope.label, field: "slopes.label")
            try Self.requireFinite(slope.before, field: "slopes.before")
            try Self.requireFinite(slope.after, field: "slopes.after")
        }
    }

    // MARK: - Invariant helpers

    /// Rejects strings that are empty once trimmed — a label of `"  "` renders
    /// as a blank axis or legend row, which reads as a rendering bug.
    private static func requireText(_ value: String, field: String) throws {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw invalid("RelationshipPayload requires non-empty \(field)", field: field)
        }
    }

    /// Rejects NaN and ±infinity. Non-finite coordinates propagate through
    /// axis-domain math and blank the whole chart, not just one mark.
    private static func requireFinite(_ value: Double, field: String) throws {
        guard value.isFinite else {
            throw invalid("\(field) must be a finite number", field: field)
        }
    }

    private static func invalid(_ message: String, field: String) -> XPCError {
        XPCError(code: "schema.payload_decode_failed", message: message, field: field)
    }
}
