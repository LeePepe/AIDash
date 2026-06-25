import Foundation
import AIDashCore

/// Machine-readable JSON output: success to stdout, errors to stderr.
public struct JSONOutput: OutputFormatter {
    public init() {}

    public func emit(success: any Encodable) throws {
        let data = try Self.encoder.encode(AnyEncodable(success))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    public func emit(error: XPCError) throws {
        let envelope = CLIErrorEnvelope(from: error)
        let data = try Self.encoder.encode(envelope)
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

// MARK: - CLI Error Envelope (per cli-surface.md §"Error envelope")

/// Public error fields exposed on the CLI surface. Excludes internal
/// transport details such as `cause` from `XPCError`.
struct CLIErrorBody: Encodable {
    let allowed: [String]?
    let code: String
    let field: String?
    let got: String?
    let message: String
    let requestId: String?
}

/// `{ "ok": false, "error": { ... } }` wrapper required by cli-surface.md.
struct CLIErrorEnvelope: Encodable {
    let ok = false
    let error: CLIErrorBody

    init(from xpcError: XPCError, requestId: String? = nil) {
        self.error = CLIErrorBody(
            allowed: xpcError.allowed,
            code: xpcError.code,
            field: xpcError.field,
            got: xpcError.got,
            message: xpcError.message,
            requestId: requestId
        )
    }
}
