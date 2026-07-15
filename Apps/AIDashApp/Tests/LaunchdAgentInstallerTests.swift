#if os(macOS)
import Testing
import Foundation
import ServiceManagement
import os
@testable import AIDashApp

/// Tests for `LaunchdAgentInstaller` (Bug 2: silent `.requiresApproval` bail).
///
/// Exercises the pure `decide(status:register:log:)` seam and the injected
/// `registerIfNeeded()` path with fake status readers / registrars, so no test
/// touches the real `SMAppService` (the test host cannot register a LaunchAgent).
@MainActor
@Suite("LaunchdAgentInstaller")
struct LaunchdAgentInstallerTests {

    private static let log = Logger(subsystem: "com.tianpli.aidash.tests", category: "launchd")

    // MARK: - decide()

    @Test("requiresApproval is terminal: never calls register, reports requiresApproval")
    func requiresApprovalDoesNotRegister() {
        var registerCalls = 0
        let outcome = LaunchdAgentInstaller.decide(
            status: .requiresApproval,
            register: { registerCalls += 1 },
            log: Self.log
        )
        #expect(outcome == .requiresApproval)
        #expect(registerCalls == 0)          // did NOT silently retry
        #expect(outcome.isHealthy == false)  // loud: not healthy
    }

    @Test("enabled status re-registers and reports registered")
    func enabledRegisters() {
        var registerCalls = 0
        let outcome = LaunchdAgentInstaller.decide(
            status: .enabled,
            register: { registerCalls += 1 },
            log: Self.log
        )
        #expect(outcome == .registered)
        #expect(registerCalls == 1)          // unconditional re-register
        #expect(outcome.isHealthy == true)
    }

    @Test("notRegistered status registers")
    func notRegisteredRegisters() {
        var registerCalls = 0
        let outcome = LaunchdAgentInstaller.decide(
            status: .notRegistered,
            register: { registerCalls += 1 },
            log: Self.log
        )
        #expect(outcome == .registered)
        #expect(registerCalls == 1)
    }

    @Test("register() throwing yields a loud .failed outcome, not a swallow")
    func registerFailureReported() {
        struct RegErr: LocalizedError {
            var errorDescription: String? { "launchd said no" }
        }
        let outcome = LaunchdAgentInstaller.decide(
            status: .enabled,
            register: { throw RegErr() },
            log: Self.log
        )
        guard case .failed(let reason) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(reason.contains("launchd said no"))
        #expect(outcome.isHealthy == false)
    }

    // MARK: - registerIfNeeded() via injected seam

    @Test("registerIfNeeded surfaces requiresApproval through the injected reader")
    func registerIfNeededSurfacesApproval() {
        let sut = LaunchdAgentInstaller(
            readStatus: { .requiresApproval },
            register: { Issue.record("register must not be called on requiresApproval") }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome == .requiresApproval)
    }

    @Test("registerIfNeeded returns registered on a healthy path")
    func registerIfNeededHealthy() {
        let sut = LaunchdAgentInstaller(
            readStatus: { .enabled },
            register: { /* success */ }
        )
        #expect(sut.registerIfNeeded() == .registered)
    }

    // MARK: - RegistrationOutcome.isHealthy

    @Test("only .registered is healthy")
    func healthyOnlyForRegistered() {
        #expect(LaunchdAgentInstaller.RegistrationOutcome.registered.isHealthy == true)
        #expect(LaunchdAgentInstaller.RegistrationOutcome.requiresApproval.isHealthy == false)
        #expect(LaunchdAgentInstaller.RegistrationOutcome.failed(reason: "x").isHealthy == false)
    }
}
#endif
