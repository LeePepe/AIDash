import Foundation
import Testing
import ArgumentParser
import AIDashCore

@Suite("BriefingPutCommand")
struct BriefingPutCommandTests {

    // MARK: - Argument parsing

    @Test("parses required flags")
    func parsesRequiredFlags() throws {
        let cmd = try BriefingPutCommand.parse([
            "--date", "2026-06-24",
            "--generated-by", "hermes-cron",
        ])
        #expect(cmd.date == "2026-06-24")
        #expect(cmd.generatedBy == "hermes-cron")
        #expect(cmd.published == false)
    }

    @Test("parses --published flag")
    func parsesPublished() throws {
        let cmd = try BriefingPutCommand.parse([
            "--date", "2026-06-24",
            "--generated-by", "hermes-cron",
            "--published",
        ])
        #expect(cmd.published == true)
    }

    @Test("fails to parse without --date")
    func missingDateFails() {
        do {
            _ = try BriefingPutCommand.parse([
                "--generated-by", "hermes",
            ])
            Issue.record("Expected parse failure for missing --date")
        } catch {
            // ArgumentParser routes to the central handler at runtime.
            #expect(error is any Error)
        }
    }

    @Test("fails to parse without --generated-by")
    func missingGeneratedByFails() {
        do {
            _ = try BriefingPutCommand.parse([
                "--date", "2026-06-24",
            ])
            Issue.record("Expected parse failure for missing --generated-by")
        } catch {
            #expect(error is any Error)
        }
    }

    // MARK: - Local validation

    @Test("validateBriefingPut accepts valid YYYY-MM-DD date + non-empty generatedBy")
    func validAccepted() throws {
        try SchemaValidator.validateBriefingPut(date: "2026-06-24", generatedBy: "hermes")
    }

    @Test("validateBriefingPut rejects empty generatedBy")
    func emptyGeneratedByRejected() {
        do {
            try SchemaValidator.validateBriefingPut(date: "2026-06-24", generatedBy: "")
            Issue.record("Expected XPCError for empty generatedBy")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "generatedBy")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateBriefingPut rejects invalid date format")
    func invalidDateRejected() {
        do {
            try SchemaValidator.validateBriefingPut(date: "not-a-date", generatedBy: "hermes")
            Issue.record("Expected XPCError for invalid date")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
            #expect(error.field == "date")
            #expect(error.got == "not-a-date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Emit (success path)

    @Test("briefing put success path emits {ok:true, data, requestId} JSON envelope")
    func successEnvelopeJSON() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let result = BriefingPutResult(
            date: "2026-06-24",
            generatedAt: generatedAt,
            publishedAt: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        let response = XPCResponse(
            requestId: "req-123",
            appVersion: "test",
            ok: true,
            data: data,
            error: nil
        )
        let globals = GlobalOptions.test(json: true, quiet: false)

        let stdout = try captureStdout {
            try BriefingPutCommand.emit(response: response, globals: globals)
        }

        let json = try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        try #require(json != nil)
        #expect(json?["ok"] as? Bool == true)
        #expect(json?["requestId"] as? String == "req-123")
        let payload = json?["data"] as? [String: Any]
        try #require(payload != nil)
        #expect(payload?["date"] as? String == "2026-06-24")
        #expect(payload?["generatedAt"] is String)
    }

    @Test("briefing put in --quiet mode emits nothing on stdout")
    func quietSuppressesStdout() throws {
        let result = BriefingPutResult(
            date: "2026-06-24",
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            publishedAt: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        let response = XPCResponse(
            requestId: "req-quiet",
            appVersion: "test",
            ok: true,
            data: data,
            error: nil
        )
        let globals = GlobalOptions.test(json: true, quiet: true)

        let stdout = try captureStdout {
            try BriefingPutCommand.emit(response: response, globals: globals)
        }
        #expect(stdout.isEmpty)
    }

    // MARK: - Emit (remote error path)

    @Test("briefing put remote error emits {ok:false, error{...,requestId}} JSON on stderr and exits 3")
    func remoteErrorEnvelopeJSON() throws {
        let errorBody = XPCError(
            code: "briefing.not_found",
            message: "No briefing for date",
            field: "date",
            got: "2099-01-01"
        )
        let response = XPCResponse(
            requestId: "req-err",
            appVersion: "test",
            ok: false,
            data: nil,
            error: errorBody
        )
        let globals = GlobalOptions.test(json: true, quiet: false)

        var capturedExit: Int32? = nil
        let stderr = try captureStderr {
            do {
                try BriefingPutCommand.emit(response: response, globals: globals)
                Issue.record("Expected ExitCode to be thrown")
            } catch let code as ExitCode {
                capturedExit = code.rawValue
            }
        }
        #expect(capturedExit == 3)

        let json = try JSONSerialization.jsonObject(with: Data(stderr.utf8)) as? [String: Any]
        try #require(json != nil)
        #expect(json?["ok"] as? Bool == false)
        let errObj = json?["error"] as? [String: Any]
        try #require(errObj != nil)
        #expect(errObj?["code"] as? String == "briefing.not_found")
        // requestId MUST live inside the error object per cli-surface.md
        #expect(errObj?["requestId"] as? String == "req-err")
        #expect(json?["requestId"] == nil)
    }

    @Test("briefing put remote schema error still exits 3 (server-returned = app-side)")
    func remoteSchemaErrorExits3() throws {
        let errorBody = XPCError(
            code: "schema.invalid_uuid",
            message: "Bad UUID server-side"
        )
        let response = XPCResponse(
            requestId: "req-schema",
            appVersion: "test",
            ok: false,
            data: nil,
            error: errorBody
        )
        var capturedExit: Int32? = nil
        _ = try captureStderr {
            do {
                try BriefingPutCommand.emit(
                    response: response,
                    globals: GlobalOptions.test(json: true, quiet: false)
                )
                Issue.record("Expected ExitCode to be thrown")
            } catch let code as ExitCode {
                capturedExit = code.rawValue
            }
        }
        #expect(capturedExit == 3)
    }

    // MARK: - Emit (malformed response)

    @Test("ok=true with no data payload throws XPCError xpc.decode_failure")
    func okWithoutDataIsDecodeFailure() throws {
        let response = XPCResponse(
            requestId: "req-no-data",
            appVersion: "test",
            ok: true,
            data: nil,
            error: nil
        )
        do {
            try BriefingPutCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
            Issue.record("Expected XPCError to be thrown")
        } catch let err as XPCError {
            #expect(err.code == "xpc.decode_failure")
        }
    }

    @Test("ok=true with undecodable data throws XPCError xpc.decode_failure")
    func undecodableDataIsDecodeFailure() throws {
        let response = XPCResponse(
            requestId: "req-bad-data",
            appVersion: "test",
            ok: true,
            data: Data("{\"unexpected\":\"shape\"}".utf8),
            error: nil
        )
        do {
            try BriefingPutCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
            Issue.record("Expected XPCError to be thrown")
        } catch let err as XPCError {
            #expect(err.code == "xpc.decode_failure")
        }
    }

    @Test("ok=false with no error payload throws XPCError xpc.decode_failure")
    func okFalseWithoutErrorIsDecodeFailure() throws {
        let response = XPCResponse(
            requestId: "req-empty-err",
            appVersion: "test",
            ok: false,
            data: nil,
            error: nil
        )
        do {
            try BriefingPutCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
            Issue.record("Expected XPCError to be thrown")
        } catch let err as XPCError {
            #expect(err.code == "xpc.decode_failure")
        }
    }
}
