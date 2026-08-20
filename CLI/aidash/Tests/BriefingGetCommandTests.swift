import Foundation
import Testing
import AIDashCore
import ArgumentParser

/// Tests for `aidash briefing get` (T052 / MY-969).
///
/// Covers Constitution §G.3 gate: every CLI subcommand needs at least one
/// success-path test (envelope contract) and one validation-failure-path
/// test, plus the T052-specific date sugar / `includeDrafts` behavior.
@Suite("BriefingGetCommand")
struct BriefingGetCommandTests {

    // MARK: - Date sugar resolution (BriefingGetCommand.resolveDate)

    @Test("resolveDate('today') -> today's YYYY-MM-DD")
    func resolvesToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expected = formatter.string(from: Date())

        #expect(BriefingGetCommand.resolveDate("today") == expected)
        #expect(BriefingGetCommand.resolveDate("Today") == expected)
        #expect(BriefingGetCommand.resolveDate("TODAY") == expected)
    }

    @Test("resolveDate('yesterday') -> yesterday's YYYY-MM-DD")
    func resolvesYesterday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let expected = formatter.string(from: yesterday)

        #expect(BriefingGetCommand.resolveDate("yesterday") == expected)
    }

    @Test("resolveDate('latest') passes through unchanged")
    func resolvesLatest() {
        #expect(BriefingGetCommand.resolveDate("latest") == "latest")
        #expect(BriefingGetCommand.resolveDate("Latest") == "latest")
        #expect(BriefingGetCommand.resolveDate("LATEST") == "latest")
    }

    @Test("resolveDate passes YYYY-MM-DD through unchanged")
    func resolvesPassThrough() {
        #expect(BriefingGetCommand.resolveDate("2026-06-24") == "2026-06-24")
    }

    // MARK: - Validation success path

    @Test("validateBriefingGet accepts well-formed YYYY-MM-DD")
    func validDateAccepted() throws {
        try SchemaValidator.validateBriefingGet(date: "2026-06-24")
    }

    @Test("validateBriefingGet accepts 'latest' sugar value")
    func latestAccepted() throws {
        try SchemaValidator.validateBriefingGet(date: "latest")
    }

    // MARK: - Validation failure paths

    @Test("validateBriefingGet rejects empty date with schema.missing_required_field")
    func emptyDateRejected() {
        do {
            try SchemaValidator.validateBriefingGet(date: "")
            Issue.record("Expected XPCError for empty date")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateBriefingGet rejects malformed date with schema.invalid_date")
    func invalidDateRejected() {
        do {
            try SchemaValidator.validateBriefingGet(date: "not-a-date")
            Issue.record("Expected XPCError for invalid date")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
            #expect(error.field == "date")
            #expect(error.got == "not-a-date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Params encoding (Codable round-trip)

    @Test("BriefingGetParams encodes date and includeDrafts")
    func paramsEncoded() throws {
        let params = BriefingGetParams(date: "2026-06-24", includeDrafts: true)
        let data = try JSONEncoder().encode(params)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["date"] as? String == "2026-06-24")
        #expect(obj["includeDrafts"] as? Bool == true)
    }

    @Test("BriefingGetParams defaults includeDrafts to false when init omits it")
    func paramsDefaultsIncludeDrafts() {
        let params = BriefingGetParams(date: "2026-06-24")
        #expect(params.includeDrafts == false)
    }

    /// Backward compatibility (XPC contract additive-change rule): older
    /// request payloads that predate `includeDrafts` must still decode.
    @Test("BriefingGetParams decodes legacy payload without includeDrafts (defaults to false)")
    func paramsDecodesLegacyPayload() throws {
        let legacy = Data(#"{"date":"2026-06-24"}"#.utf8)
        let decoded = try JSONDecoder().decode(BriefingGetParams.self, from: legacy)
        #expect(decoded.date == "2026-06-24")
        #expect(decoded.includeDrafts == false)
    }

    @Test("BriefingGetParams round-trips includeDrafts=true through Codable")
    func paramsRoundTrips() throws {
        let original = BriefingGetParams(date: "2026-06-24", includeDrafts: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BriefingGetParams.self, from: data)
        #expect(decoded.date == original.date)
        #expect(decoded.includeDrafts == original.includeDrafts)
    }

    // MARK: - Command wiring: XPC request construction (mirrors BriefingGetCommand.run)

    /// Asserts that `BriefingGetParams` round-trips through `XPCRequest.params`
    /// as the exact JSON shape the app-side `briefing.get` handler expects.
    /// See `contracts/xpc-protocol.md` §"Request envelope".
    @Test("buildXPCRequest packs BriefingGetParams as the documented briefing.get envelope")
    func buildsBriefingGetRequest() throws {
        let params = BriefingGetParams(date: "2026-06-24", includeDrafts: false)
        let paramsData = try JSONEncoder().encode(params)
        let request = XPCRequest(
            requestId: "req-briefing-get-1",
            cliVersion: "1.0.0",
            command: "briefing.get",
            params: paramsData
        )

        #expect(request.command == "briefing.get")
        #expect(request.cliVersion == "1.0.0")
        #expect(request.requestId == "req-briefing-get-1")

        let decoded = try JSONDecoder().decode(BriefingGetParams.self, from: request.params)
        #expect(decoded.date == "2026-06-24")
        #expect(decoded.includeDrafts == false)
    }

    // MARK: - BriefingGetResult decoding from a synthetic XPC response

    /// Mirrors BriefingGetCommand.run's success path: take the bytes the
    /// app-side `briefing.get` handler would put in `XPCResponse.data`,
    /// decode via the same iso8601 decoder, and assert it round-trips into
    /// the briefing the formatter will emit.
    @Test("BriefingGetResult decodes from the documented success-data shape")
    func decodesBriefingGetResult() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let isoString = ISO8601DateFormatter().string(from: generatedAt)
        let bodyJSON = """
        {"briefing":{"date":"2026-06-24","generatedAt":"\(isoString)","generatedBy":"test-agent","containers":[]}}
        """
        let decoder = JSONDecoder.iso8601Decoder
        let result = try decoder.decode(BriefingGetResult.self, from: Data(bodyJSON.utf8))

        #expect(result.briefing.date == "2026-06-24")
        #expect(result.briefing.generatedBy == "test-agent")
        #expect(result.briefing.containers.isEmpty)
        #expect(Int(result.briefing.generatedAt.timeIntervalSince1970)
                == Int(generatedAt.timeIntervalSince1970))
    }

    // MARK: - Command wiring: JSON success envelope (Constitution §B.1, §G.3)

    /// Success-path test: emitting a `Briefing` through `JSONOutput` produces
    /// the documented `{ok, data, requestId}` envelope on stdout. This is the
    /// formatter-selection + envelope contract `BriefingGetCommand` uses
    /// when `--json` is set.
    @Test("JSONOutput wraps Briefing in the {ok, data, requestId} success envelope")
    func jsonOutputWrapsBriefing() throws {
        let briefing = Briefing(
            date: "2026-06-24",
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            generatedBy: "test-agent",
            containers: []
        )

        let stdout = try captureStdout {
            try JSONOutput().emit(success: briefing, requestId: "req-briefing-get-2")
        }

        let obj = try #require(
            try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == true)
        #expect(obj["requestId"] as? String == "req-briefing-get-2")
        let body = try #require(obj["data"] as? [String: Any])
        #expect(body["date"] as? String == "2026-06-24")
        #expect(body["generatedBy"] as? String == "test-agent")
    }

    // MARK: - Command wiring: remote-error envelope (Constitution §B.2)

    /// Remote-error path: when the server returns an `XPCResponse.error`,
    /// the command must emit a `{ok:false, error:{..., requestId}}` envelope
    /// on stderr with `requestId` nested INSIDE the error object per
    /// `cli-surface.md` §"Error envelope".
    @Test("JSONOutput serializes remote XPCError with requestId nested inside error")
    func jsonOutputNestsRequestIdInsideError() throws {
        let remoteError = XPCError(
            code: "briefing.not_found",
            message: "No briefing for that date",
            field: "date",
            got: "2026-06-24"
        )

        let stderr = try captureStderr {
            try JSONOutput().emit(error: remoteError, requestId: "req-briefing-get-err")
        }

        let obj = try #require(
            try JSONSerialization.jsonObject(with: Data(stderr.utf8)) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == false)
        let errBody = try #require(obj["error"] as? [String: Any])
        #expect(errBody["code"] as? String == "briefing.not_found")
        #expect(errBody["field"] as? String == "date")
        #expect(errBody["got"] as? String == "2026-06-24")
        // Contract: requestId is INSIDE the error object, not at root.
        #expect(errBody["requestId"] as? String == "req-briefing-get-err")
        #expect(obj["requestId"] == nil)
    }

    // MARK: - Exit code mapping (Constitution §B contract)

    @Test("schema.* errors map to exit 1 (local validation)")
    func schemaMapsToOne() {
        let error = XPCError(code: "schema.invalid_date", message: "bad date")
        #expect(ExitCodeMapper.code(for: error) == 1)
    }

    @Test("xpc.* errors map to exit 2 (local transport)")
    func xpcMapsToTwo() {
        let error = XPCError(code: "xpc.timeout", message: "timed out")
        #expect(ExitCodeMapper.code(for: error) == 2)
    }

    @Test("briefing.* errors map to exit 3 (remote)")
    func remoteBriefingMapsToThree() {
        let error = XPCError(code: "briefing.not_found", message: "no briefing")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }

    // MARK: - MY-1455: Remote error retains requestId from XPCResponse

    /// Production-seam test: encodes a synthetic XPCResponse with ok=false,
    /// decodes it through `XPCClient.decodeReply` (the production decode path),
    /// then calls `BriefingGetCommand.emitRemoteError` to verify the full
    /// decoded-reply → command-emit path.
    ///
    /// Asserts:
    /// - decodeReply returns the response (does not throw for ok=false)
    /// - stderr contains the error envelope
    /// - `error.requestId` equals `XPCResponse.requestId`
    /// - root `requestId` is absent
    /// - `error.code` is `briefing.not_found`
    /// - ExitCode(3) is thrown
    @Test("BriefingGetCommand remote-error path via production seam emits response.requestId and exits 3 (MY-1455)")
    func briefingGetRemoteErrorPreservesRequestId() throws {
        // Build and encode a synthetic XPCResponse with ok=false.
        let response = XPCResponse(
            requestId: "xpc-resp-id-456",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: XPCError(
                code: "briefing.not_found",
                message: "No briefing found for date '2026-08-20'"
            )
        )
        let encodedBytes = try JSONEncoder().encode(response)

        // Decode through the production path (XPCClient.decodeReply).
        let decoded = try XPCClient.decodeReply(encodedBytes)

        // Assert decodeReply returns ok=false (not thrown).
        #expect(decoded.ok == false)
        #expect(decoded.requestId == "xpc-resp-id-456")

        // Exercise the command's emitRemoteError with the decoded response.
        let globals = GlobalOptions.test(json: true, quiet: false)
        var capturedExit: Int32?
        let stderr = try captureStderr {
            do {
                try BriefingGetCommand.emitRemoteError(
                    decoded.error!,
                    requestId: decoded.requestId,
                    globals: globals
                )
            } catch let exitCode as ExitCode {
                capturedExit = exitCode.rawValue
            }
        }

        #expect(capturedExit == 3)

        let obj = try #require(
            try JSONSerialization.jsonObject(with: Data(stderr.utf8)) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == false)
        // Root must NOT have requestId
        #expect(obj["requestId"] == nil)
        let errBody = try #require(obj["error"] as? [String: Any])
        #expect(errBody["code"] as? String == "briefing.not_found")
        #expect(errBody["message"] as? String == "No briefing found for date '2026-08-20'")
        // MY-1455 contract: error.requestId equals the XPC response's requestId
        #expect(errBody["requestId"] as? String == "xpc-resp-id-456")
    }
}
