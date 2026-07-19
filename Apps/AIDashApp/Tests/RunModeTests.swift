#if os(macOS)
import Testing
import Foundation
@testable import AIDashApp

/// Tests for `RunMode.decide(env:)` — the pure agent-vs-GUI decision made once at
/// launch. Agent mode (launchd-spawned headless process, flagged by
/// `AIDASH_XPC_AGENT=1` in the LaunchAgent plist) must take the listener-only,
/// local-only, no-GUI path; a normal user/Xcode launch stays GUI.
@Suite("RunMode")
struct RunModeTests {

    @Test("AIDASH_XPC_AGENT=1 selects agent mode")
    func agentEnvSelectsAgent() {
        #expect(RunMode.decide(env: [LaunchdAgentInstaller.agentEnvVar: "1"]) == .agent)
    }

    @Test("absent env selects GUI mode")
    func absentSelectsGUI() {
        #expect(RunMode.decide(env: [:]) == .gui)
    }

    @Test("a non-1 value selects GUI mode (only exactly \"1\" is agent)")
    func nonOneSelectsGUI() {
        #expect(RunMode.decide(env: [LaunchdAgentInstaller.agentEnvVar: "0"]) == .gui)
        #expect(RunMode.decide(env: [LaunchdAgentInstaller.agentEnvVar: "true"]) == .gui)
    }

    @Test("XCTestConfigurationFilePath selects test-host mode")
    func xctestEnvSelectsTestHost() {
        #expect(RunMode.decide(env: ["XCTestConfigurationFilePath": "/tmp/x"]) == .testHost)
        #expect(RunMode.decide(env: ["XCTestBundlePath": "/tmp/y.xctest"]) == .testHost)
    }

    @Test("agent mode wins over a test-host env (a launchd spawn is never a test)")
    func agentBeatsTestHost() {
        #expect(RunMode.decide(env: [
            LaunchdAgentInstaller.agentEnvVar: "1",
            "XCTestConfigurationFilePath": "/tmp/x",
        ]) == .agent)
    }
}
#endif
