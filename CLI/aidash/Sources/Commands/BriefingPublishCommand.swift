import ArgumentParser
import Foundation
import AIDashCore

struct BriefingPublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Mark a briefing as visible to readers."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Briefing date (YYYY-MM-DD, 'today', or 'yesterday').")
    var date: String

    func run() async throws {
        let resolvedDate = resolveDate(date)

        // Local validation — fail fast with exit 1.
        do {
            try SchemaValidator.validateBriefingPublish(date: resolvedDate)
        } catch let error as XPCError {
            try globals.formatter.emit(error: error)
            throw ExitCode(1)
        }

        // Build XPC request.
        let params = BriefingPublishParams(date: resolvedDate)
        let paramsData = try JSONEncoder().encode(params)
        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: AIDash.configuration.version ?? "1.0.0",
            command: "briefing.publish",
            params: paramsData
        )

        // Execute XPC call.
        let response: XPCResponse
        do {
            response = try await XPCClient().execute(request)
        } catch let error as XPCError {
            try globals.formatter.emit(error: error)
            throw ExitCode(2)
        }

        // Handle response.
        if response.ok, let data = response.data {
            let result = try JSONDecoder.xpc.decode(BriefingPublishResult.self, from: data)
            try globals.formatter.emit(success: result)
        } else if let error = response.error {
            try globals.formatter.emit(error: error)
            throw ExitCode(3)
        }
    }

    /// Resolve `today`/`yesterday` sugar into YYYY-MM-DD.
    private func resolveDate(_ input: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        switch input.lowercased() {
        case "today":
            return formatter.string(from: Date())
        case "yesterday":
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            return formatter.string(from: yesterday ?? Date())
        default:
            return input
        }
    }
}

// MARK: - Global Options

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet = false

    var formatter: any OutputFormatter {
        json ? JSONOutput() : HumanOutput()
    }
}

// MARK: - JSONDecoder extension for XPC date handling

extension JSONDecoder {
    static let xpc: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
