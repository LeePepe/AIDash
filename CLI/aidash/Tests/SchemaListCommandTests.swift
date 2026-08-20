import Foundation
import Testing
import AIDashCore
import ArgumentParser

/// Tests for `aidash schema list` (T055 / MY-972).
///
/// Covers the constitution-required gate G.3: every CLI subcommand needs
/// at least one success-path test (with JSON envelope assertion) and one
/// validation-failure test.
@Suite("SchemaListCommand")
struct SchemaListCommandTests {

    // MARK: - Fixtures

    private static func sampleResult(payloads: [String: String]? = nil) -> SchemaListResult {
        SchemaListResult(
            cliVersion: "1.0.0",
            schemaVersion: "1.0.0",
            cardTypes: ["metric", "insight", "digest"],
            cardSizes: ["small", "medium", "wide", "hero"],
            cardStyles: ["neutral", "success", "warning", "accent"],
            containerLayouts: ["auto", "list", "grid", "hero"],
            userEventActions: ["done", "star"],
            payloads: payloads ?? [
                "metric": #"{"type":"object","properties":{"items":{"type":"array"}}}"#,
                "insight": #"{"type":"object","properties":{"title":{"type":"string"}}}"#,
                "digest": #"{"type":"object","properties":{"body":{"type":"string"}}}"#,
            ]
        )
    }

    // MARK: - Success path — JSON envelope contract (Constitution §B.1)

    @Test("makeEnvelopeData inlines payload schemas as JSON objects, not escaped strings")
    func successEnvelopeInlinesSchemas() throws {
        let result = Self.sampleResult()
        let envelope = SchemaListRendering.makeEnvelopeData(result)

        let data = try JSONEncoder().encode(envelope)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // Payloads are inlined as nested JSON objects, not as strings.
        let payloads = try #require(obj["payloads"] as? [String: Any])
        let metric = try #require(payloads["metric"] as? [String: Any])
        #expect(metric["type"] as? String == "object")

        // Enum fields are preserved.
        #expect((obj["cardTypes"] as? [String])?.contains("metric") == true)
        #expect(obj["cliVersion"] as? String == "1.0.0")
    }

