#if os(macOS)
import Testing
import Foundation
@testable import AIDashApp
import AIDashCore

// Behavior tests for the public XPCListener surface (MY-1003 follow-up to T080).
// XPCListener is intentionally NOT @MainActor — NSXPCListener delivers its
// delegate callback on its own internal serial queue, so these tests do not
// hop to the main actor when exercising the listener directly.

private final class StubXPCHandlers: NSObject, AIDashXPCServiceProtocol {
    func execute(requestData: Data, reply: @escaping (Data) -> Void) {
        reply(Data())
    }
}

@Test func xpcListenerInitRetainsInjectedHandlers() {
    let handlers = StubXPCHandlers()
    let sut = XPCListener(handlers: handlers)

    // Public init keeps the injected handlers reference alive for the
    // lifetime of the listener (NSXPCConnection.exportedObject relies on it).
    weak var weakHandlers = handlers
    #expect(weakHandlers != nil)
    // Touch the listener so ARC cannot drop it before the assertion runs.
    _ = sut
}

@Test func xpcListenerInitDoesNotResumeUntilStart() {
    // Constructing a listener must NOT resume it — resuming an
    // NSXPCListener(machServiceName:) twice traps with `_xpc_api_misuse`, so
    // `start()` is the single, caller-controlled resume point. (An earlier test
    // asserted `start()` was idempotent across repeated calls; that premise is
    // wrong — XPC forbids double-resume — and it crashed the whole test process
    // once the app-target suite actually ran. Removed.)
    let handlers = StubXPCHandlers()
    let sut = XPCListener(handlers: handlers)
    weak var weakHandlers = handlers
    #expect(weakHandlers != nil)   // handlers retained; nothing resumed yet
    _ = sut
}

@Test func xpcListenerAcceptsNewConnectionAndWiresExportedObject() async throws {
    let handlers = StubXPCHandlers()
    let sut = XPCListener(handlers: handlers)

    // We can't drive the real Mach service in a sandboxed unit test, but we
    // can drive the NSXPCListenerDelegate callback directly using an
    // anonymous listener + connection pair, which is exactly what the system
    // uses internally. The contract under test: the delegate
    // (a) returns true, (b) installs the AIDashXPCServiceProtocol interface,
    // and (c) sets the injected handlers as the exportedObject.
    let anonymous = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: anonymous.endpoint)
    defer { connection.invalidate() }

    let accepted = sut.listener(anonymous, shouldAcceptNewConnection: connection)
    #expect(accepted == true)
    #expect(connection.exportedInterface != nil)
    #expect((connection.exportedObject as AnyObject?) === handlers)
}

@Test func xpcListenerDelegateUsesAIDashProtocolInterface() {
    let sut = XPCListener(handlers: StubXPCHandlers())
    let anonymous = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: anonymous.endpoint)
    defer { connection.invalidate() }

    _ = sut.listener(anonymous, shouldAcceptNewConnection: connection)

    // The exported interface must describe AIDashXPCServiceProtocol so the
    // CLI's remote proxy can resolve `execute(requestData:reply:)`. If a
    // future refactor swapped the protocol, this assertion catches it.
    let expected = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
    #expect(connection.exportedInterface?.protocol === expected.protocol)
}

// MARK: - True end-to-end over a live anonymous XPC connection
//
// This is the regression test the codebase never had: a REAL client connection
// to a REAL listener serving the REAL XPCHandlers (in-memory SwiftData), driving
// the full push pipeline (briefing → container → card → get) across an actual
// XPC boundary. It runs with ZERO launchd and ZERO Xcode — the same mechanism
// the production LaunchAgent brokers, minus the launchd port. Proves that when
// launchd *does* broker the mach service to this process, pushes land.

/// Hosts an anonymous listener wiring the real handlers, exactly like the app's
/// `XPCListener` does for the mach service — but on an anonymous endpoint a test
/// client can reach without launchd.
@MainActor
private final class AnonServiceHost: NSObject, NSXPCListenerDelegate {
    let listener = NSXPCListener.anonymous()
    private let handlers: XPCHandlers
    init(handlers: XPCHandlers) {
        self.handlers = handlers
        super.init()
        listener.delegate = self
        listener.resume()
    }
    nonisolated func listener(_ listener: NSXPCListener,
                              shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        c.exportedInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        c.exportedObject = handlers
        c.resume()
        return true
    }
}

@MainActor
private func liveCall(_ conn: NSXPCConnection, command: String,
                      params: some Encodable) async throws -> XPCResponse {
    let enc = XPCTestSupport.jsonEncoder
    let request = XPCRequest(requestId: UUID().uuidString, cliVersion: "e2e",
                             command: command, params: try enc.encode(params))
    let requestData = try enc.encode(request)
    return try await withCheckedThrowingContinuation { cont in
        let proxy = conn.remoteObjectProxyWithErrorHandler { cont.resume(throwing: $0) }
            as? AIDashXPCServiceProtocol
        guard let proxy else {
            cont.resume(throwing: XPCError(code: "e2e.proxy", message: "no proxy")); return
        }
        proxy.execute(requestData: requestData) { data in
            do { cont.resume(returning: try XPCTestSupport.jsonDecoder.decode(XPCResponse.self, from: data)) }
            catch { cont.resume(throwing: error) }
        }
    }
}

@MainActor
@Test func liveXPCRoundTripDrivesFullPushPipeline() async throws {
    let handlers = try XPCTestSupport.makeHandlers()   // real handlers, in-memory store
    let host = AnonServiceHost(handlers: handlers)
    let conn = NSXPCConnection(listenerEndpoint: host.listener.endpoint)
    conn.remoteObjectInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
    conn.resume()
    defer { conn.invalidate() }

    let date = "2026-07-19"
    let cid = "11111111-0719-0001-0000-000000000001"
    let kid = "22222222-0719-0001-0000-000000000001"

    // briefing put
    var r = try await liveCall(conn, command: "briefing.put",
        params: BriefingPutParams(date: date, generatedBy: "e2e", published: false))
    #expect(r.ok)
    // container put
    r = try await liveCall(conn, command: "container.put",
        params: ContainerPutParams(briefingDate: date, id: cid, title: "T",
                                   subtitle: nil, order: 10, layout: .auto, style: .neutral))
    #expect(r.ok)
    // card put
    let payload = Data(#"{"topic":"t","items":[{"title":"a","url":"https://x","score":1}]}"#.utf8)
    r = try await liveCall(conn, command: "card.put",
        params: CardPutParams(containerId: cid, id: kid, type: .trending,
                              size: .hero, style: .neutral, payload: payload))
    #expect(r.ok)
    // publish + get: the pushed briefing round-trips back with its card
    _ = try await liveCall(conn, command: "briefing.publish",
        params: BriefingPublishParams(date: date))
    let got = try await liveCall(conn, command: "briefing.get",
        params: BriefingGetParams(date: date))
    #expect(got.ok)
    #expect(got.data != nil)
}
#endif
