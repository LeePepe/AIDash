import Foundation
import AIDashCore

/// Routes command output to either machine-readable JSON or pretty-printed
/// human form, per the contract in
/// `specs/001-core-briefing-cli/contracts/cli-surface.md`.
///
/// Conforming types MUST:
/// - Write success payloads to **stdout**.
/// - Write errors to **stderr** as JSON, regardless of mode
///   (per cli-surface §"Error envelope" and constitution §B.2).
/// - Wrap `--json` success output in
///   `{ "ok": true, "data": ..., "requestId": ... }`
///   (per cli-surface §"Success envelope" and constitution §B.1).
public protocol OutputFormatter: Sendable {
    /// Emit a successful command result.
    ///
    /// - Parameters:
    ///   - success: The command-specific payload to render. For `--json`
    ///     mode this becomes the `data` field of the success envelope.
    ///   - requestId: Correlation id propagated to the success envelope.
    ///     Constitution §B.1 makes this non-optional: every `--json` success
    ///     envelope must carry a `requestId` so callers (agents, log
    ///     scrapers) can correlate against backend logs. Use the id
    ///     returned by the XPC response, or a freshly generated UUID for
    ///     commands that do not round-trip through XPC.
    /// - Throws: Any `Swift.Error` raised by the underlying `JSONEncoder`
    ///   while encoding `success` (typically `EncodingError.invalidValue`
    ///   when the payload contains a non-encodable value). Errors are not
    ///   written to stdout when thrown; the caller is responsible for
    ///   routing the failure through `emit(error:requestId:)` on stderr.
    func emit(success: any Encodable, requestId: String) throws

    /// Emit an error to stderr as the JSON envelope required by
    /// `cli-surface.md` §"Error envelope":
    /// `{ "ok": false, "error": { code, message, field?, got?, allowed?, requestId? } }`.
    ///
    /// - Parameters:
    ///   - error: The transport/domain error. The CLI surface intentionally
    ///     exposes only the public fields of `XPCError` (`code`, `message`,
    ///     `field`, `got`, `allowed`). Internal fields such as `cause`
    ///     MUST NOT leak to stderr.
    ///   - requestId: Optional correlation id nested inside the `error`
    ///     object. `nil` when the error occurs before a request id is
    ///     assigned (e.g. argument-parsing failures); the key is omitted
    ///     from the envelope in that case.
    /// - Throws: Any `Swift.Error` raised by the underlying `JSONEncoder`
    ///   while serialising the error envelope. The original `XPCError`
    ///   itself is not rethrown — it is rendered to stderr.
    func emit(error: XPCError, requestId: String?) throws
}

public enum OutputMode: Sendable {
    case human
    case json

    /// Returns a stateless formatter for this mode. `requestId` is supplied
    /// per call via `emit(success:requestId:)` / `emit(error:requestId:)`
    /// so the type system enforces the constitution §B.1 success-envelope
    /// contract at the call site rather than at construction time.
    public func formatter() -> any OutputFormatter {
        switch self {
        case .human: return HumanOutput()
        case .json:  return JSONOutput()
        }
    }
}
