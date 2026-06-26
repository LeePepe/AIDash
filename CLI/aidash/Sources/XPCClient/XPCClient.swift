import Foundation
import AIDashCore

/// Async-Swift wrapper around `NSXPCConnection` to the AIDash app's XPC service.
/// Thread-safe by design: `actor` isolation ensures no data races on mutable state.
///
/// Lifecycle guarantees:
/// - Each `execute` call registers a per-request continuation in
///   `XPCPendingRequests` keyed by `XPCRequest.requestId`. Overlapping calls
///   never overwrite each other (T041).
/// - Transport, proxy, decode, invalidation, and interruption failures all
///   resume the affected continuation(s) with a typed `XPCError`.
/// - Any connection-level failure (transport / proxy / invalidation /
///   interruption / decode) clears the cached connection so the next call
///   recreates it.
/// - Single-resume semantics: `XPCPendingRequests.complete` atomically takes
///   the continuation, preventing double-resume if multiple callbacks race.
/// - A 5-second timeout ensures the CLI never hangs indefinitely (T051).
/// - On transport failure, launches AIDash.app via `AppLauncher` and retries
///   once with a protocol-valid readiness round trip (T051).
public actor XPCClient {
    private var connection: NSXPCConnection?
    private let pending = XPCPendingRequests()
    private var hasRetriedWithLaunch = false

    /// Timeout for XPC calls (per contract: 5s budget).
    private static let timeoutDuration: Duration = .seconds(5)

    /// Per-probe timeout used during launch-and-poll retry. Shorter than the
    /// regular call budget so a wedged service does not block the AppLauncher
    /// loop (10 attempts × 500 ms poll cadence).
    private static let probeTimeout: Duration = .milliseconds(400)

    private let appLauncher: AppLauncher

    public init(appLauncher: AppLauncher = AppLauncher()) {
        self.appLauncher = appLauncher
    }

    /// Send an XPC request and await the response.
    /// Throws `XPCError` on transport failure, timeout, or remote error.
    /// If the app is not running, attempts to launch it via `AppLauncher` and retries once.
    public func execute(_ request: XPCRequest) async throws -> XPCResponse {
        do {
            return try await executeWithTimeout(request)
        } catch let error as XPCError where error.code == "xpc.transport_failure" && !hasRetriedWithLaunch {
            // App may not be running — launch it and retry once.
            hasRetriedWithLaunch = true
            try await appLauncher.launchAndWait { [weak self] in
                await self?.probeRoundTrip() ?? false
            }
            return try await executeWithTimeout(request)
        }
    }

    // MARK: - Internal

    /// Race the XPC call against a timeout.
    private func executeWithTimeout(_ request: XPCRequest) async throws -> XPCResponse {
        try await withThrowingTaskGroup(of: XPCResponse.self) { group in
            group.addTask {
                try await self.executeXPC(request)
            }
            group.addTask {
                try await Task.sleep(for: Self.timeoutDuration)
                throw XPCError(
                    code: "xpc.timeout",
                    message: "XPC request timed out after 5 seconds"
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Readiness probe: performs a real protocol-valid XPC round trip using
    /// the `schema.list` command. The service is considered ready when ANY
    /// `XPCResponse` is received (even an error response) — the success of
    /// the transport layer is what we're checking, not the response payload.
    ///
    /// Uses a short per-probe timeout so a wedged service does not block the
    /// `AppLauncher` polling loop. Returns `false` on any transport failure,
    /// timeout, or decode failure; returns `true` only when the app actually
    /// answered the round trip.
    private func probeRoundTrip() async -> Bool {
        connection = nil
        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "schema.list",
            params: Data()
        )
        do {
            _ = try await withThrowingTaskGroup(of: XPCResponse.self) { group in
                group.addTask {
                    try await self.executeXPC(request)
                }
                group.addTask {
                    try await Task.sleep(for: Self.probeTimeout)
                    throw XPCError(
                        code: "xpc.timeout",
                        message: "probe timed out"
                    )
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            return true
        } catch {
            connection = nil
            return false
        }
    }

    /// Submit a single request through the per-request pending table (T041).
    /// Returns the decoded `XPCResponse`; transport/proxy/decode failures
    /// resume only this request's continuation.
    private func executeXPC(_ request: XPCRequest) async throws -> XPCResponse {
        let conn = ensureConnection()
        let requestData = try JSONEncoder().encode(request)
        let requestId = request.requestId

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await pending.register(requestId: requestId, continuation: continuation)

                let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] err in
                    Task { await self?.failRequest(
                        requestId: requestId,
                        code: "xpc.transport_failure",
                        message: err.localizedDescription
                    )}
                } as? any AIDashXPCServiceProtocol

                guard let proxy else {
                    await failRequest(
                        requestId: requestId,
                        code: "xpc.proxy_unavailable",
                        message: "remote object proxy missing"
                    )
                    return
                }

                proxy.execute(requestData: requestData) { [weak self] responseData in
                    Task { await self?.handleReply(requestId: requestId, data: responseData) }
                }
            }
        }
    }

    // MARK: - Continuation management

    /// Fail one specific request and clear the cached connection so the next
    /// call recreates it. Used for transport failure, proxy unavailable, and
    /// decode failure paths that affect only the calling request.
    private func failRequest(requestId: String, code: String, message: String) async {
        connection = nil
        await pending.complete(requestId: requestId) { cont in
            cont.resume(throwing: XPCError(code: code, message: message))
        }
    }

    /// Fail every in-flight request (connection died). Used for invalidation
    /// and interruption — both kill the entire connection, not a single call.
    private func failAll(code: String, message: String) async {
        connection = nil
        await pending.failAll(code: code, message: message)
    }

    /// Decode the reply and resume the matching pending continuation.
    private func handleReply(requestId: String, data: Data) async {
        let decoded: Result<XPCResponse, any Error>
        do {
            decoded = .success(try JSONDecoder().decode(XPCResponse.self, from: data))
        } catch {
            decoded = .failure(XPCError(
                code: "xpc.decode_failure",
                message: error.localizedDescription
            ))
        }

        switch decoded {
        case .success(let response):
            await pending.complete(requestId: requestId) { cont in
                cont.resume(returning: response)
            }
        case .failure(let error):
            connection = nil
            await pending.complete(requestId: requestId) { cont in
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Connection lifecycle

    private func ensureConnection() -> NSXPCConnection {
        if let c = connection { return c }
        let c = NSXPCConnection(
            machServiceName: XPCServiceConfiguration.machServiceName,
            options: []
        )
        c.remoteObjectInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        c.invalidationHandler = { [weak self] in
            Task { await self?.failAll(
                code: "xpc.connection_invalidated",
                message: "XPC connection was invalidated"
            )}
        }
        c.interruptionHandler = { [weak self] in
            Task { await self?.failAll(
                code: "xpc.connection_interrupted",
                message: "XPC connection was interrupted"
            )}
        }
        c.resume()
        connection = c
        return c
    }
}
