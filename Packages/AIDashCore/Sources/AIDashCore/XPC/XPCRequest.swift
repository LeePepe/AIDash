import Foundation

/// JSON-RPC request envelope for the AIDash XPC protocol.
/// See `contracts/xpc-protocol.md` §"Request envelope".
public struct XPCRequest: Codable, Sendable {
    /// UUID string for log correlation.
    public let requestId: String
    /// CLI's version string (e.g. "1.0.0").
    public let cliVersion: String
    /// Dotted command name (e.g. "card.put", "events.pull").
    public let command: String
    /// Command-specific Codable payload, already JSON-encoded.
    public let params: Data

    public init(
        requestId: String,
        cliVersion: String,
        command: String,
        params: Data
    ) {
        self.requestId = requestId
        self.cliVersion = cliVersion
        self.command = command
        self.params = params
    }
}
