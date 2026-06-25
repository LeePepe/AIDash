import ArgumentParser
import Foundation
import AIDashCore

/// `aidash schema list` — fetch the full AIDash schema (enums + per-CardType
/// payload JSON Schemas) from the app via XPC.
///
/// See `specs/001-core-briefing-cli/contracts/cli-surface.md` §"schema list".
///
/// Subcommand flag (per issue MY-972):
///   --format <json|markdown>   default: json
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
///   - `--format markdown` → human-readable Markdown doc on stdout.
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

    @Option(name: .long, help: "Output format: json (default) or markdown.")
    var format: OutputFormat = .json

    func run() async throws {
        // Local-only validation. `--format` is already restricted to the enum
        // values by ArgumentParser; no further checks needed.

        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "schema.list",
            params: try JSONEncoder().encode(SchemaListParams())
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

        let result: SchemaListResult
        do {
            result = try JSONDecoder().decode(SchemaListResult.self, from: data)
        } catch {
            throw XPCError(
                code: "xpc.decode_failure",
                message: "Failed to decode SchemaListResult: \(error.localizedDescription)"
            )
        }

        if globals.isQuiet { return }

        switch format {
        case .json:
            // Inline the per-CardType payload schemas as JSON objects, not as
            // re-escaped strings — the wire-level `payloads: [String: String]`
            // representation is a transport-only detail.
            let envelopeData = SchemaListEnvelopeData(
                cliVersion: result.cliVersion,
                schemaVersion: result.schemaVersion,
                cardTypes: result.cardTypes,
                cardSizes: result.cardSizes,
                cardStyles: result.cardStyles,
                containerLayouts: result.containerLayouts,
                userEventActions: result.userEventActions,
                payloads: result.payloads.reduce(into: [:]) { acc, kv in
                    acc[kv.key] = AnyJSON.parse(kv.value) ?? .string(kv.value)
                }
            )
            let formatter = globals.outputMode.formatter(requestId: response.requestId)
            try formatter.emit(success: envelopeData)

        case .markdown:
            FileHandle.standardOutput.write(Data(SchemaListCommand.renderMarkdown(result).utf8))
        }
    }

    // MARK: - Markdown rendering

    /// Render the full schema document as Markdown. Deterministic — payload
    /// keys are sorted before emission.
    static func renderMarkdown(_ result: SchemaListResult) -> String {
        var out = ""
        out += "# AIDash Schema\n\n"
        out += "- CLI version: `\(result.cliVersion)`\n"
        out += "- Schema version: `\(result.schemaVersion)`\n\n"

        out += "## Enums\n\n"
        out += renderEnumSection("CardType", values: result.cardTypes)
        out += renderEnumSection("CardSize", values: result.cardSizes)
        out += renderEnumSection("CardStyle", values: result.cardStyles)
        out += renderEnumSection("ContainerLayout", values: result.containerLayouts)
        out += renderEnumSection("UserEventAction", values: result.userEventActions)

        out += "## Per-CardType payload schemas\n\n"
        for key in result.payloads.keys.sorted() {
            let body = result.payloads[key] ?? ""
            out += "### `\(key)`\n\n"
            out += "```json\n"
            out += prettyPrintJSON(body)
            out += "\n```\n\n"
        }
        return out
    }

    private static func renderEnumSection(_ name: String, values: [String]) -> String {
        var s = "### \(name)\n\n"
        for v in values { s += "- `\(v)`\n" }
        s += "\n"
        return s
    }

    /// Pretty-print a JSON string. Returns the input unchanged on parse
    /// failure — output rendering never throws.
    static func prettyPrintJSON(_ input: String) -> String {
        guard let data = input.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let str = String(data: pretty, encoding: .utf8)
        else {
            return input
        }
        return str
    }
}

// MARK: - Envelope shape

/// JSON-envelope-friendly mirror of `SchemaListResult` where per-CardType
/// payload schemas are inlined as JSON objects (not stringified bodies).
private struct SchemaListEnvelopeData: Encodable {
    let cliVersion: String
    let schemaVersion: String
    let cardTypes: [String]
    let cardSizes: [String]
    let cardStyles: [String]
    let containerLayouts: [String]
    let userEventActions: [String]
    let payloads: [String: AnyJSON]
}

// MARK: - AnyJSON helper

/// Minimal recursive JSON value used to inline pre-encoded JSON Schema bodies
/// into the response envelope without re-stringifying them.
private enum AnyJSON: Encodable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    static func parse(_ raw: String) -> AnyJSON? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed]
              )
        else { return nil }
        return from(any: obj)
    }

    private static func from(any value: Any) -> AnyJSON {
        if value is NSNull { return .null }
        if let n = value as? NSNumber {
            // NSNumber bridges both Bool and numeric — disambiguate by CFTypeID.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            let d = n.doubleValue
            if d.rounded() == d, abs(d) < 9_007_199_254_740_992 {
                return .integer(n.int64Value)
            }
            return .number(d)
        }
        if let b = value as? Bool { return .bool(b) }
        if let s = value as? String { return .string(s) }
        if let arr = value as? [Any] { return .array(arr.map { from(any: $0) }) }
        if let dict = value as? [String: Any] {
            var out: [String: AnyJSON] = [:]
            for (k, v) in dict { out[k] = from(any: v) }
            return .object(out)
        }
        return .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let b):    try c.encode(b)
        case .integer(let i): try c.encode(i)
        case .number(let d):  try c.encode(d)
        case .string(let s):  try c.encode(s)
        case .array(let arr): try c.encode(arr)
        case .object(let o):  try c.encode(o)
        }
    }
}
