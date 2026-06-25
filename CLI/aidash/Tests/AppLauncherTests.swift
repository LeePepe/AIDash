import Foundation
import Testing
import AIDashCore

@Suite("AppLauncher")
struct AppLauncherTests {

    // MARK: - Probe succeeds immediately

    @Test("returns when probe succeeds on first poll")
    func probeSucceedsImmediately() async throws {
        let launcher = AppLauncher(launcher: { /* no-op: skip real NSWorkspace */ })

        try await launcher.launchAndWait(
            probe: { true },
            maxAttempts: 3,
            pollInterval: .milliseconds(10)
        )
        // No throw = success
    }

    // MARK: - Probe succeeds after several attempts

    @Test("returns when probe succeeds on third poll")
    func probeSucceedsAfterRetries() async throws {
        let counter = Counter()
        let launcher = AppLauncher(launcher: { /* no-op */ })

        try await launcher.launchAndWait(
            probe: {
                let current = await counter.increment()
                return current >= 3
            },
            maxAttempts: 5,
            pollInterval: .milliseconds(10)
        )

        let final = await counter.value
        #expect(final == 3)
    }

    // MARK: - Probe never succeeds → xpc.app_unavailable

    @Test("throws xpc.app_unavailable when probe never succeeds")
    func probeNeverSucceeds() async {
        let launcher = AppLauncher(launcher: { /* no-op */ })

        do {
            try await launcher.launchAndWait(
                probe: { false },
                maxAttempts: 3,
                pollInterval: .milliseconds(10)
            )
            Issue.record("Expected XPCError but launchAndWait returned")
        } catch let error as XPCError {
            #expect(error.code == "xpc.app_unavailable")
            #expect(error.message.contains("not reachable"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Launch failure → xpc.app_launch_failed

    @Test("throws xpc.app_launch_failed when launcher throws")
    func launchFails() async {
        let launcher = AppLauncher(launcher: {
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "App not found",
            ])
        })

        do {
            try await launcher.launchAndWait(
                probe: { true },
                maxAttempts: 3,
                pollInterval: .milliseconds(10)
            )
            Issue.record("Expected XPCError but launchAndWait returned")
        } catch let error as XPCError {
            #expect(error.code == "xpc.app_launch_failed")
            #expect(error.message.contains("Could not launch AIDash.app"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Distinct error codes

    @Test("launch failure and unreachable produce distinct error codes")
    func distinctErrorCodes() async {
        // Launch failure
        let failLauncher = AppLauncher(launcher: {
            throw NSError(domain: "test", code: 1)
        })
        let launchCode: String
        do {
            try await failLauncher.launchAndWait(
                probe: { true },
                maxAttempts: 1,
                pollInterval: .milliseconds(10)
            )
            launchCode = ""
        } catch let error as XPCError {
            launchCode = error.code
        } catch {
            launchCode = ""
        }

        // Unreachable
        let okLauncher = AppLauncher(launcher: { /* no-op */ })
        let unreachableCode: String
        do {
            try await okLauncher.launchAndWait(
                probe: { false },
                maxAttempts: 1,
                pollInterval: .milliseconds(10)
            )
            unreachableCode = ""
        } catch let error as XPCError {
            unreachableCode = error.code
        } catch {
            unreachableCode = ""
        }

        #expect(launchCode == "xpc.app_launch_failed")
        #expect(unreachableCode == "xpc.app_unavailable")
        #expect(launchCode != unreachableCode)
    }
}

// MARK: - Test helper

/// Thread-safe counter for tracking probe invocations.
private actor Counter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
