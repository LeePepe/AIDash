import Foundation

/// JSON-RPC response envelope for the AIDash XPC protocol.
/// See `contracts/xpc-protocol.md` §"Response envelope".
public struct XPCResponse: Codable, Sendable {
    /// Mirrors the request's `requestId`.
    public let requestId: String
    /// App's version string.
    public let appVersion: String
    /// `true` on success, `false` on error.
    public let ok: Bool
    /// Command-specific Result payload, JSON-encoded. `nil` on error.
    public let data: Data?
    /// Error details. `nil` on success.
    public let error: XPCError?

    public init(
        requestId: String,
        appVersion: String,
        ok: Bool,
        data: Data?,
        error: XPCError?
    ) {
        self.requestId = requestId
        self.appVersion = appVersion
        self.ok = ok
        self.data = data
        self.error = error
    }
}
