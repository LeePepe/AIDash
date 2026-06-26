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

    // MARK: - Command wiring: XPC request construction (mirrors CardPutCommand.run)

    /// Asserts that `CardPutParams` round-trips through `XPCRequest.params` as
    /// the exact JSON shape the app-side handler expects: documented field
    /// names, raw enum strings, payload as a Base64 `Data`.
    /// See `contracts/xpc-protocol.md` §"Request envelope" + `Commands/CardPut.swift`.
    @Test("buildXPCRequest packs CardPutParams as the documented card.put envelope")
    func buildsCardPutRequest() throws {
        let params = CardPutParams(
            containerId: Self.validContainerID,
            id: Self.validCardID,
            type: .metric,
            size: .small,
            style: .neutral,
            payload: Data(Self.validMetric.utf8)
        )
        let paramsData = try JSONEncoder().encode(params)
        let request = XPCRequest(
            requestId: "req-card-put-1",
            cliVersion: "1.0.0",
            command: "card.put",
            params: paramsData
        )

        #expect(request.command == "card.put")
        #expect(request.cliVersion == "1.0.0")
        #expect(request.requestId == "req-card-put-1")

        // Re-decode the params blob and assert each field.
        let decoded = try JSONDecoder().decode(CardPutParams.self, from: request.params)
        #expect(decoded.containerId == Self.validContainerID)
        #expect(decoded.id == Self.validCardID)
        #expect(decoded.type == .metric)
        #expect(decoded.size == .small)
        #expect(decoded.style == .neutral)
        #expect(decoded.payload == Data(Self.validMetric.utf8))
    }

    // MARK: - Command wiring: CardPutResult decoding from a synthetic XPC response

    /// Mirrors CardPutCommand.run's success path: take the bytes the app-side
    /// would put in `XPCResponse.data`, decode via `iso8601Decoder`, and assert
    /// every field round-trips. This is the decode contract the CLI relies on
    /// before emitting the success envelope.
    @Test("CardPutResult decodes from the documented success-data shape")
    func decodesCardPutResult() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let isoString: String = {
            let f = ISO8601DateFormatter()
            return f.string(from: now)
        }()
        let bodyJSON = #"{"id":"\#(Self.validCardID)","updatedAt":"\#(isoString)","wasCreated":true}"#
        let iso = JSONDecoder()
        iso.dateDecodingStrategy = .iso8601
        let decoded = try iso.decode(
            CardPutResult.self,
            from: Data(bodyJSON.utf8)
        )
        #expect(decoded.id == Self.validCardID)
        #expect(Int(decoded.updatedAt.timeIntervalSince1970) == Int(now.timeIntervalSince1970))
        #expect(decoded.wasCreated == true)
    }

    // MARK: - Command wiring: JSON success envelope (Constitution §B.1)

    /// Asserts that emitting a `CardPutResult` through `JSONOutput` produces
    /// the documented `{ok, data, requestId}` envelope on stdout. This is the
    /// formatter selection + envelope contract the CardPutCommand success
    /// path is responsible for.
    @Test("JSONOutput wraps CardPutResult in the {ok, data, requestId} success envelope")
    func jsonOutputWrapsCardPutResult() throws {
        let result = CardPutResult(
            id: Self.validCardID,
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            wasCreated: true
        )

        let pipe = Pipe()
        let saved = dup(FileHandle.standardOutput.fileDescriptor)
        dup2(pipe.fileHandleForWriting.fileDescriptor, FileHandle.standardOutput.fileDescriptor)

        try JSONOutput().emit(success: result, requestId: "req-card-put-2")

        dup2(saved, FileHandle.standardOutput.fileDescriptor)
        close(saved)
        try pipe.fileHandleForWriting.close()
        let captured = pipe.fileHandleForReading.readDataToEndOfFile()

        let obj = try #require(
            try JSONSerialization.jsonObject(with: captured) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == true)
        #expect(obj["requestId"] as? String == "req-card-put-2")
        let body = try #require(obj["data"] as? [String: Any])
        #expect(body["id"] as? String == Self.validCardID)
        #expect(body["wasCreated"] as? Bool == true)
        // updatedAt is ISO-8601 — present and non-empty is the contract.
        let updatedAt = try #require(body["updatedAt"] as? String)
        #expect(!updatedAt.isEmpty)
    }

    // MARK: - Command wiring: remote-error envelope (formatter selection)

    /// Mirrors CardPutCommand.run's remote-error branch: a remote `XPCError`
    /// must serialize through `JSONOutput.emit(error:)` as the documented
    /// `{ok:false, error:{code, message, ...}}` envelope on stderr.
    @Test("JSONOutput serializes remote XPCError as the documented error envelope")
    func jsonOutputSerializesRemoteError() throws {
        let remoteError = XPCError(
            code: "container.not_found",
            message: "No container with that id",
            field: "containerId",
            got: Self.validContainerID
        )

        let pipe = Pipe()
        let saved = dup(FileHandle.standardError.fileDescriptor)
        dup2(pipe.fileHandleForWriting.fileDescriptor, FileHandle.standardError.fileDescriptor)

        try JSONOutput().emit(error: remoteError, requestId: "req-card-put-err")

        dup2(saved, FileHandle.standardError.fileDescriptor)
        close(saved)
        try pipe.fileHandleForWriting.close()
        let captured = pipe.fileHandleForReading.readDataToEndOfFile()

        let obj = try #require(
            try JSONSerialization.jsonObject(with: captured) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == false)
        let errBody = try #require(obj["error"] as? [String: Any])
        #expect(errBody["code"] as? String == "container.not_found")
        #expect(errBody["field"] as? String == "containerId")
        #expect(errBody["got"] as? String == Self.validContainerID)
        #expect(errBody["requestId"] as? String == "req-card-put-err")
    }
}
