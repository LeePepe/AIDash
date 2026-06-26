import Foundation
import AIDashCore

/// Machine-readable JSON output: success to stdout, errors to stderr.
/// Emits the documented envelope format per cli-surface.md.
public struct JSONOutput: OutputFormatter {
    private let requestId: String?

    public init(requestId: String? = nil) {
        self.requestId = requestId
    }

    public func emit(success: any Encodable) throws {
        let envelope = CLISuccessEnvelope(data: AnyEncodable(success), requestId: requestId)
        let data = try Self.encoder.encode(envelope)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    public func emit(error: XPCError) throws {
        let envelope = CLIErrorEnvelope(from: error, requestId: requestId)
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

// MARK: - CLI Success Envelope (per cli-surface.md §"Success envelope")

struct CLISuccessEnvelope: Encodable {
    let ok = true
    let data: AnyEncodable
    let requestId: String?
}

// MARK: - CLI Error Envelope (per cli-surface.md §"Error envelope")

struct CLIErrorBody: Encodable {
    let allowed: [String]?
    let code: String
    let field: String?
    let got: String?
    let message: String
    let requestId: String?
}

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
