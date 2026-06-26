import Foundation
import Testing
import AIDashCore

/// Tests for `aidash card put` (T054 / MY-971).
///
/// Covers the constitution-required gate G.3: every CLI subcommand needs
/// at least one success-path test (envelope/decoding contract) and one
/// validation-failure test, plus the T054-specific @file payload behavior.
@Suite("CardPutCommand")
struct CardPutCommandTests {

    // MARK: - Fixtures

    private static let validContainerID = "11111111-1111-1111-1111-111111111111"
    private static let validCardID      = "22222222-2222-2222-2222-222222222222"
    private static let validMetric      = #"{"items":[{"label":"PRs","value":3}]}"#

    // MARK: - Validation success path

    @Test("validateCardPut accepts well-formed metric card")
    func validMetricAccepted() throws {
        try SchemaValidator.validateCardPut(
            containerId: Self.validContainerID,
            id: Self.validCardID,
            type: "metric",
            size: "small",
            style: "neutral",
            payload: Data(Self.validMetric.utf8)
        )
    }

    // MARK: - Validation failure paths

    @Test("validateCardPut rejects invalid container UUID")
    func rejectsInvalidContainerUUID() {
        do {
            try SchemaValidator.validateCardPut(
                containerId: "not-a-uuid",
                id: Self.validCardID,
                type: "metric",
                size: "small",
                style: "neutral",
                payload: Data(Self.validMetric.utf8)
            )
            Issue.record("Expected XPCError for invalid container UUID")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_uuid")
            #expect(error.field == "containerId")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateCardPut rejects unknown card type")
    func rejectsUnknownType() {
        do {
            try SchemaValidator.validateCardPut(
                containerId: Self.validContainerID,
                id: Self.validCardID,
                type: "bogus",
                size: "small",
                style: "neutral",
                payload: Data(Self.validMetric.utf8)
            )
            Issue.record("Expected XPCError for unknown card type")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_card_type")
            #expect(error.field == "type")
            #expect(error.allowed?.contains("metric") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateCardPut rejects payload exceeding 256 KB")
    func rejectsOversizedPayload() {
        let big = Data(repeating: 0x61, count: 256 * 1024 + 1)
        do {
            try SchemaValidator.validateCardPut(
                containerId: Self.validContainerID,
                id: Self.validCardID,
                type: "metric",
                size: "small",
                style: "neutral",
                payload: big
            )
            Issue.record("Expected XPCError for oversized payload")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_too_large")
            #expect(error.field == "payload")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateCardPut rejects payload that fails typed decode")
    func rejectsMalformedPayload() {
        do {
            try SchemaValidator.validateCardPut(
                containerId: Self.validContainerID,
                id: Self.validCardID,
                type: "metric",
                size: "small",
                style: "neutral",
                payload: Data(#"{"wrong":"shape"}"#.utf8)
            )
            Issue.record("Expected XPCError for malformed metric payload")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - @file payload resolution (research.md §R-2)

    @Test("resolvePayload returns inline JSON bytes verbatim")
    func resolvesInlineJSON() throws {
        let bytes = try PayloadResolver.resolve(Self.validMetric)
        #expect(bytes == Data(Self.validMetric.utf8))
    }

    @Test("resolvePayload reads @file contents from disk")
    func resolvesFilePayload() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-cardput-\(UUID().uuidString).json")
        let body = #"{"items":[{"label":"Issues","value":7,"trend":"up"}]}"#
        try Data(body.utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bytes = try PayloadResolver.resolve("@" + tmp.path)
        #expect(bytes == Data(body.utf8))
    }

    @Test("resolvePayload errors with schema.payload_file_unreadable on missing file")
    func errorsOnMissingFile() {
        let bogus = "@/tmp/aidash-cardput-does-not-exist-\(UUID().uuidString).json"
        do {
            _ = try PayloadResolver.resolve(bogus)
            Issue.record("Expected XPCError for missing payload file")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_file_unreadable")
            #expect(error.field == "payload")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("resolvePayload errors when @ is followed by an empty path")
    func errorsOnEmptyPath() {
        do {
            _ = try PayloadResolver.resolve("@")
            Issue.record("Expected XPCError for empty path after @")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_file_unreadable")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Exit code mapping for the CLI surface

    @Test("schema.* errors map to exit 1")
    func schemaErrorsMapToOne() {
        let error = XPCError(code: "schema.unknown_card_type", message: "x")
        #expect(ExitCodeMapper.code(for: error) == 1)
    }

    @Test("xpc.* errors map to exit 2")
    func xpcErrorsMapToTwo() {
        let error = XPCError(code: "xpc.app_unavailable", message: "x")
        #expect(ExitCodeMapper.code(for: error) == 2)
    }

    @Test("remote errors map to exit 3")
    func remoteErrorsMapToThree() {
        let error = XPCError(code: "container.not_found", message: "x")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }
}
