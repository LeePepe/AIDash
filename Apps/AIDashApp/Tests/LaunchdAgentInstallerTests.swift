#if os(macOS)
import Testing
import Foundation
@testable import AIDashApp

/// Tests for `LaunchdAgentInstaller` — the plain-`launchctl` LaunchAgent installer
/// that replaced `SMAppService` (root cause: SMAppService attaches a Launch
/// Constraint / LWCR that kills the per-build-re-signed DerivedData agent spawn).
///
/// The pure `decide(currentExec:installedExec:)` seam and the injected effect
/// closures (plist read/write, launchctl) are exercised with fakes, so no test
/// touches the real `~/Library/LaunchAgents` or `/bin/launchctl`.
@MainActor
@Suite("LaunchdAgentInstaller")
struct LaunchdAgentInstallerTests {

    // MARK: - decide(): up-to-date only when path matches AND job is loaded

    @Test("up-to-date when installed exec matches AND job is loaded")
    func upToDateWhenMatchingAndLoaded() {
        #expect(LaunchdAgentInstaller.decide(
            currentExec: "/a/AIDash", installedExec: "/a/AIDash",
            jobLoaded: true) == .upToDate)
    }

    @Test("install when plist matches but launchd job is NOT loaded (self-heal)")
    func installWhenMatchingButNotLoaded() {
        // The root-cause regression guard: a matching plist on disk must NOT be
        // trusted when launchd has booted the job out — reinstall to self-heal.
        #expect(LaunchdAgentInstaller.decide(
            currentExec: "/a/AIDash", installedExec: "/a/AIDash",
            jobLoaded: false) == .install)
    }

    @Test("install when the plist is absent")
    func installWhenAbsent() {
        #expect(LaunchdAgentInstaller.decide(
            currentExec: "/a/AIDash", installedExec: nil,
            jobLoaded: true) == .install)
    }

    @Test("install when the plist points at a stale build (rebuild self-heals)")
    func installWhenStale() {
        #expect(LaunchdAgentInstaller.decide(
            currentExec: "/new/AIDash", installedExec: "/old/AIDash",
            jobLoaded: true) == .install)
    }

    // MARK: - registerIfNeeded(): up-to-date is a cheap no-op

    @Test("up-to-date launch writes nothing and runs no bootout/bootstrap")
    func upToDateIsNoOp() {
        var wrote = false
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },   // path matches
            writePlist: { _, _ in wrote = true },
            // print (job-loaded query) succeeds ⇒ loaded; nothing else runs.
            launchctl: { launchctlCalls.append($0); return true }
        )
        #expect(sut.registerIfNeeded() == .registered)
        #expect(wrote == false)
        // Only the read-only `print` query ran — no bootout/bootstrap.
        #expect(launchctlCalls.allSatisfy { $0.first == "print" })
        #expect(!launchctlCalls.contains { $0.first == "bootout" })
        #expect(!launchctlCalls.contains { $0.first == "bootstrap" })
    }

    // MARK: - registerIfNeeded(): the self-heal case (the root-cause fix)

    @Test("matching plist but unloaded job triggers write + bootout + bootstrap")
    func unloadedJobSelfHeals() {
        var written: Data?
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },   // path MATCHES…
            writePlist: { _, data in written = data },
            // …but `print` reports the job is NOT loaded ⇒ must reinstall.
            launchctl: { args in
                launchctlCalls.append(args)
                return args.first == "print" ? false : true
            }
        )
        #expect(sut.registerIfNeeded() == .registered)
        #expect(written != nil)                                   // rewrote plist
        #expect(launchctlCalls.contains { $0.first == "bootout" })
        #expect(launchctlCalls.contains { $0.first == "bootstrap" })
    }

    @Test("fail-safe: a failing job-loaded query is treated as unloaded → install")
    func failSafeQueryTreatedAsUnloaded() {
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },   // path matches
            writePlist: { _, _ in },
            // `print` returns false (simulating a launchctl hiccup, not a
            // definitive "absent") — fail-safe still reinstalls.
            launchctl: { args in
                launchctlCalls.append(args)
                return args.first == "print" ? false : true
            }
        )
        #expect(sut.registerIfNeeded() == .registered)
        #expect(launchctlCalls.contains { $0.first == "bootstrap" })
    }

    // MARK: - registerIfNeeded(): a rebuild rewrites + bootout + bootstrap

    @Test("stale plist triggers write, then bootout then bootstrap")
    func staleTriggersReinstall() {
        var written: Data?
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/new/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/old/AIDash" },
            writePlist: { _, data in written = data },
            launchctl: { launchctlCalls.append($0); return true }
        )
        #expect(sut.registerIfNeeded() == .registered)
        #expect(written != nil)
        // The reinstall's mutating calls are bootout then bootstrap, in order
        // (a read-only `print` query may precede them; filter to the mutations).
        let mutations = launchctlCalls.filter { $0.first == "bootout" || $0.first == "bootstrap" }
        #expect(mutations.count == 2)
        #expect(mutations[0].first == "bootout")
        #expect(mutations[1].first == "bootstrap")
    }

    @Test("bootstrap failure is reported as .failed")
    func bootstrapFailureIsLoud() {
        let sut = LaunchdAgentInstaller(
            execPath: { "/new/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in nil },
            writePlist: { _, _ in },
            launchctl: { args in args.first == "bootstrap" ? false : true }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        if case .failed = outcome {} else { Issue.record("expected .failed, got \(outcome)") }
    }

    @Test("a write failure is reported as .failed and never bootstraps")
    func writeFailureIsLoud() {
        struct WriteError: Error {}
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/new/AIDash" },
            plistURL: { URL(fileURLWithPath: "/does/not/exist/x.plist") },
            installedExec: { _ in nil },
            writePlist: { _, _ in throw WriteError() },
            launchctl: { launchctlCalls.append($0); return true }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        // A read-only `print` job-loaded query may run first, but the mutating
        // bootout/bootstrap must never be reached once the write fails.
        #expect(!launchctlCalls.contains { $0.first == "bootout" })
        #expect(!launchctlCalls.contains { $0.first == "bootstrap" })
    }

    // MARK: - plist authoring

    @Test("plist declares the mach service, program, and the agent env var")
    func plistShape() throws {
        let data = LaunchdAgentInstaller.plistData(execPath: "/a/AIDash")
        let plist = try #require(try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any])
        #expect(plist["Program"] as? String == "/a/AIDash")
        #expect(plist["Label"] as? String == LaunchdAgentInstaller.label)
        let mach = try #require(plist["MachServices"] as? [String: Any])
        #expect(mach[LaunchdAgentInstaller.machServiceName] as? Bool == true)
        let env = try #require(plist["EnvironmentVariables"] as? [String: Any])
        #expect(env[LaunchdAgentInstaller.agentEnvVar] as? String == "1")
        // No RunAtLoad / KeepAlive — on-demand only.
        #expect(plist["RunAtLoad"] == nil)
        #expect(plist["KeepAlive"] == nil)
    }

    @Test("readProgram round-trips the authored plist")
    func readProgramRoundTrips() throws {
        let data = LaunchdAgentInstaller.plistData(execPath: "/round/AIDash")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-\(UUID().uuidString).plist")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LaunchdAgentInstaller.readProgram(from: url) == "/round/AIDash")
    }
}
#endif
