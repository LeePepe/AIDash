import Testing
import Foundation
@testable import AIDashCore

/// Focused coverage for the `MetricPayload.Item.ratio` invariant (0...1),
/// kept in its own file so `SchemaValidatorTests` stays within the
/// file-length budget.
@Suite("MetricPayload ratio validation")
struct MetricRatioValidationTests {

    private func validate(_ json: String) throws {
        try SchemaValidator.validateCardPut(
            containerId: "550E8400-E29B-41D4-A716-446655440000",
            id: "660E8400-E29B-41D4-A716-446655440000",
            type: "metric",
            size: "small",
            style: "neutral",
            payload: Data(json.utf8)
        )
    }

    @Test func ratioOutOfRange_throws() {
        do {
            try validate(#"{"items":[{"label":"Done","value":50,"ratio":1.5}]}"#)
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "ratio")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func ratioNegative_throws() {
        do {
            try validate(#"{"items":[{"label":"Done","value":50,"ratio":-0.1}]}"#)
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.field == "ratio")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func ratioInRange_doesNotThrow() throws {
        try validate(#"{"items":[{"label":"Done","value":50,"ratio":0.5}]}"#)
        try validate(#"{"items":[{"label":"Done","value":50,"ratio":0}]}"#)
        try validate(#"{"items":[{"label":"Done","value":50,"ratio":1}]}"#)
    }
}
