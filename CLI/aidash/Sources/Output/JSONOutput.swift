import Foundation
import AIDashCore

/// Emits structured JSON to stdout/stderr per `contracts/cli-surface.md`.
///
/// Errors are always emitted as JSON to stderr, regardless of `--json` flag.
public struct JSONOutput: Sendable {
    public init() {}

    /// Emit an error envelope to stderr.
    public func emit(error: XPCError, requestId: String? = nil) throws {
        let envelope = ErrorEnvelope(
            ok: false,
            error: ErrorDetail(
                code: error.code,
                message: error.message,
                field: error.field,
                got: error.got,
                allowed: error.allowed,
                requestId: requestId ?? UUID().uuidString
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
    }
}

// MARK: - Private envelope types

private struct ErrorEnvelope: Encodable {
    let ok: Bool
    let error: ErrorDetail
}

private struct ErrorDetail: Encodable {
    let code: String
    let message: String
    let field: String?
    let got: String?
    let allowed: [String]?
    let requestId: String
}
