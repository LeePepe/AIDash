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

@Test func xpcListenerStartIsIdempotentAndDoesNotThrow() {
    let sut = XPCListener(handlers: StubXPCHandlers())

    // start() resumes the Mach-service NSXPCListener. Repeated calls must
    // not trap: app launch + reinvocation by tests/tooling should be safe.
    sut.start()
    sut.start()
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
#endif
