import Foundation
import AIDashCore

/// Human-readable output: pretty-printed JSON to stdout for success,
/// JSON error to stderr (per cli-surface contract: errors are always JSON).
///
/// Success output is pretty-printed and unwrapped (no `ok`/`data`/`requestId`
/// envelope) so it's pleasant to read in a terminal. The structured
/// envelope is reserved for `--json` mode (see `JSONOutput`).
public struct HumanOutput: OutputFormatter {
    public init() {}

    /// Human-mode success: pretty-prints the payload to stdout. The
    /// `requestId` is intentionally ignored — it only appears in the
    /// `--json` success envelope (per cli-surface.md).
    ///
    /// - Throws: `EncodingError` if the payload cannot be JSON-encoded.
    public func emit(success: any Encodable, requestId _: String) throws {
        // Human mode: ignore requestId, render the payload pretty.
        let json = try JSONEncoder().encode(AnyEncodable(success))
        if let obj = try? JSONSerialization.jsonObject(with: json),
           let pretty = try? JSONSerialization.data(
               withJSONObject: obj,
               options: [.prettyPrinted, .sortedKeys]
           ) {
            FileHandle.standardOutput.write(pretty)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    /// Delegates to `JSONOutput.emit(error:requestId:)` because the
    /// cli-surface contract requires errors to be JSON-enveloped on stderr
    /// in every mode, including human mode.
    ///
    /// - Throws: `EncodingError` propagated from `JSONOutput`.
    public func emit(error: XPCError, requestId: String?) throws {
        // Errors ALWAYS JSON-enveloped on stderr — per cli-surface contract.
        try JSONOutput().emit(error: error, requestId: requestId)
    }
}
