import Foundation
import Testing
import AIDashCore
import ArgumentParser

@Suite("ContainerPutCommand")
struct ContainerPutCommandTests {

    // MARK: - Argument Parsing

    @Test("parses all required flags")
    func parsesRequiredFlags() throws {
        let args = [
            "--briefing-date", "2026-06-25",
            "--id", "11111111-1111-1111-1111-111111111111",
            "--title", "Morning Wins",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "2026-06-25")
        #expect(cmd.id == "11111111-1111-1111-1111-111111111111")
        #expect(cmd.title == "Morning Wins")
        #expect(cmd.order == 10)
        #expect(cmd.layout == "auto")
        #expect(cmd.style == "neutral")
        #expect(cmd.globals.json == false)
        #expect(cmd.globals.quiet == false)
    }

    @Test("parses all optional flags")
    func parsesOptionalFlags() throws {
        let args = [
            "--briefing-date", "today",
            "--id", "22222222-2222-2222-2222-222222222222",
            "--title", "Evening Review",
            "--subtitle", "A summary",
            "--order", "20",
            "--layout", "grid",
            "--style", "accent",
            "--json",
            "--quiet",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.subtitle == "A summary")
        #expect(cmd.layout == "grid")
        #expect(cmd.style == "accent")
        #expect(cmd.globals.json == true)
        #expect(cmd.globals.quiet == true)
    }

    @Test("defaults layout to auto and style to neutral")
    func defaultValues() throws {
        let args = [
            "--briefing-date", "yesterday",
            "--id", "33333333-3333-3333-3333-333333333333",
            "--title", "Test",
            "--order", "30",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.layout == "auto")
        #expect(cmd.style == "neutral")
    }

