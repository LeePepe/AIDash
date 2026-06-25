import Foundation

/// Tracks in-flight XPC requests by their `requestId` so that asynchronous
/// callbacks (reply, error handler, invalidation, interruption) can resume the
/// correct continuation without overwriting unrelated in-flight requests.
///
/// Lifecycle contract:
/// - `register(requestId:continuation:)` stores a continuation under its id.
///   Calling `register` twice with the same id is a programmer error (would
///   indicate request id collision); the existing continuation is replaced and
///   the prior one is resumed with a `xpc.request_id_collision` error so it
///   does not leak.
/// - `complete(requestId:_:)` atomically removes the continuation for `id` and
///   invokes the closure. If the id is unknown (already completed by a racing
///   callback) the closure is not invoked — guarantees single-resume.
/// - `failAll(code:message:)` removes every pending continuation and resumes
///   each with the given `XPCError`. Used when the underlying connection is
///   invalidated or interrupted — every in-flight request must be told the
///   transport is gone.
/// - `pendingCount` exposes the current in-flight count for tests and
///   diagnostics.
public actor XPCPendingRequests {
    private var pending: [String: CheckedContinuation<XPCResponse, any Error>] = [:]

    public init() {}

    public var pendingCount: Int { pending.count }

    /// Register a continuation under `requestId`. If `requestId` already has a
    /// pending continuation the prior one is resumed with
    /// `xpc.request_id_collision` so it does not leak.
    public func register(
        requestId: String,
        continuation: CheckedContinuation<XPCResponse, any Error>
    ) {
        if let prior = pending.removeValue(forKey: requestId) {
            prior.resume(throwing: XPCError(
                code: "xpc.request_id_collision",
                message: "another request registered the same requestId"
            ))
        }
        pending[requestId] = continuation
    }

    /// Atomically take the continuation for `requestId` (if any) and pass it
    /// to `body`. Returns `true` if the continuation existed, `false` if
    /// already consumed (e.g. by a racing invalidation callback).
    @discardableResult
    public func complete(
        requestId: String,
        _ body: (CheckedContinuation<XPCResponse, any Error>) -> Void
    ) -> Bool {
        guard let cont = pending.removeValue(forKey: requestId) else {
            return false
        }
        body(cont)
        return true
    }

    /// Resume every pending continuation with `XPCError(code:message:)` and
    /// clear the table. Used when the underlying connection dies and every
    /// in-flight request must be aborted.
    public func failAll(code: String, message: String) {
        let snapshot = pending
        pending.removeAll()
        for (_, cont) in snapshot {
            cont.resume(throwing: XPCError(code: code, message: message))
        }
    }
}
