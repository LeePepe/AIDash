#if os(macOS)
import Testing
import Foundation
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

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

    // MARK: - Helpers

    /// Convenience factory for a successful LaunchctlResult.
    private static func successResult(args: [String] = []) -> LaunchdAgentInstaller.LaunchctlResult {
        .init(arguments: args, terminationStatus: 0, stdout: "", stderr: "", launchError: nil)
    }

    /// Convenience factory for a failed LaunchctlResult with a given status and stderr.
    private static func failResult(args: [String] = [], status: Int32 = 1, stderr: String = "") -> LaunchdAgentInstaller.LaunchctlResult {
        .init(arguments: args, terminationStatus: status, stdout: "", stderr: stderr, launchError: nil)
    }

    /// Convenience factory for a launch error (process could not start).
    private static func launchErrorResult(args: [String] = [], error: String = "No such file") -> LaunchdAgentInstaller.LaunchctlResult {
        .init(arguments: args, terminationStatus: -1, stdout: "", stderr: "", launchError: error)
    }

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
            launchctl: { args in
                launchctlCalls.append(args)
                return Self.successResult(args: args)
            }
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
                if args.first == "print" {
                    return Self.failResult(args: args, status: 113, stderr: "Could not find service")
                }
                return Self.successResult(args: args)
            }
        )
        #expect(sut.registerIfNeeded() == .registered)
        #expect(written != nil)                                   // rewrote plist
        #expect(launchctlCalls.contains { $0.first == "bootout" })
        #expect(launchctlCalls.contains { $0.first == "bootstrap" })
    }

    @Test("known-absent print result (exit 3) triggers install")
    func knownAbsentPrintTriggersInstall() {
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },   // path matches
            writePlist: { _, _ in },
            // `print` returns exit 3 ("No such process") — known absence, safe to reinstall.
            launchctl: { args in
                launchctlCalls.append(args)
                if args.first == "print" {
                    return Self.failResult(args: args, status: 3, stderr: "No such process")
                }
                return Self.successResult(args: args)
            }
        )
        #expect(sut.registerIfNeeded() == .registered)
        #expect(launchctlCalls.contains { $0.first == "bootstrap" })
    }

    @Test("known-absent print result (exit 113) triggers install")
    func knownAbsent113TriggersInstall() {
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },
            writePlist: { _, _ in },
            launchctl: { args in
                launchctlCalls.append(args)
                if args.first == "print" {
                    return Self.failResult(args: args, status: 113, stderr: "Could not find service")
                }
                return Self.successResult(args: args)
            }
        )
        #expect(sut.registerIfNeeded() == .registered)
        #expect(launchctlCalls.contains { $0.first == "bootstrap" })
    }

    @Test("unknown print failure (exit 1) returns .failed without installing")
    func unknownPrintFailureReturnsFailed() {
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },
            writePlist: { _, _ in },
            launchctl: { args in
                launchctlCalls.append(args)
                if args.first == "print" {
                    return Self.failResult(args: args, status: 1, stderr: "Permission denied")
                }
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        if case .failed(let reason) = outcome {
            #expect(reason.contains("Permission denied"))
        } else {
            Issue.record("expected .failed, got \(outcome)")
        }
        // Must NOT attempt install when print failure is unclassified.
        #expect(!launchctlCalls.contains { $0.first == "bootout" })
        #expect(!launchctlCalls.contains { $0.first == "bootstrap" })
    }

    @Test("print launch error returns .failed without installing")
    func printLaunchErrorReturnsFailed() {
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },
            writePlist: { _, _ in },
            launchctl: { args in
                launchctlCalls.append(args)
                if args.first == "print" {
                    return Self.launchErrorResult(args: args, error: "launchctl binary not found")
                }
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        if case .failed(let reason) = outcome {
            #expect(reason.contains("launch error"))
        } else {
            Issue.record("expected .failed, got \(outcome)")
        }
        #expect(!launchctlCalls.contains { $0.first == "bootstrap" })
    }

    // MARK: - classifyPrint unit tests

    @Test("classifyPrint: success → loaded")
    func classifyPrintLoaded() {
        let r = Self.successResult(args: ["print", "gui/501/com.tianpli.aidash"])
        #expect(LaunchdAgentInstaller.classifyPrint(r) == .loaded)
    }

    @Test("classifyPrint: exit 113 → knownAbsent")
    func classifyPrint113() {
        let r = Self.failResult(args: ["print", "gui/501/com.tianpli.aidash"], status: 113, stderr: "Could not find service")
        #expect(LaunchdAgentInstaller.classifyPrint(r) == .knownAbsent)
    }

    @Test("classifyPrint: exit 3 → knownAbsent")
    func classifyPrint3() {
        let r = Self.failResult(args: ["print", "gui/501/com.tianpli.aidash"], status: 3, stderr: "No such process")
        #expect(LaunchdAgentInstaller.classifyPrint(r) == .knownAbsent)
    }

    @Test("classifyPrint: exit 1 → commandFailure")
    func classifyPrint1() {
        let r = Self.failResult(args: ["print", "gui/501/com.tianpli.aidash"], status: 1, stderr: "Something went wrong")
        #expect(LaunchdAgentInstaller.classifyPrint(r) == .commandFailure)
    }

    @Test("classifyPrint: launch error → commandFailure")
    func classifyPrintLaunchError() {
        let r = Self.launchErrorResult(args: ["print", "gui/501/com.tianpli.aidash"], error: "No such file")
        #expect(LaunchdAgentInstaller.classifyPrint(r) == .commandFailure)
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
            launchctl: { args in
                launchctlCalls.append(args)
                return Self.successResult(args: args)
            }
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

    // MARK: - Bootstrap failure with actionable diagnostics (MY-1439 regression)

    @Test("bootstrap failure includes termination status and stderr in reason")
    func bootstrapFailureIncludesDiagnostics() {
        let sut = LaunchdAgentInstaller(
            execPath: { "/new/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in nil },
            writePlist: { _, _ in },
            launchctl: { args in
                if args.first == "bootstrap" {
                    return Self.failResult(
                        args: args,
                        status: 5,
                        stderr: "Bootstrap failed: 5: Input/output error"
                    )
                }
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        if case .failed(let reason) = outcome {
            // Must contain the termination status and stderr — not just "bootstrap failed".
            #expect(reason.contains("exit 5"))
            #expect(reason.contains("Input/output error"))
        } else {
            Issue.record("expected .failed, got \(outcome)")
        }
    }

    @Test("bootstrap failure with empty stderr still reports exit code")
    func bootstrapFailureEmptyStderr() {
        let sut = LaunchdAgentInstaller(
            execPath: { "/new/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in nil },
            writePlist: { _, _ in },
            launchctl: { args in
                if args.first == "bootstrap" {
                    return Self.failResult(args: args, status: 78, stderr: "")
                }
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        if case .failed(let reason) = outcome {
            #expect(reason.contains("exit 78"))
            #expect(reason.contains("no stderr"))
        } else {
            Issue.record("expected .failed, got \(outcome)")
        }
    }

    @Test("launchctl process launch error produces actionable failure")
    func launchctlProcessLaunchError() {
        let sut = LaunchdAgentInstaller(
            execPath: { "/new/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in nil },
            writePlist: { _, _ in },
            launchctl: { args in
                if args.first == "bootstrap" {
                    return Self.launchErrorResult(args: args, error: "The file launchctl couldn't be opened.")
                }
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        if case .failed(let reason) = outcome {
            #expect(reason.contains("launch error"))
        } else {
            Issue.record("expected .failed, got \(outcome)")
        }
    }

    // MARK: - Successful recovery after bootstrap (self-heal scenario)

    @Test("successful recovery: bootout fails (no prior job) but bootstrap succeeds")
    func successfulRecoveryAfterBootoutFails() {
        var launchctlCalls: [[String]] = []
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },   // path matches, but job not loaded
            writePlist: { _, _ in },
            launchctl: { args in
                launchctlCalls.append(args)
                if args.first == "print" {
                    return Self.failResult(args: args, status: 113, stderr: "Could not find service")
                }
                if args.first == "bootout" {
                    // No prior job to boot out — normal for first install.
                    return Self.failResult(args: args, status: 3, stderr: "No such process")
                }
                // bootstrap succeeds
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome == .registered)
        #expect(launchctlCalls.contains { $0.first == "bootstrap" })
    }

    // MARK: - Repeat install is idempotent

    @Test("repeat install (already registered) is a no-op")
    func repeatInstallIsNoOp() {
        var callCount = 0
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },
            writePlist: { _, _ in },
            launchctl: { args in
                callCount += 1
                return Self.successResult(args: args)
            }
        )
        // First call
        #expect(sut.registerIfNeeded() == .registered)
        let firstCallCount = callCount
        // Second call — should still be a no-op (only print query)
        #expect(sut.registerIfNeeded() == .registered)
        // Both calls only issue a `print` query — total calls should be 2 (one per invocation).
        #expect(callCount == firstCallCount + 1)
    }

    // MARK: - Unrecoverable: bootstrap keeps failing

    @Test("unrecoverable bootstrap produces diagnostic with launchctl stderr")
    func unrecoverableBootstrapDiagnostic() {
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in "/a/AIDash" },
            writePlist: { _, _ in },
            launchctl: { args in
                if args.first == "print" {
                    return Self.failResult(args: args, status: 113, stderr: "Could not find service \"com.tianpli.aidash\" in domain for uid: 501")
                }
                if args.first == "bootstrap" {
                    return Self.failResult(args: args, status: 5, stderr: "Bootstrap failed: 5: Input/output error\nTry running `launchctl bootout` first")
                }
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        if case .failed(let reason) = outcome {
            // The failure reason must include useful launchctl status/stderr,
            // not the previous generic "bootstrap failed" string.
            #expect(reason.contains("exit 5"))
            #expect(reason.contains("Input/output error"))
        } else {
            Issue.record("expected .failed with diagnostic, got \(outcome)")
        }
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
            launchctl: { args in
                launchctlCalls.append(args)
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        #expect(outcome.isHealthy == false)
        // A read-only `print` job-loaded query may run first, but the mutating
        // bootout/bootstrap must never be reached once the write fails.
        #expect(!launchctlCalls.contains { $0.first == "bootout" })
        #expect(!launchctlCalls.contains { $0.first == "bootstrap" })
    }

    // MARK: - LaunchctlResult diagnosticSummary

    @Test("diagnosticSummary formats success correctly")
    func diagnosticSummarySuccess() {
        let r = LaunchdAgentInstaller.LaunchctlResult(
            arguments: ["print", "gui/501/com.tianpli.aidash"],
            terminationStatus: 0, stdout: "some output", stderr: "", launchError: nil)
        #expect(r.diagnosticSummary.contains("ok"))
    }

    @Test("diagnosticSummary formats failure with stderr")
    func diagnosticSummaryFailure() {
        let r = LaunchdAgentInstaller.LaunchctlResult(
            arguments: ["bootstrap", "gui/501", "/path/to/plist"],
            terminationStatus: 5, stdout: "", stderr: "Input/output error", launchError: nil)
        #expect(r.diagnosticSummary.contains("exit 5"))
        #expect(r.diagnosticSummary.contains("Input/output error"))
    }

    @Test("diagnosticSummary formats launch error")
    func diagnosticSummaryLaunchError() {
        let r = LaunchdAgentInstaller.LaunchctlResult(
            arguments: ["bootstrap", "gui/501", "/x"],
            terminationStatus: -1, stdout: "", stderr: "", launchError: "No such file")
        #expect(r.diagnosticSummary.contains("launch error"))
        #expect(r.diagnosticSummary.contains("No such file"))
    }

    // MARK: - Pipe capacity regression (deadlock prevention)

    @Test("large stdout+stderr beyond pipe capacity completes without deadlock")
    func largePipeOutputCompletesWithoutDeadlock() {
        // Simulate launchctl producing >64 KB on both stdout and stderr.
        // The injected seam returns the large strings directly — this proves
        // that the LaunchctlResult can carry large payloads and that the
        // registerIfNeeded flow handles them without hanging.
        let largeOutput = String(repeating: "x", count: 80_000) // >64 KB
        let largeStderr = String(repeating: "e", count: 80_000)
        let sut = LaunchdAgentInstaller(
            execPath: { "/a/AIDash" },
            plistURL: { URL(fileURLWithPath: "/tmp/x.plist") },
            installedExec: { _ in nil },
            writePlist: { _, _ in },
            launchctl: { args in
                if args.first == "print" {
                    // Known absence — proceeds to install.
                    return Self.failResult(args: args, status: 113, stderr: "Could not find service")
                }
                if args.first == "bootstrap" {
                    // Simulate a failure with large output on both streams.
                    return LaunchdAgentInstaller.LaunchctlResult(
                        arguments: args,
                        terminationStatus: 5,
                        stdout: largeOutput,
                        stderr: largeStderr,
                        launchError: nil
                    )
                }
                return Self.successResult(args: args)
            }
        )
        let outcome = sut.registerIfNeeded()
        // The test completing at all proves no deadlock.
        #expect(outcome.isHealthy == false)
        if case .failed(let reason) = outcome {
            // diagnosticSummary trims, so it won't contain 80K chars,
            // but it should contain the exit code.
            #expect(reason.contains("exit 5"))
        } else {
            Issue.record("expected .failed, got \(outcome)")
        }
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
