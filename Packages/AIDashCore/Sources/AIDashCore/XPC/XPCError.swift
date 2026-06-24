/// Structured error returned inside an `XPCResponse`.
/// See `contracts/xpc-protocol.md` §"Error code taxonomy".
///
/// Conforms to `Error` so it can be thrown directly.
public struct XPCError: Codable, Sendable, Error {
    /// Dotted error code (e.g. "schema.unknown_card_type").
    public let code: String
    /// Human-readable description.
    public let message: String
    /// For schema errors: which field caused the error.
    public let field: String?
    /// For schema errors: the actual value received.
    public let got: String?
    /// For schema errors: list of valid values.
    public let allowed: [String]?
    /// Optional underlying error description.
    public let cause: String?

    public init(
        code: String,
        message: String,
        field: String? = nil,
        got: String? = nil,
        allowed: [String]? = nil,
        cause: String? = nil
    ) {
        self.code = code
        self.message = message
        self.field = field
        self.got = got
        self.allowed = allowed
        self.cause = cause
    }
}
