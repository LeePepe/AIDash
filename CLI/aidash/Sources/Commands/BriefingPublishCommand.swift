import ArgumentParser
import AIDashCore
import Foundation

/// `aidash briefing publish --date <YYYY-MM-DD|today|yesterday>`
///
/// Marks a briefing as visible to readers (atomic publish per spec FR-006).
/// Idempotent — calling on an already-published briefing returns existing publishedAt.
///
/// Error-flow contract (matches `BriefingPutCommand`):
///   - Local validation failures → throw `XPCError` with `schema.*` code;
///     central handler in `AIDash.main` emits envelope + exits 1 via
///     `ExitCodeMapper`.
///   - Local XPC transport failures (`xpc.*`) → propagate from
///     `XPCClient.execute`; central handler emits + exits 2.
///   - Remote `ok=false` → emit the envelope here (so it carries
///     `response.requestId`) and throw `ExitCode(3)`. Per
///     `cli-surface.md` §"Exit codes" a server-returned error is ALWAYS
///     exit 3, even if its `code` happens to start with `schema.` or
///     `xpc.` (those prefixes are reserved for LOCAL classification).
struct BriefingPublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Mark a briefing as visible to readers."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Briefing date (YYYY-MM-DD, 'today', or 'yesterday').")
    var date: String

    func run() async throws {
        let resolvedDate = DateResolver.resolve(date)
        try SchemaValidator.validateBriefingPublish(date: resolvedDate)

        let params = BriefingPublishParams(date: resolvedDate)
        let paramsData = try JSONEncoder().encode(params)

        let requestId = UUID().uuidString
        let request = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "briefing.publish",
            params: paramsData
        )

        let response: XPCResponse
        do {
            response = try await XPCClient().execute(request)
        } catch let error as XPCError {
            do {
                try Self.handleExecuteError(error, requestId: requestId, globals: globals)
            } catch let exitCode as ExitCode {
                Darwin.exit(exitCode.rawValue)
            }
            return
        }

        do {
            try Self.emit(response: response, globals: globals)
        } catch let exitCode as ExitCode {
            Darwin.exit(exitCode.rawValue)
        }
    }

    // MARK: - Execute-error triage (extracted for tests).
    //
    // `XPCClient.execute` throws a single `XPCError` type for two distinct
    // failure classes (the actor's `resultForResponse` re-throws remote
    // envelope errors instead of returning the failed `XPCResponse`). Per
    // `cli-surface.md` §"Exit codes" we MUST disambiguate before exiting:
    //
    //   - Local `xpc.*` (transport/timeout/decode) → rethrow so the
    //     central handler maps via `ExitCodeMapper` → exit 2.
    //   - Anything else → REMOTE server error. Every server-returned error
    //     exits 3 regardless of code class, so remote `schema.*` and
    //     remote `xpc.*` still exit 3. Emit the envelope on stderr with
    //     the request id and throw `ExitCode(3)`.
    static func handleExecuteError(
        _ error: XPCError,
        requestId: String,
        globals: GlobalOptions
    ) throws {
        if error.code.hasPrefix("xpc.") {
            throw error
        }
        let formatter = globals.outputMode.formatter()
        try formatter.emit(error: error, requestId: requestId)
        throw ExitCode(3)
    }

    // MARK: - Emit (extracted for tests).

    static func emit(
        response: XPCResponse,
        globals: GlobalOptions
    ) throws {
        if response.ok {
            guard let data = response.data else {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Server returned ok=true but no data payload"
                )
            }
            let result: BriefingPublishResult
            do {
                result = try JSONDecoder.iso8601Decoder.decode(
                    BriefingPublishResult.self, from: data
                )
            } catch {
                throw XPCError(
                    code: "xpc.decode_failure",
                    message: "Failed to decode BriefingPublishResult: \(error.localizedDescription)"
                )
            }
            if !globals.isQuiet {
                let formatter = globals.outputMode.formatter()
                try formatter.emit(success: result, requestId: response.requestId)
            }
            return
        }

        if let remoteError = response.error {
            let formatter = globals.outputMode.formatter()
            try formatter.emit(error: remoteError, requestId: response.requestId)
            throw ExitCode(3)
        }

        throw XPCError(
            code: "xpc.decode_failure",
            message: "Server returned ok=false but no error payload"
        )
    }
}

// MARK: - Global Options (shared across all commands)

/// Detects `--json` and `--quiet` from both leaf-level ArgumentParser parsing
/// AND root-level process arguments (e.g. `aidash --json briefing publish ...`).
/// This allows flags before or after the subcommand verb.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet = false

    var outputMode: OutputMode {
        let isJSON = json || ProcessInfo.processInfo.arguments.contains("--json")
        return isJSON ? .json : .human
    }

    var isQuiet: Bool {
        quiet || ProcessInfo.processInfo.arguments.contains("--quiet")
    }
}

// MARK: - JSONDecoder extension

extension JSONDecoder {
    static let iso8601Decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
