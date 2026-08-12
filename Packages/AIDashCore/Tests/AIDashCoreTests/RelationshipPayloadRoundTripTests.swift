import Foundation
import Testing
@testable import AIDashCore

// Round-trip + decode-dispatch coverage for the `relationship` CardType.
// Invariant rejection lives in RelationshipPayloadInvariantTests.
@Suite("RelationshipPayload Round-Trip Tests")
struct RelationshipPayloadRoundTripTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func roundTrip(_ value: RelationshipPayload) throws -> RelationshipPayload {
        try decoder.decode(RelationshipPayload.self, from: encoder.encode(value))
    }

    // MARK: - scatter

    @Test func scatterRoundTrip() throws {
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
        let decoded = try roundTrip(payload)
        #expect(decoded.title == "Cost × outcome")
        #expect(decoded.visualization == .scatter)
        #expect(decoded.xAxis.label == "Cost")
        #expect(decoded.xAxis.unit == "USD")
        #expect(decoded.yAxis.unit == "%")
        #expect(decoded.points.count == 1)
        #expect(decoded.points[0].x == 2.1)
        #expect(decoded.points[0].y == 88)
        #expect(decoded.points[0].magnitude == 34)
        #expect(decoded.points[0].category == "project")
        #expect(decoded.cells.isEmpty)
        #expect(decoded.slopes.isEmpty)
        #expect(decoded.sampleSize == 34)
        #expect(decoded.timeWindow == "7d")
        #expect(decoded.metricDefinition == "pipeline completion proxy")
        #expect(decoded.summary == "Observed frontier candidate.")

        let dispatched = try CardType.relationship.decode(encoder.encode(payload))
        #expect(dispatched is RelationshipPayload)
    }

    // MARK: - heatmap

    @Test func heatmapRoundTrip() throws {
        let payload = RelationshipPayload(
            title: "Rework concentration",
            visualization: .heatmap,
            xAxis: .init(label: "Day"),
            yAxis: .init(label: "Workspace"),
            cells: [.init(column: "2026-08-11", row: "AIDash", value: 48_000)],
            sampleSize: 4,
            timeWindow: "7d",
            metricDefinition: "tokens on issues completed after cancellation",
            summary: "Observed rework is concentrated on one day; no causal claim."
        )
        let decoded = try roundTrip(payload)
        #expect(decoded.visualization == .heatmap)
        #expect(decoded.xAxis.unit == nil)
        #expect(decoded.cells.count == 1)
        #expect(decoded.cells[0].column == "2026-08-11")
        #expect(decoded.cells[0].row == "AIDash")
        #expect(decoded.cells[0].value == 48_000)
        #expect(decoded.points.isEmpty)
        #expect(decoded.slopes.isEmpty)

        let dispatched = try CardType.relationship.decode(encoder.encode(payload))
        #expect(dispatched is RelationshipPayload)
    }

    // MARK: - slope

    @Test func slopeRoundTrip() throws {
        let payload = RelationshipPayload(
            title: "Before × after",
            visualization: .slope,
            xAxis: .init(label: "Period"),
            yAxis: .init(label: "Tokens per completed task"),
            slopes: [.init(label: "AIDash", before: 21_000, after: 18_000)],
            sampleSize: 12,
            timeWindow: "previous 7d vs current 7d",
            metricDefinition: "total tokens divided by completed pipeline tasks",
            summary: "Observed unit token use decreased."
        )
        let decoded = try roundTrip(payload)
        #expect(decoded.visualization == .slope)
        #expect(decoded.slopes.count == 1)
        #expect(decoded.slopes[0].label == "AIDash")
        #expect(decoded.slopes[0].before == 21_000)
        #expect(decoded.slopes[0].after == 18_000)
        #expect(decoded.points.isEmpty)
        #expect(decoded.cells.isEmpty)

        let dispatched = try CardType.relationship.decode(encoder.encode(payload))
        #expect(dispatched is RelationshipPayload)
    }

    // MARK: - Locked contract JSON (cardtype-payloads.md)
    //
    // Authors omit the mark arrays they don't populate — the exact shapes in
    // the contract doc. Decode must tolerate the absent arrays (→ empty), or
    // every published relationship card fails schema validation.

    @Test func decodesContractScatterJSONWithOmittedArrays() throws {
        let json = Data("""
        {"title":"Cost × outcome","visualization":"scatter",\
        "xAxis":{"label":"Cost per completed task","unit":"USD"},\
        "yAxis":{"label":"First-pass completion proxy","unit":"%"},\
        "points":[{"label":"AIDash","x":2.1,"y":88,"magnitude":34,"category":"project"}],\
        "sampleSize":34,"timeWindow":"7d",\
        "metricDefinition":"completed is a pipeline proxy, not objective correctness",\
        "summary":"AIDash has the lowest observed cost at the highest completion proxy."}
        """.utf8)
        let decoded = try #require(try CardType.relationship.decode(json) as? RelationshipPayload)
        #expect(decoded.points.count == 1)
        #expect(decoded.cells.isEmpty)
        #expect(decoded.slopes.isEmpty)
        try CardType.relationship.validate(json)
    }

    @Test func decodesContractHeatmapJSONWithOmittedArrays() throws {
        let json = Data("""
        {"title":"Rework concentration","visualization":"heatmap",\
        "xAxis":{"label":"Day"},"yAxis":{"label":"Workspace"},\
        "cells":[{"column":"2026-08-11","row":"AIDash","value":48000}],\
        "sampleSize":4,"timeWindow":"7d",\
        "metricDefinition":"tokens on issues completed after cancellation",\
        "summary":"Observed rework is concentrated on one day; no causal claim."}
        """.utf8)
        let decoded = try #require(try CardType.relationship.decode(json) as? RelationshipPayload)
        #expect(decoded.cells.count == 1)
        #expect(decoded.points.isEmpty)
        try CardType.relationship.validate(json)
    }

    @Test func decodesContractSlopeJSONWithOmittedArrays() throws {
        let json = Data("""
        {"title":"Before × after","visualization":"slope",\
        "xAxis":{"label":"Period"},"yAxis":{"label":"Tokens per completed task"},\
        "slopes":[{"label":"AIDash","before":21000,"after":18000}],\
        "sampleSize":12,"timeWindow":"previous 7d vs current 7d",\
        "metricDefinition":"total tokens divided by completed pipeline tasks",\
        "summary":"Observed unit token use decreased."}
        """.utf8)
        let decoded = try #require(try CardType.relationship.decode(json) as? RelationshipPayload)
        #expect(decoded.slopes.count == 1)
        #expect(decoded.cells.isEmpty)
        try CardType.relationship.validate(json)
    }

    // MARK: - visualization enum

    @Test func visualizationRoundTripsAsRawString() throws {
        for visualization in [RelationshipVisualization.scatter, .heatmap, .slope] {
            let data = try encoder.encode(visualization)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(visualization.rawValue)\"")
            #expect(try decoder.decode(RelationshipVisualization.self, from: data) == visualization)
        }
    }

    @Test func unknownVisualizationIsRejected() {
        let json = Data("""
        {"title":"t","visualization":"bubble","xAxis":{"label":"x"},"yAxis":{"label":"y"},\
        "points":[{"label":"a","x":1,"y":2}],"sampleSize":1,"timeWindow":"7d",\
        "metricDefinition":"d","summary":"s"}
        """.utf8)
        #expect(throws: (any Error).self) {
            try CardType.relationship.decode(json)
        }
    }

    // MARK: - CardType surface

    @Test func relationshipIsAdvertisedInAllCases() {
        #expect(CardType.allCases.contains(.relationship))
        #expect(CardType(rawValue: "relationship") == .relationship)
        #expect(CardType.relationship.rawValue == "relationship")
    }
}
