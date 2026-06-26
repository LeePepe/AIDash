import Foundation

/// Central URL validation for agent-authored content (card refs, link
/// targets). View code MUST route every agent-authored URL string through
/// `URLPolicy.validate(_:)` rather than constructing `URL(string:)` directly.
///
/// Policy (per constitution §C URL & Link Policy):
/// - Allowed scheme: `https` only.
/// - URL must have a non-empty host.
/// - `http`, `about:`, `javascript:`, `file:`, custom schemes → rejected
///   and the caller renders the value as plain text.
public enum URLPolicy {

    /// Schemes accepted by `validate(_:)`. The constitution pins this to
    /// `https` only; widening requires a constitutional amendment.
    public static let allowedSchemes: Set<String> = ["https"]

    /// Validates an agent-authored URL string and returns the parsed `URL`
    /// when the value is safe to use as a link destination.
    ///
    /// - Returns: A `URL` whose scheme is in `allowedSchemes` and whose host
    ///   is non-empty; otherwise `nil`.
    public static func validate(_ ref: String?) -> URL? {
        guard let ref, !ref.isEmpty else { return nil }
        guard let url = URL(string: ref) else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
