import Foundation
import Testing
@testable import AIDashCore

// Invariant rejection matrix for `relationship`. Every case asserts the
// XPCError code AND the exact offending field, because the field is what the
// CLI shows the publishing agent — a wrong field sends an author hunting in
// the wrong part of their payload.
//
// Two entry points are exercised deliberately:
//   * `validateInvariants()` for values that JSON cannot express (non-finite
//     doubles — JSONEncoder rejects them before an invariant could run).
//   * `SchemaValidator.validateCardPut` for everything expressible as JSON,
//     which is the path a published card actually takes.
@Suite("RelationshipPayload Invariant Tests")
struct RelationshipPayloadInvariantTests {

    // MARK: - Builders

    private func payload(
        title: String = "Cost × outcome",
        visualization: RelationshipVisualization = .scatter,
        xAxis: RelationshipPayload.Axis = .init(label: "Cost", unit: "USD"),
        yAxis: RelationshipPayload.Axis = .init(label: "Completion", unit: "%"),
        points: [RelationshipPayload.Point] = [.init(label: "AIDash", x: 2.1, y: 88)],
        cells: [RelationshipPayload.Cell] = [],
        slopes: [RelationshipPayload.Slope] = [],
        sampleSize: Int = 34,
        timeWindow: String = "7d",
        metricDefinition: String = "pipeline completion proxy",
        summary: String = "Observed frontier candidate."
    ) -> RelationshipPayload {
        RelationshipPayload(
            title: title,
            visualization: visualization,
            xAxis: xAxis,
            yAxis: yAxis,
            points: points,
            cells: cells,
            slopes: slopes,
            sampleSize: sampleSize,
            timeWindow: timeWindow,
            metricDefinition: metricDefinition,
            summary: summary
        )
    }

    private let heatmapCells = [RelationshipPayload.Cell(column: "2026-08-11", row: "AIDash", value: 48_000)]
    private let slopeItems = [RelationshipPayload.Slope(label: "AIDash", before: 21_000, after: 18_000)]

