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

        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "briefing.publish",
            params: paramsData
        )

        let client = XPCClient()
        let response = try await client.execute(request)

        if response.ok, let data = response.data {
            let result = try JSONDecoder.iso8601Decoder.decode(
                BriefingPublishResult.self, from: data
            )
            let formatter = globals.outputMode.formatter()
            try formatter.emit(success: result)
        } else if let error = response.error {
            throw error
        }
    }
}

// MARK: - Global Options (shared across all commands)

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet = false

    var outputMode: OutputMode {
        json ? .json : .human
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
