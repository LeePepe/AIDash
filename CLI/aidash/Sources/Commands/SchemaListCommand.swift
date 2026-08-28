import ArgumentParser
import Foundation
import AIDashCore

/// `aidash schema list` — fetch the full AIDash schema (enums + per-CardType
/// payload JSON Schemas) from the app via XPC.
///
/// See `specs/001-core-briefing-cli/contracts/cli-surface.md` §"schema list".
///
/// Subcommand flags (per issue MY-972):
///   --type   <CardType>       optional; filter `payloads` to a single type.
///   --format <json|markdown>  default: json
///
/// Plus global `--json`/`--quiet` (declared on `GlobalOptions`).
///
/// Exit codes:
///   0 — success
///   1 — local validation (`schema.*`)
///   2 — XPC transport (`xpc.*`) or malformed protocol reply (ok=false, no error)
///   3 — remote error (ok=false with error payload; emitted locally with
///       response.requestId on stderr and `Darwin.exit(3)` — MY-1455)
///
/// Output:
///   - `--format json` → success envelope on stdout via `JSONOutput`/`HumanOutput`.
///   - `--format markdown` → human-readable Markdown doc on stdout when global
///     `--json` is NOT set. When `--json` IS set, the Markdown body is wrapped
///     in the standard success envelope as a string (`data.markdown`) so that
///     `aidash --json schema list --format markdown` still emits the contract
///     envelope (per Constitution §B.1).
///   - Errors are always JSON envelopes on stderr; remote errors are emitted
///     locally via `handleFailedResponse` with `response.requestId` and exit 3
///     directly (MY-1455). Malformed ok=false (nil error) throws to the central
///     handler for exit 2.
struct SchemaListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Print the full AIDash schema (enums + per-CardType payload schemas)."
    )

    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case json
        case markdown
    }

    @OptionGroup var globals: GlobalOptions

    @Option(name: .long, help: "Filter the payload schemas to a single CardType (e.g. metric).")
    var type: String?

    @Option(name: .long, help: "Output format: json (default) or markdown.")
    var format: OutputFormat = .json

    func run() async throws {
        // Local-only validation. Fail fast before round-tripping bad input.
        try SchemaValidator.validateSchemaList(type: type)

        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "schema.list",
            params: try JSONEncoder().encode(SchemaListParams(type: type))
        )

        let response = try await XPCClient().execute(request)

        if response.ok == false {
            do {
                try Self.handleFailedResponse(response, globals: globals)
            } catch let exitCode as ExitCode {
                Darwin.exit(exitCode.rawValue)
            }
            return  // unreachable after Darwin.exit, but satisfies compiler
        }

        guard let data = response.data else {
            throw XPCError(
                code: "xpc.decode_failure",
                message: "Server returned ok=true but no data payload"
            )
        }

        let decoded: SchemaListResult
        do {
            decoded = try JSONDecoder().decode(SchemaListResult.self, from: data)
        } catch {
            throw XPCError(
                code: "xpc.decode_failure",
                message: "Failed to decode SchemaListResult: \(error.localizedDescription)"
            )
        }

        // Defensive client-side filter: if --type was passed and the server
        // returned more entries than requested (e.g. legacy app not yet aware
        // of the filter), trim down here so output matches the documented
        // surface either way.
        let result = SchemaListRendering.applyTypeFilter(decoded, type: type)

        if globals.isQuiet { return }

        try SchemaListCommand.render(
            result: result,
            format: format,
            outputMode: globals.outputMode,
            requestId: response.requestId
        )
    }

    /// Production response handler for schema.list. Valid remote errors emit
    /// the envelope with response.requestId on stderr and throw ExitCode(3).
    /// Malformed ok=false (nil error) throws xpc.decode_failure (exit 2 via
    /// central handler).
    static func handleFailedResponse(
        _ response: XPCResponse,
        globals: GlobalOptions
    ) throws {
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

    /// Render the result to stdout per the documented contract:
    /// - `--format json`: envelope via `JSONOutput`/`HumanOutput`.
    /// - `--format markdown` without global `--json`: raw Markdown to stdout.
    /// - `--format markdown` with global `--json`: envelope whose `data` is
    ///   `{ "markdown": "<body>" }` so the contract envelope is preserved.
    static func render(
        result: SchemaListResult,
        format: OutputFormat,
        outputMode: OutputMode,
        requestId: String
    ) throws {
        switch format {
        case .json:
            let envelopeData = SchemaListRendering.makeEnvelopeData(result)
            let formatter = outputMode.formatter()
            try formatter.emit(success: envelopeData, requestId: requestId)

        case .markdown:
            let body = SchemaListRendering.renderMarkdown(result)
            switch outputMode {
            case .json:
                // Preserve the contract envelope even when the user asks for
                // Markdown — Markdown body is carried as a string field.
                let envelope = MarkdownEnvelopeData(markdown: body)
                let formatter = outputMode.formatter()
                try formatter.emit(success: envelope, requestId: requestId)
            case .human:
                FileHandle.standardOutput.write(Data(body.utf8))
            }
        }
    }
}
