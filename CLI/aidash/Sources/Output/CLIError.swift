import AIDashCore
import Foundation

/// Central error handler: writes the error envelope to stderr and terminates.
enum CLIError {

    /// Write error envelope to stderr and exit with the given code.
    /// This function never returns.
    static func exit(
        _ error: XPCError,
        requestId: String,
        code: ExitCode
    ) -> Never {
        JSONOutput.writeError(error, requestId: requestId)
        Darwin.exit(code.rawValue)
    }
}
