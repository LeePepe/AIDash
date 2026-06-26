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
/// Exit codes are mapped centrally by `AIDash.main` via `ExitCodeMapper`:
///   0 — success
///   1 — local validation (`schema.*`)
///   2 — XPC transport (`xpc.*`)
///   3 — remote error (everything else)
///
/// Output:
///   - `--format json` → success envelope on stdout via `JSONOutput`/`HumanOutput`.
///   - `--format markdown` → human-readable Markdown doc on stdout when global
///     `--json` is NOT set. When `--json` IS set, the Markdown body is wrapped
///     in the standard success envelope as a string (`data.markdown`) so that
///     `aidash --json schema list --format markdown` still emits the contract
///     envelope (per Constitution §B.1).
///   - Errors are always JSON envelopes on stderr (per cli-surface contract);
///     this command throws `XPCError` so `AIDash.main`'s central handler emits
///     and exits with the correct code.
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
            throw response.error ?? XPCError(
                code: "xpc.decode_failure",
                message: "Server returned ok=false but no error payload"
            )
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
