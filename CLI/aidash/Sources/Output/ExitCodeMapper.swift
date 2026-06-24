import AIDashCore
import Foundation

/// Maps XPC errors to CLI exit codes per `contracts/cli-surface.md`.
enum ExitCode: Int32 {
    case success = 0
    case localValidation = 1
    case xpcTransport = 2
    case remoteError = 3
}

/// Determines the correct exit code for a given XPCError.
enum ExitCodeMapper {

    static func exitCode(for error: XPCError) -> ExitCode {
        let code = error.code
        if code.hasPrefix("schema.") {
            return .localValidation
        }
        if code.hasPrefix("xpc.") {
            return .xpcTransport
        }
        // All other error categories: remote errors
        return .remoteError
    }
}
