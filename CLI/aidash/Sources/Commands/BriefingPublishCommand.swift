import ArgumentParser
import AIDashCore
import Foundation

/// `aidash briefing publish --date <YYYY-MM-DD|today|yesterday>`
///
/// Marks a briefing as visible to readers (atomic publish per spec FR-006).
/// Idempotent — calling on an already-published briefing returns existing publishedAt.
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

        let client = XPCClient()
        let response = try await client.execute(request)

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
            let formatter = globals.outputMode.formatter(requestId: response.requestId)
            if !globals.isQuiet {
                try formatter.emit(success: result)
            }
        } else if let error = response.error {
            let remoteError = XPCError(
                code: error.code,
                message: error.message,
                field: error.field,
                got: error.got,
                allowed: error.allowed,
                cause: error.cause
            )
            let formatter = globals.outputMode.formatter(requestId: response.requestId)
            try formatter.emit(error: remoteError)
            Darwin.exit(ExitCodeMapper.code(for: remoteError))
        } else {
            throw XPCError(
                code: "xpc.decode_failure",
                message: "Server returned ok=false but no error payload"
            )
        }
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
