import Foundation
import AIDashCore

/// Pure rendering and envelope-shaping helpers for `aidash schema list`.
///
/// Kept separate from `SchemaListCommand` so the helpers can be exercised
/// by the test target without dragging in `ArgumentParser` or the
/// `@OptionGroup` plumbing. The command struct delegates here.
enum SchemaListRendering {

    // MARK: - Filtering

    /// Returns a copy of `result` with `payloads` trimmed to `type` (if
    /// non-nil and present); enum fields are returned unchanged.
    static func applyTypeFilter(
        _ result: SchemaListResult,
        type: String?
    ) -> SchemaListResult {
        guard let type, !type.isEmpty else { return result }
        let trimmed = result.payloads.filter { $0.key == type }
        return SchemaListResult(
            cliVersion: result.cliVersion,
            schemaVersion: result.schemaVersion,
            cardTypes: result.cardTypes,
            cardSizes: result.cardSizes,
            cardStyles: result.cardStyles,
            containerLayouts: result.containerLayouts,
            userEventActions: result.userEventActions,
            payloads: trimmed
        )
    }

    // MARK: - Envelope shaping

    /// Build the success-envelope `data` payload — inlines stringified
    /// per-CardType JSON schemas as real JSON objects so the consumer sees
    /// structured content instead of escaped strings.
    static func makeEnvelopeData(_ result: SchemaListResult) -> SchemaListEnvelopeData {
        SchemaListEnvelopeData(
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
    }

    // MARK: - Markdown

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

// MARK: - Envelope shapes

/// JSON-envelope-friendly mirror of `SchemaListResult` where per-CardType
/// payload schemas are inlined as JSON objects (not stringified bodies).
struct SchemaListEnvelopeData: Encodable {
    let cliVersion: String
    let schemaVersion: String
    let cardTypes: [String]
    let cardSizes: [String]
    let cardStyles: [String]
    let containerLayouts: [String]
    let userEventActions: [String]
    let payloads: [String: AnyJSON]
}

/// Envelope shape used when `--format markdown` is combined with the global
/// `--json` flag — the Markdown body is carried as a single string so the
/// CLI surface contract envelope is preserved.
struct MarkdownEnvelopeData: Encodable {
    let markdown: String
}

// MARK: - AnyJSON helper

/// Minimal recursive JSON value used to inline pre-encoded JSON Schema bodies
/// into the response envelope without re-stringifying them.
enum AnyJSON: Encodable, Equatable {
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
