import AIDashCore
import ArgumentParser
import Foundation

/// `aidash briefing put` — create or update a Briefing's top-level metadata.
/// Idempotent by `--date`.
struct BriefingPutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "put",
        abstract: "Create or update a briefing's metadata."
    )

    // MARK: - Arguments

    @Option(name: .long, help: "Briefing date (YYYY-MM-DD, 'today', or 'yesterday').")
    var date: String

    @Option(name: .customLong("generated-by"), help: "Name of the agent/script publishing.")
    var generatedBy: String

    @Flag(name: .long, help: "Also publish the briefing atomically.")
    var published: Bool = false

    @OptionGroup var globalOptions: GlobalOptions

    // MARK: - Execution

    func run() async throws {
        let requestId = UUID().uuidString

        // Resolve date sugar (today/yesterday → YYYY-MM-DD)
        let resolvedDate = resolveDate(date)

        // Local validation — fail fast, NEVER round-trip invalid data
        do {
            try SchemaValidator.validateBriefingPut(
                date: resolvedDate,
                generatedBy: generatedBy
            )
        } catch let error as XPCError {
            CLIError.exit(error, requestId: requestId, code: .localValidation)
        }

        // Build params
        let params = BriefingPutParams(
            date: resolvedDate,
            generatedBy: generatedBy,
            published: published
        )

        // Encode params and build XPC request
        let paramsData = try JSONEncoder().encode(params)
        let request = XPCRequest(
            requestId: requestId,
            cliVersion: AIDashCLI.configuration.version,
            command: "briefing.put",
            params: paramsData
        )

        // Send via XPC
        let response: XPCResponse
        do {
            response = try await XPCClient().execute(request)
        } catch let error as XPCError {
            CLIError.exit(error, requestId: requestId, code: .xpcTransport)
        } catch {
            let xpcError = XPCError(
                code: "xpc.app_unavailable",
                message: error.localizedDescription
            )
            CLIError.exit(xpcError, requestId: requestId, code: .xpcTransport)
        }

        // Handle response
        guard response.ok, let data = response.data else {
            if let error = response.error {
                CLIError.exit(
                    error,
                    requestId: requestId,
                    code: ExitCodeMapper.exitCode(for: error)
                )
            }
            return
        }

        let result = try JSONDecoder.iso8601.decode(
            BriefingPutResult.self, from: data
        )

        if globalOptions.json {
            try JSONOutput.writeSuccess(result, requestId: requestId)
        } else if !globalOptions.quiet {
            HumanOutput.writeSuccess(formatResult(result))
        }
    }

    // MARK: - Helpers

    /// Resolve `today`/`yesterday` sugar to YYYY-MM-DD in user's local timezone.
    private func resolveDate(_ input: String) -> String {
        switch input.lowercased() {
        case "today":
            return Self.dateFormatter.string(from: Date())
        case "yesterday":
            let yesterday = Calendar.current.date(
                byAdding: .day, value: -1, to: Date()
            ) ?? Date()
            return Self.dateFormatter.string(from: yesterday)
        default:
            return input
        }
    }

    private func formatResult(_ result: BriefingPutResult) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var output = "Briefing \(result.date) updated"
        output += " (generated at \(iso.string(from: result.generatedAt)))"
        if let pub = result.publishedAt {
            output += ", published at \(iso.string(from: pub))"
        }
        return output
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
