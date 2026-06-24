/// Marker protocol for all card payload types.
public protocol CardPayloadProtocol: Codable, Sendable {
    /// Validates type-specific invariants after successful JSON decode.
    /// Throws `XPCError` with `code: "schema.payload_decode_failed"` on failure.
    func validateInvariants() throws
}

extension CardPayloadProtocol {
    /// Default: no invariants to check.
    public func validateInvariants() throws {}
}
