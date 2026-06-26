import Foundation
import AIDashCore

/// Machine-readable JSON output: success to stdout, errors to stderr.
///
/// Both success and error are wrapped in the envelopes documented in
/// `specs/001-core-briefing-cli/contracts/cli-surface.md`:
///
/// - Success (`--json`):  `{ "ok": true,  "data": ..., "requestId": ... }`
/// - Error  (any mode):  `{ "ok": false, "error": { ..., "requestId": ... } }`
///   (per cli-surface.md, error `requestId` lives INSIDE the `error` object)
public struct JSONOutput: OutputFormatter {
    public init() {}

    /// Writes the success envelope to stdout. `requestId` is always emitted
    /// per constitution §B.1.
    ///
    /// - Throws: `EncodingError` if the payload contains a value the
    ///   `JSONEncoder` cannot serialise.
    public func emit(success: any Encodable, requestId: String) throws {
        let envelope = CLISuccessEnvelope(data: success, requestId: requestId)
        let data = try Self.encoder.encode(envelope)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    /// Writes the error envelope to stderr. `requestId`, when supplied,
    /// is nested inside the `error` object per cli-surface §"Error envelope".
    /// Internal `XPCError.cause` is never serialised.
    ///
    /// - Throws: `EncodingError` if envelope encoding fails (the input
    ///   `XPCError` is composed of `Codable` primitives, so this is not
    ///   expected in practice).
    public func emit(error: XPCError, requestId: String?) throws {
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

/// `{ "ok": true, "data": ..., "requestId": ... }` wrapper required by
/// cli-surface.md. `requestId` is required (constitution §B.1) so the
/// envelope cannot drift back to an unenveloped raw payload.
struct CLISuccessEnvelope: Encodable {
    let ok = true
    let data: any Encodable
    let requestId: String

    enum CodingKeys: String, CodingKey {
        case ok
        case data
        case requestId
    }

    init(data: any Encodable, requestId: String) {
        self.data = data
        self.requestId = requestId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ok, forKey: .ok)
        try container.encode(AnyEncodable(data), forKey: .data)
        try container.encode(requestId, forKey: .requestId)
    }
}

// MARK: - CLI Error Envelope (per cli-surface.md §"Error envelope")

/// Public error fields exposed on the CLI surface. Excludes internal
/// transport details such as `cause` from `XPCError`.
///
/// Per `cli-surface.md`, `requestId` is nested INSIDE the `error` object,
/// not as a sibling at the envelope root.
struct CLIErrorBody: Encodable {
    let allowed: [String]?
    let code: String
    let field: String?
    let got: String?
    let message: String
    let requestId: String?
}

/// `{ "ok": false, "error": { ..., "requestId": ... } }` wrapper required
/// by cli-surface.md.
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