    @Test("JSONOutput wraps schema-list data in the {ok, data, requestId} envelope")
    func jsonEnvelopeWrapsSuccessData() throws {
        let result = Self.sampleResult()
        let envelope = SchemaListRendering.makeEnvelopeData(result)

        let stdout = try captureStdout {
            try JSONOutput().emit(success: envelope, requestId: "req-1")
        }

        let obj = try #require(
            try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == true)
        #expect(obj["requestId"] as? String == "req-1")
        let body = try #require(obj["data"] as? [String: Any])
        #expect(body["schemaVersion"] as? String == "1.0.0")
        #expect((body["cardTypes"] as? [String])?.contains("insight") == true)
    }

    @Test("Markdown + global --json wraps body in success envelope (Constitution §B.1)")
    func markdownUnderJSONStillWrapsInEnvelope() throws {
        let envelope = MarkdownEnvelopeData(
            markdown: SchemaListRendering.renderMarkdown(Self.sampleResult())
        )

        let stdout = try captureStdout {
            try JSONOutput().emit(success: envelope, requestId: "req-md")
        }

        let obj = try #require(
            try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == true)
        #expect(obj["requestId"] as? String == "req-md")
        let body = try #require(obj["data"] as? [String: Any])
        let markdown = try #require(body["markdown"] as? String)
        #expect(markdown.contains("# AIDash Schema"))
        #expect(markdown.contains("### `metric`"))
    }

    // MARK: - Markdown determinism

    @Test("Markdown payload sections are emitted in sorted key order")
    func markdownPayloadsAreSorted() {
        // Insertion order is intentionally non-alphabetical to prove sorting.
        let result = Self.sampleResult(payloads: [
            "zeta": #"{"type":"object"}"#,
            "alpha": #"{"type":"object"}"#,
            "mu": #"{"type":"object"}"#,
        ])

        let md = SchemaListRendering.renderMarkdown(result)
        let alphaIdx = try? #require(md.range(of: "### `alpha`")?.lowerBound)
        let muIdx    = try? #require(md.range(of: "### `mu`")?.lowerBound)
        let zetaIdx  = try? #require(md.range(of: "### `zeta`")?.lowerBound)
        #expect(alphaIdx != nil && muIdx != nil && zetaIdx != nil)
        if let a = alphaIdx, let m = muIdx, let z = zetaIdx {
            #expect(a < m)
            #expect(m < z)
        }
    }

    // MARK: - --type filter

    @Test("applyTypeFilter trims payloads to the requested CardType only")
    func typeFilterTrimsPayloads() {
        let result = Self.sampleResult()
        let filtered = SchemaListRendering.applyTypeFilter(result, type: "metric")
        #expect(filtered.payloads.keys.sorted() == ["metric"])
        // Enum fields are not narrowed — the contract returns them all.
        #expect(filtered.cardTypes == result.cardTypes)
    }

    @Test("applyTypeFilter is a no-op when type is nil")
    func typeFilterIsNoOpWhenNil() {
        let result = Self.sampleResult()
        let filtered = SchemaListRendering.applyTypeFilter(result, type: nil)
        #expect(filtered.payloads == result.payloads)
    }

    // MARK: - Validation failure (Constitution §G.3 — required negative test)

    @Test("validateSchemaList rejects an unknown CardType with schema.unknown_card_type")
    func validationFailsForUnknownType() {
        do {
            try SchemaValidator.validateSchemaList(type: "unicorn")
            Issue.record("Expected XPCError for unknown CardType")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_card_type")
            #expect(error.field == "type")
            #expect(error.got == "unicorn")
            // Allowed list is the full CardType case set, for agent feedback.
            #expect(error.allowed?.contains("metric") == true)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("validateSchemaList accepts nil and known CardType rawValues")
    func validationAcceptsNilAndKnownTypes() throws {
        try SchemaValidator.validateSchemaList(type: nil)
        for rawValue in CardType.allCases.map(\.rawValue) {
            try SchemaValidator.validateSchemaList(type: rawValue)
        }
    }

    // MARK: - MY-1455: Remote error via production handleFailedResponse (exit 3)

    /// Production-seam test: exercises SchemaListCommand.handleFailedResponse
    /// with a valid remote error. Verifies stderr has requestId, ExitCode(3) thrown.
    @Test("schema list handleFailedResponse emits requestId from response and exits 3 (MY-1455)")
    func remoteErrorEmitsRequestId() throws {
        let response = XPCResponse(
            requestId: "req-schema-remote",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: XPCError(code: "storage.quota_exceeded", message: "quota exceeded")
        )
        let globals = GlobalOptions.test(json: true, quiet: false)

        var capturedExit: Int32?
        let stderr = try captureStderr {
            do {
                try SchemaListCommand.handleFailedResponse(response, globals: globals)
            } catch let exitCode as ExitCode {
                capturedExit = exitCode.rawValue
            }
        }

        #expect(capturedExit == 3)

        let obj = try #require(
            try JSONSerialization.jsonObject(with: Data(stderr.utf8)) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == false)
        #expect(obj["requestId"] == nil)
        let errBody = try #require(obj["error"] as? [String: Any])
        #expect(errBody["code"] as? String == "storage.quota_exceeded")
        #expect(errBody["requestId"] as? String == "req-schema-remote")
    }

    // MARK: - MY-1455: Malformed ok=false (nil error) → xpc.decode_failure (exit 2)

    /// Production-seam test: handleFailedResponse with response.error == nil
    /// throws XPCError with code "xpc.decode_failure", which ExitCodeMapper maps to 2.
    @Test("schema list handleFailedResponse with nil error throws xpc.decode_failure (exit 2)")
    func malformedOkFalseThrowsDecodeFailure() {
        let response = XPCResponse(
            requestId: "req-malformed",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: nil
        )
        let globals = GlobalOptions.test(json: true, quiet: false)

        do {
            try SchemaListCommand.handleFailedResponse(response, globals: globals)
            Issue.record("Expected XPCError to be thrown")
        } catch let error as XPCError {
            #expect(error.code == "xpc.decode_failure")
            #expect(error.message.contains("ok=false"))
            #expect(ExitCodeMapper.code(for: error) == 2)
        } catch {
            Issue.record("Expected XPCError, got: \(error)")
        }
    }
}
