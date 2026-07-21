import Foundation
import Testing
import ArgumentParser
import AIDashCore

@Suite("BriefingPublishCommand")
struct BriefingPublishCommandTests {

    // MARK: - Date resolution

    @Test("resolves 'today' to current date in YYYY-MM-DD format")
    func resolvesToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expected = formatter.string(from: Date())

        let resolved = DateResolver.resolve("today")
        #expect(resolved == expected)
    }

    @Test("resolves 'yesterday' to previous date")
    func resolvesYesterday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let expected = formatter.string(from: yesterday)

        let resolved = DateResolver.resolve("yesterday")
        #expect(resolved == expected)
    }

    @Test("passes through YYYY-MM-DD dates unchanged")
    func passesThrough() {
        let resolved = DateResolver.resolve("2026-06-24")
        #expect(resolved == "2026-06-24")
    }

    @Test("resolution is case-insensitive")
    func caseInsensitive() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expected = formatter.string(from: Date())

        #expect(DateResolver.resolve("TODAY") == expected)
        #expect(DateResolver.resolve("Today") == expected)
    }

    // MARK: - Validation

    @Test("validateBriefingPublish accepts valid YYYY-MM-DD date")
    func validDateAccepted() throws {
        try SchemaValidator.validateBriefingPublish(date: "2026-06-24")
    }

    @Test("validateBriefingPublish rejects empty date")
    func emptyDateRejected() {
        do {
            try SchemaValidator.validateBriefingPublish(date: "")
            Issue.record("Expected XPCError for empty date")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateBriefingPublish rejects invalid date format")
    func invalidDateRejected() {
        do {
            try SchemaValidator.validateBriefingPublish(date: "not-a-date")
            Issue.record("Expected XPCError for invalid date")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
            #expect(error.field == "date")
            #expect(error.got == "not-a-date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateBriefingPublish rejects invalid month")
    func invalidMonthRejected() {
        do {
            try SchemaValidator.validateBriefingPublish(date: "2026-13-01")
            Issue.record("Expected XPCError for invalid month")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Argument parsing (CLI subcommand wiring)

    @Test("parses required --date flag")
    func parsesDateFlag() throws {
        let cmd = try BriefingPublishCommand.parse([
            "--date", "2026-06-24",
        ])
        #expect(cmd.date == "2026-06-24")
    }

    @Test("fails to parse without --date")
    func missingDateFails() {
        do {
            _ = try BriefingPublishCommand.parse([])
            Issue.record("Expected parse failure for missing --date")
        } catch {
            // ArgumentParser routes to the central handler at runtime.
            #expect(error is any Error)
        }
    }

    // MARK: - Emit success path (Constitution §G.3 success envelope)

    /// Asserts the documented `{ok, data, requestId}` JSON envelope shape
    /// when the app returns a `BriefingPublishResult` per
    /// `contracts/cli-surface.md` §"aidash briefing publish":
    ///   Success data: `{ "date": "...", "publishedAt": "..." }`.
    @Test("briefing publish success path emits {ok:true, data, requestId} JSON envelope")
    func successEnvelopeJSON() throws {
        let publishedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let result = BriefingPublishResult(
            date: "2026-06-24",
            publishedAt: publishedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        let response = XPCResponse(
            requestId: "req-pub-1",
            appVersion: "test",
            ok: true,
            data: data,
            error: nil
        )
        let globals = GlobalOptions.test(json: true, quiet: false)

        let stdout = try captureStdout {
            try BriefingPublishCommand.emit(response: response, globals: globals)
        }

        let json = try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any]
        try #require(json != nil)
        #expect(json?["ok"] as? Bool == true)
        #expect(json?["requestId"] as? String == "req-pub-1")
        let payload = json?["data"] as? [String: Any]
        try #require(payload != nil)
        #expect(payload?["date"] as? String == "2026-06-24")
        #expect(payload?["publishedAt"] is String)
    }

    @Test("briefing publish in --quiet mode emits nothing on stdout")
    func quietSuppressesStdout() throws {
        let result = BriefingPublishResult(
            date: "2026-06-24",
            publishedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        let response = XPCResponse(
            requestId: "req-pub-quiet",
            appVersion: "test",
            ok: true,
            data: data,
            error: nil
        )
        let globals = GlobalOptions.test(json: true, quiet: true)

        let stdout = try captureStdout {
            try BriefingPublishCommand.emit(response: response, globals: globals)
        }
        #expect(stdout.isEmpty)
    }

    // MARK: - Emit remote-error path (validation-failure surface from server)

    /// Remote-error path: validate that the documented `briefing.not_found`
    /// surface (per `cli-surface.md` §"Errors" for `briefing publish`)
    /// produces the `{ok:false, error{..., requestId}}` envelope on stderr
    /// and exits 3 — the cli-surface contract guarantees server-returned
    /// errors always exit 3.
    @Test("briefing publish remote briefing.not_found emits envelope on stderr and exits 3")
    func remoteNotFoundEnvelopeJSON() throws {
        let errorBody = XPCError(
            code: "briefing.not_found",
            message: "No Briefing exists for that date",
            field: "date",
            got: "2099-01-01"
        )
        let response = XPCResponse(
            requestId: "req-pub-nf",
            appVersion: "test",
            ok: false,
            data: nil,
            error: errorBody
        )
        let globals = GlobalOptions.test(json: true, quiet: false)

        var capturedExit: Int32? = nil
        let stderr = try captureStderr {
            do {
                try BriefingPublishCommand.emit(response: response, globals: globals)
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
        #expect(errObj?["requestId"] as? String == "req-pub-nf")
        #expect(json?["requestId"] == nil)
    }

    // MARK: - Emit malformed-response failure paths

    @Test("ok=true with no data payload throws XPCError xpc.decode_failure")
    func okWithoutDataIsDecodeFailure() throws {
        let response = XPCResponse(
            requestId: "req-pub-no-data",
            appVersion: "test",
            ok: true,
            data: nil,
            error: nil
        )
        do {
            try BriefingPublishCommand.emit(
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
            requestId: "req-pub-bad-data",
            appVersion: "test",
            ok: true,
            data: Data("{\"unexpected\":\"shape\"}".utf8),
            error: nil
        )
        do {
            try BriefingPublishCommand.emit(
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
            requestId: "req-pub-empty-err",
            appVersion: "test",
            ok: false,
            data: nil,
            error: nil
        )
        do {
            try BriefingPublishCommand.emit(
                response: response,
                globals: GlobalOptions.test(json: true, quiet: false)
            )
            Issue.record("Expected XPCError to be thrown")
        } catch let err as XPCError {
            #expect(err.code == "xpc.decode_failure")
        }
    }
}

// MARK: - handleExecuteError (XPCClient.execute throws-only path)

@Suite("BriefingPublishCommand.handleExecuteError")
struct BriefingPublishExecuteErrorTests {

    @Test("local xpc.* error is rethrown (central handler maps to exit 2)")
    func localXpcErrorRethrown() throws {
        let local = XPCError(code: "xpc.timeout", message: "no reply in 5s")
        do {
            try BriefingPublishCommand.handleExecuteError(
                local,
                requestId: "req-pub-local",
                globals: GlobalOptions.test(json: true, quiet: false)
            )
            Issue.record("Expected XPCError to be rethrown for local xpc.* code")
        } catch let err as XPCError {
            #expect(err.code == "xpc.timeout")
            #expect(err.message == "no reply in 5s")
        }
    }

    @Test("remote briefing.* error emits envelope on stderr with requestId and throws ExitCode(3)")
    func remoteAppErrorEmitsAndExits3() throws {
        let remote = XPCError(
            code: "briefing.not_found",
            message: "Not found",
            field: "date",
            got: "2099-01-01"
        )
        var capturedExit: Int32? = nil
        let stderr = try captureStderr {
            do {
                try BriefingPublishCommand.handleExecuteError(
                    remote,
                    requestId: "req-pub-remote",
                    globals: GlobalOptions.test(json: true, quiet: false)
                )
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
        #expect(errObj?["requestId"] as? String == "req-pub-remote")
        #expect(json?["requestId"] == nil)
    }

    @Test("remote schema.* error still exits 3 (reserved-prefix rule applies to local only)")
    func remoteSchemaErrorStillExits3() throws {
        let remote = XPCError(code: "schema.invalid_uuid", message: "server-side bad UUID")
        var capturedExit: Int32? = nil
        _ = try captureStderr {
            do {
                try BriefingPublishCommand.handleExecuteError(
                    remote,
                    requestId: "req-pub-schema-remote",
                    globals: GlobalOptions.test(json: true, quiet: false)
                )
                Issue.record("Expected ExitCode to be thrown")
            } catch let code as ExitCode {
                capturedExit = code.rawValue
            }
        }
        #expect(capturedExit == 3)
    }
}

// MARK: - ExitCodeMapper tests

@Suite("ExitCodeMapper")
struct ExitCodeMapperTests {

    @Test("schema errors map to exit 1")
    func schemaErrors() {
        let error = XPCError(code: "schema.invalid_date", message: "bad date")
        #expect(ExitCodeMapper.code(for: error) == 1)
    }

    @Test("xpc errors map to exit 2")
    func xpcErrors() {
        let error = XPCError(code: "xpc.app_unavailable", message: "no app")
        #expect(ExitCodeMapper.code(for: error) == 2)
    }

    @Test("remote errors map to exit 3")
    func remoteErrors() {
        let error = XPCError(code: "briefing.not_found", message: "no briefing")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }

    @Test("internal errors map to exit 3")
    func internalErrors() {
        let error = XPCError(code: "internal.unexpected", message: "oops")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }

    @Test("cloudkit errors map to exit 3")
    func cloudkitErrors() {
        let error = XPCError(code: "cloudkit.quota_exceeded", message: "quota")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }
}
