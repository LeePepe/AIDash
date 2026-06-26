import Foundation
import AIDashCore

/// Resolves the `--payload` flag value into raw JSON bytes.
///
/// Per `specs/001-core-briefing-cli/research.md` §R-2 (@file payload support):
///   - If `value` starts with `@`, strips the `@` and reads the remaining
///     path from disk; file contents are used as the payload bytes verbatim.
///   - Otherwise, treats `value` as inline JSON and uses its UTF-8 bytes.
///
/// Read errors are surfaced as `schema.payload_file_unreadable` so they map
/// to exit 1 (local validation failure) via `ExitCodeMapper`.
///
/// Factored out of `CardPutCommand` so the unit-test target (which does not
/// depend on `ArgumentParser`) can exercise the path-handling logic.
public enum PayloadResolver {
    public static func resolve(_ value: String) throws -> Data {
        guard value.hasPrefix("@") else {
            return Data(value.utf8)
        }

        let path = String(value.dropFirst())
        guard !path.isEmpty else {
            throw XPCError(
                code: "schema.payload_file_unreadable",
                message: "Empty file path after '@' in --payload",
                field: "payload",
                got: value
            )
        }

        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw XPCError(
                code: "schema.payload_file_unreadable",
                message: "Failed to read payload file at '\(path)': \(error.localizedDescription)",
                field: "payload",
                got: value,
                cause: error.localizedDescription
            )
        }
    }
}