    @Test("fails to parse when missing required --briefing-date")
    func missingBriefingDate() {
        let args = [
            "--id", "44444444-4444-4444-4444-444444444444",
            "--title", "Test",
            "--order", "10",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    @Test("fails to parse when missing required --id")
    func missingId() {
        let args = [
            "--briefing-date", "today",
            "--title", "Test",
            "--order", "10",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    @Test("fails to parse when missing required --title")
    func missingTitle() {
        let args = [
            "--briefing-date", "today",
            "--id", "55555555-5555-5555-5555-555555555555",
            "--order", "10",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    @Test("fails to parse when missing required --order")
    func missingOrder() {
        let args = [
            "--briefing-date", "today",
            "--id", "66666666-6666-6666-6666-666666666666",
            "--title", "Test",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    @Test("fails to parse when --order is not an integer")
    func nonIntegerOrder() {
        let args = [
            "--briefing-date", "today",
            "--id", "77777777-7777-7777-7777-777777777777",
            "--title", "Test",
            "--order", "abc",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    // MARK: - Date Parsing Pass-Through (DateResolver / run-time validation
    // covered indirectly here; run-time error → exit 1 envelope is covered
    // in the subcommand-level emit tests below.)

    @Test("accepts valid YYYY-MM-DD date")
    func acceptsValidDate() throws {
        let args = [
            "--briefing-date", "2026-06-25",
            "--id", "ffffffff-ffff-ffff-ffff-ffffffffffff",
            "--title", "Test",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "2026-06-25")
    }

    @Test("accepts 'today' as briefing-date")
    func acceptsTodayDate() throws {
        let args = [
            "--briefing-date", "today",
            "--id", "ffffffff-ffff-ffff-ffff-ffffffffffff",
            "--title", "Test",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "today")
    }

    @Test("accepts 'yesterday' as briefing-date")
    func acceptsYesterdayDate() throws {
        let args = [
            "--briefing-date", "yesterday",
            "--id", "ffffffff-ffff-ffff-ffff-ffffffffffff",
            "--title", "Test",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "yesterday")
    }

    // MARK: - Subcommand-level emit tests
    //
    // These drive the actual `container put` subcommand emit path with a
    // synthetic `XPCResponse`, capturing stdout/stderr via the FD-redirect
    // helpers below. They cover acceptance criteria from cli-surface.md and
    // constitution §G: success envelope, error envelope, exit-code mapping,
    // and requestId placement.

    @Test("container put success path emits {ok:true, data, requestId} JSON envelope")
    func successEnvelopeJSON() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let result = ContainerPutResult(
            id: "11111111-1111-1111-1111-111111111111",
            updatedAt: updatedAt,
            wasCreated: true
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
            try ContainerPutCommand.emit(
                response: response,
                globals: globals,
                requestedId: "req-123"
            )
        }

        let bytes = Data(stdout.utf8)
        let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        try #require(json != nil)
        #expect(json?["ok"] as? Bool == true)
        #expect(json?["requestId"] as? String == "req-123")
        let payload = json?["data"] as? [String: Any]
        try #require(payload != nil)
        #expect(payload?["id"] as? String == "11111111-1111-1111-1111-111111111111")
        #expect(payload?["wasCreated"] as? Bool == true)
        #expect(payload?["updatedAt"] is String)
    }

    @Test("container put remote error emits {ok:false, error{...,requestId}} JSON on stderr and exits 3")
    func remoteErrorEnvelopeJSON() throws {
        let errorBody = XPCError(
            code: "briefing.not_found",
            message: "No briefing for date",
            field: "briefingDate",
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
                try ContainerPutCommand.emit(
                    response: response,
                    globals: globals,
                    requestedId: "req-err"
                )
                Issue.record("Expected ExitCode to be thrown")
            } catch let code as ExitCode {
                capturedExit = code.rawValue
            }
        }
        #expect(capturedExit == 3)

        let bytes = Data(stderr.utf8)
        let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        try #require(json != nil)
        #expect(json?["ok"] as? Bool == false)
        let errObj = json?["error"] as? [String: Any]
        try #require(errObj != nil)
        #expect(errObj?["code"] as? String == "briefing.not_found")
        #expect(errObj?["message"] as? String == "No briefing for date")
        // requestId MUST live inside the error object per cli-surface.md
        #expect(errObj?["requestId"] as? String == "req-err")
        // ... and NOT at the top level.
        #expect(json?["requestId"] == nil)
    }

    @Test("container put schema remote error exits 1")
    func remoteSchemaErrorExits1() throws {
        let errorBody = XPCError(
            code: "schema.invalid_uuid",
            message: "bad uuid",
            field: "id",
            got: "not-a-uuid"
        )
        let response = XPCResponse(
            requestId: "req-s",
            appVersion: "test",
            ok: false,
            data: nil,
            error: errorBody
        )
        var capturedExit: Int32? = nil
        _ = try captureStderr {
            do {
                try ContainerPutCommand.emit(
                    response: response,
                    globals: GlobalOptions.test(json: true, quiet: false),
                    requestedId: "req-s"
                )
            } catch let code as ExitCode {
                capturedExit = code.rawValue
            }
        }
        #expect(capturedExit == 1)
    }

    @Test("container put xpc remote error exits 2")
    func remoteXpcErrorExits2() throws {
        let errorBody = XPCError(
            code: "xpc.connection_invalidated",
            message: "lost"
        )
        let response = XPCResponse(
            requestId: "req-x",
            appVersion: "test",
            ok: false,
            data: nil,
            error: errorBody
        )
        var capturedExit: Int32? = nil
        _ = try captureStderr {
            do {
                try ContainerPutCommand.emit(
                    response: response,
                    globals: GlobalOptions.test(json: true, quiet: false),
                    requestedId: "req-x"
                )
            } catch let code as ExitCode {
                capturedExit = code.rawValue
            }
        }
        #expect(capturedExit == 2)
    }

    @Test("container put in --quiet mode emits nothing on stdout")
    func successQuietEmitsNothing() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let result = ContainerPutResult(
            id: "11111111-1111-1111-1111-111111111111",
            updatedAt: updatedAt,
            wasCreated: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        let response = XPCResponse(
            requestId: "req-q",
            appVersion: "test",
            ok: true,
            data: data,
            error: nil
        )
        let globals = GlobalOptions.test(json: true, quiet: true)

        let stdout = try captureStdout {
            try ContainerPutCommand.emit(
                response: response,
                globals: globals,
                requestedId: "req-q"
            )
        }
        #expect(stdout.isEmpty)
    }
}

// MARK: - GlobalOptions test helper

extension GlobalOptions {
    /// Test-only convenience that parses through ArgumentParser so we don't
    /// reach into framework internals.
    static func test(json: Bool, quiet: Bool) -> GlobalOptions {
        var args: [String] = []
        if json { args.append("--json") }
        if quiet { args.append("--quiet") }
        // ParsableArguments must succeed for empty input too.
        return (try? GlobalOptions.parse(args)) ?? (try! GlobalOptions.parse([]))
    }
}

// MARK: - stdout/stderr capture helpers
//
// We redirect the live POSIX FD into a temporary file (not a pipe) so the
// Swift Testing framework's own output written during the captured block
// can drain freely without blocking the writer side, and we can read the
// captured slice back after restoring the FD. Using a Pipe here deadlocks
// once the pipe buffer fills because Swift Testing keeps writing to the
// redirected FD throughout the test run.

func captureStdout(_ block: () throws -> Void) throws -> String {
    try captureFD(STDOUT_FILENO, block)
}

func captureStderr(_ block: () throws -> Void) throws -> String {
    try captureFD(STDERR_FILENO, block)
}

private func captureFD(_ fd: Int32, _ block: () throws -> Void) throws -> String {
    let saved = dup(fd)
    defer { close(saved) }

    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("aidash-capture-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
    let writeHandle = try FileHandle(forWritingTo: tmpURL)
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    dup2(writeHandle.fileDescriptor, fd)

    var thrown: Error?
    do {
        try block()
    } catch {
        thrown = error
    }

    // Flush + restore.
    try? writeHandle.synchronize()
    dup2(saved, fd)
    try? writeHandle.close()

    let captured = (try? String(contentsOf: tmpURL, encoding: .utf8)) ?? ""
    if let thrown { throw thrown }
    return captured
}
