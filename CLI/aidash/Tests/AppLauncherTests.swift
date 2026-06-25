import Foundation
import Testing
import AIDashCore

/// No-op sleeper for tests — skips real delays.
private let instantSleeper: @Sendable (Duration) async throws -> Void = { _ in }

@Suite("AppLauncher")
struct AppLauncherTests {

    // MARK: - Probe succeeds immediately

    @Test("returns when probe succeeds on first poll")
    func probeSucceedsImmediately() async throws {
        let launcher = AppLauncher(launcher: { /* no-op */ }, sleeper: instantSleeper)

        try await launcher.launchAndWait(probe: { true })
        // No throw = success
    }

    // MARK: - Probe succeeds after several attempts

    @Test("returns when probe succeeds on third poll")
    func probeSucceedsAfterRetries() async throws {
        let counter = Counter()
        let launcher = AppLauncher(launcher: { /* no-op */ }, sleeper: instantSleeper)

        try await launcher.launchAndWait(
            probe: {
                let current = await counter.increment()
                return current >= 3
            }
        )

        let final = await counter.value
        #expect(final == 3)
    }

    // MARK: - Probe never succeeds → xpc.app_unavailable

    @Test("throws xpc.app_unavailable when probe never succeeds")
    func probeNeverSucceeds() async {
        let launcher = AppLauncher(launcher: { /* no-op */ }, sleeper: instantSleeper)

        do {
            try await launcher.launchAndWait(probe: { false })
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
        let launcher = AppLauncher(
            launcher: {
                throw NSError(domain: "test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "App not found",
                ])
            },
            sleeper: instantSleeper
        )

        do {
            try await launcher.launchAndWait(probe: { true })
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
        let failLauncher = AppLauncher(
            launcher: { throw NSError(domain: "test", code: 1) },
            sleeper: instantSleeper
        )
        let launchCode: String
        do {
            try await failLauncher.launchAndWait(probe: { true })
            launchCode = ""
        } catch let error as XPCError {
            launchCode = error.code
        } catch {
            launchCode = ""
        }

        // Unreachable
        let okLauncher = AppLauncher(launcher: { /* no-op */ }, sleeper: instantSleeper)
        let unreachableCode: String
        do {
            try await okLauncher.launchAndWait(probe: { false })
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

    // MARK: - Sleeper is actually called

    @Test("sleeper is invoked between each poll attempt")
    func sleeperCalledBetweenPolls() async throws {
        let sleepCounter = Counter()
        let probeCounter = Counter()
        let launcher = AppLauncher(
            launcher: { /* no-op */ },
            sleeper: { _ in _ = await sleepCounter.increment() }
        )

        try await launcher.launchAndWait(
            probe: {
                let n = await probeCounter.increment()
                return n >= 2
            }
        )

        let sleeps = await sleepCounter.value
        let probes = await probeCounter.value
        #expect(sleeps == probes)  // one sleep before each probe
    }
}

// MARK: - Test helper

/// Thread-safe counter for tracking invocations.
private actor Counter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
