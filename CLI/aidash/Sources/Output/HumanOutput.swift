import AIDashCore
import Foundation

/// Emits human-readable output for interactive use.
enum HumanOutput {

    /// Write a success message to stdout.
    static func writeSuccess(_ message: String) {
        print(message)
    }

    /// Write an error to stderr (still JSON per contract — errors always JSON).
    static func writeError(_ error: XPCError, requestId: String) {
        JSONOutput.writeError(error, requestId: requestId)
    }
}