    /// Asserts `validateInvariants()` throws `schema.payload_decode_failed`
    /// naming `field`.
    private func expectInvalid(
        _ value: RelationshipPayload,
        field: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            try value.validateInvariants()
            Issue.record("Should have thrown for field '\(field)'", sourceLocation: sourceLocation)
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed", sourceLocation: sourceLocation)
            #expect(error.field == field, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error type: \(error)", sourceLocation: sourceLocation)
        }
    }

    /// Asserts the same payload rejected through the real publish path
    /// (`SchemaValidator.validateCardPut`), so the error code/field survive
    /// JSON encode + decode + validate rather than only the in-memory call.
    private func expectRejectedByValidator(
        _ value: RelationshipPayload,
        field: String,
        size: String = "wide",
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let data = try JSONEncoder().encode(value)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "relationship",
                size: size,
                style: "neutral",
                payload: data
            )
            Issue.record("Should have thrown for field '\(field)'", sourceLocation: sourceLocation)
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed", sourceLocation: sourceLocation)
            #expect(error.field == field, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error type: \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - visualization ⇄ mark-set exclusivity

    @Test func scatterRequiresPointsAndRejectsOtherMarks() throws {
        expectInvalid(payload(points: []), field: "points")
        expectInvalid(payload(cells: heatmapCells), field: "cells")
        expectInvalid(payload(slopes: slopeItems), field: "slopes")
        try expectRejectedByValidator(payload(points: []), field: "points")
        try expectRejectedByValidator(payload(cells: heatmapCells), field: "cells")
    }

    @Test func heatmapRequiresCellsAndRejectsOtherMarks() throws {
        expectInvalid(
            payload(visualization: .heatmap, points: [], cells: []),
            field: "cells"
        )
        expectInvalid(
            payload(visualization: .heatmap, cells: heatmapCells),
            field: "points"
        )
        expectInvalid(
            payload(visualization: .heatmap, points: [], cells: heatmapCells, slopes: slopeItems),
            field: "slopes"
        )
        try expectRejectedByValidator(
            payload(visualization: .heatmap, points: [], cells: []),
            field: "cells"
        )
    }

    @Test func slopeRequiresSlopesAndRejectsOtherMarks() throws {
        expectInvalid(
            payload(visualization: .slope, points: [], slopes: []),
            field: "slopes"
        )
        expectInvalid(
            payload(visualization: .slope, slopes: slopeItems),
            field: "points"
        )
        expectInvalid(
            payload(visualization: .slope, points: [], cells: heatmapCells, slopes: slopeItems),
            field: "cells"
        )
        try expectRejectedByValidator(
            payload(visualization: .slope, points: [], slopes: []),
            field: "slopes"
        )
    }

    // MARK: - evidence context

    @Test func sampleSizeMustBePositive() throws {
        expectInvalid(payload(sampleSize: 0), field: "sampleSize")
        expectInvalid(payload(sampleSize: -3), field: "sampleSize")
        try expectRejectedByValidator(payload(sampleSize: 0), field: "sampleSize")
    }

    @Test func evidenceStringsRejectTrimmedEmpty() throws {
        expectInvalid(payload(title: "   "), field: "title")
        expectInvalid(payload(timeWindow: " \n "), field: "timeWindow")
        expectInvalid(payload(metricDefinition: "\t"), field: "metricDefinition")
        expectInvalid(payload(summary: ""), field: "summary")
        try expectRejectedByValidator(payload(timeWindow: "  "), field: "timeWindow")
        try expectRejectedByValidator(payload(metricDefinition: ""), field: "metricDefinition")
    }

    @Test func axisLabelsRejectTrimmedEmpty() throws {
        expectInvalid(payload(xAxis: .init(label: " ", unit: "USD")), field: "xAxis.label")
        expectInvalid(payload(yAxis: .init(label: "", unit: "%")), field: "yAxis.label")
        try expectRejectedByValidator(payload(xAxis: .init(label: "  ")), field: "xAxis.label")
    }

    // MARK: - mark-level fields

    @Test func markLabelsRejectTrimmedEmpty() throws {
        expectInvalid(payload(points: [.init(label: " ", x: 1, y: 2)]), field: "points.label")
        expectInvalid(
            payload(visualization: .heatmap, points: [], cells: [.init(column: "", row: "AIDash", value: 1)]),
            field: "cells.column"
        )
        expectInvalid(
            payload(visualization: .heatmap, points: [], cells: [.init(column: "d", row: " ", value: 1)]),
            field: "cells.row"
        )
        expectInvalid(
            payload(visualization: .slope, points: [], slopes: [.init(label: "", before: 1, after: 2)]),
            field: "slopes.label"
        )
        try expectRejectedByValidator(
            payload(points: [.init(label: "", x: 1, y: 2)]),
            field: "points.label"
        )
    }

    @Test func numericMarkValuesRejectNonFinite() {
        for bad in [Double.nan, .infinity, -.infinity] {
            expectInvalid(payload(points: [.init(label: "a", x: bad, y: 2)]), field: "points.x")
            expectInvalid(payload(points: [.init(label: "a", x: 1, y: bad)]), field: "points.y")
            expectInvalid(
                payload(points: [.init(label: "a", x: 1, y: 2, magnitude: bad)]),
                field: "points.magnitude"
            )
            expectInvalid(
                payload(visualization: .heatmap, points: [], cells: [.init(column: "d", row: "r", value: bad)]),
                field: "cells.value"
            )
            expectInvalid(
                payload(visualization: .slope, points: [], slopes: [.init(label: "a", before: bad, after: 2)]),
                field: "slopes.before"
            )
            expectInvalid(
                payload(visualization: .slope, points: [], slopes: [.init(label: "a", before: 1, after: bad)]),
                field: "slopes.after"
            )
        }
    }

    @Test func magnitudeMustBeStrictlyPositive() throws {
        // Symbol area is proportional to magnitude; 0 or negative renders an
        // invisible or undefined mark rather than a small one.
        expectInvalid(payload(points: [.init(label: "a", x: 1, y: 2, magnitude: 0)]), field: "points.magnitude")
        expectInvalid(payload(points: [.init(label: "a", x: 1, y: 2, magnitude: -4)]), field: "points.magnitude")
        try expectRejectedByValidator(
            payload(points: [.init(label: "a", x: 1, y: 2, magnitude: -1)]),
            field: "points.magnitude"
        )
    }

    @Test func absentMagnitudeAndCategoryAreValid() throws {
        // Both are optional: a scatter without bubble sizing or categories is
        // a legitimate shape, not a degraded one.
        try payload(points: [.init(label: "a", x: 1, y: 2)]).validateInvariants()
    }

    // MARK: - valid shapes pass

    @Test func validShapesPassValidation() throws {
        try payload().validateInvariants()
        try payload(visualization: .heatmap, points: [], cells: heatmapCells).validateInvariants()
        try payload(visualization: .slope, points: [], slopes: slopeItems).validateInvariants()
    }

    @Test func validShapesPassTheFullPublishPath() throws {
        let encoder = JSONEncoder()
        for value in [
            payload(),
            payload(visualization: .heatmap, points: [], cells: heatmapCells),
            payload(visualization: .slope, points: [], slopes: slopeItems)
        ] {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "relationship",
                size: "wide",
                style: "neutral",
                payload: try encoder.encode(value)
            )
        }
    }
}
