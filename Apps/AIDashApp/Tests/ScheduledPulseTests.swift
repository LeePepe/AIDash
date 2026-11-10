#if os(macOS)
import Foundation
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@MainActor
@Suite("Scheduled Pulse")
struct ScheduledPulseTests {
    private static func populatedMenuBarSnapshot() -> MenuBarSystemSnapshot {
        MenuBarSystemSnapshot(
            capturedAt: Date(timeIntervalSince1970: 0),
            machine: MachineStatusSnapshot(totalCores: 10, performanceCores: 6, efficiencyCores: 4, powerSummary: "AC"),
            cpu: CPUStatusSnapshot(
                usage: 0.25, user: 0.1, system: 0.15, idle: 0.75, coreCount: 10,
                loadOneMinute: 1, loadFiveMinutes: 1, loadFifteenMinutes: 1,
                gpu: GPUStatusSnapshot(deviceUtilization: 0.5),
                topProcessName: "worker", topProcessValueText: "10 ticks"
            ),
            memory: MemoryStatusSnapshot(
                usedBytes: 1, totalBytes: 2, freeBytes: 1, wiredBytes: 0, compressedBytes: 0,
                pressure: .normal, topProcessName: "worker", topProcessValueText: "1.0M"
            ),
            storage: StorageStatusSnapshot(
                systemVolume: StorageVolumeSnapshot(id: "root", name: "Root", mountPoint: "/", isMounted: true, isExternalSSD: false, usedBytes: 1, availableBytes: 1, totalBytes: 2),
                ssdVolume: StorageVolumeSnapshot(id: "ssd", name: "SSD", mountPoint: "/Volumes/SSD", isMounted: false, isExternalSSD: true, usedBytes: 0, availableBytes: 0, totalBytes: 0)
            ),
            tokenUsage: CLITokenUsageSnapshot(items: []),
            attention: AttentionStatusSnapshot(needsPersonCount: 0, items: [])
        )
    }

    @Test("registry contains exactly two live PR jobs and one reserved WorkIQ row")
    func registryShape() {
        #expect(ScheduledPulseRegistry.jobs.map(\.id) == [
            .myPRSupervisor, .prAutoReview, .workiqDigest
        ])
        #expect(ScheduledPulseRegistry.liveJobs.count == 2)
        #expect(ScheduledPulseRegistry.reservedJobs.map(\.id) == [.workiqDigest])
        #expect(ScheduledPulseRegistry.job(for: .workiqDigest)?.program == nil)
        #expect(ScheduledPulseRegistry.job(for: .workiqDigest)?.cadence == .reserved)
    }

    @Test("live job plist data has deterministic labels, absolute programs, and five-minute cadence")
    func plistShape() throws {
        let homeURL = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        for (id, program) in [
            (ScheduledPulseJobID.myPRSupervisor, "/Users/tester/Development/handoff/my-pr-supervisor/precheck.py"),
            (ScheduledPulseJobID.prAutoReview, "/Users/tester/Development/handoff/pr-auto-review/precheck.py")
        ] {
            let definition = try #require(ScheduledPulseRegistry.job(for: id))
            let data = try #require(ScheduledPulseLaunchdInstaller.plistData(for: definition, homeURL: homeURL))
            let plist = try #require(
                PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            )
            #expect(plist["Label"] as? String == definition.launchAgentLabel)
            #expect(plist["Program"] as? String == program)
            #expect(plist["StartInterval"] as? Int == 300)
        }

        let workiq = try #require(ScheduledPulseRegistry.job(for: .workiqDigest))
        #expect(ScheduledPulseLaunchdInstaller.plistData(for: workiq) == nil)
    }

    @Test("installer plan is idempotent and skips the reserved job")
    func installPlan() throws {
        let job = try #require(ScheduledPulseRegistry.job(for: .myPRSupervisor))
        let plist = try #require(ScheduledPulseLaunchdInstaller.plistData(for: job, homeURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true)))
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: plist, expected: plist, isLive: true) == .upToDate)
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: plist, expected: plist, isLive: true, jobLoaded: false) == .install)
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: nil, expected: plist, isLive: true) == .install)
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: Data("stale".utf8), expected: plist, isLive: true) == .install)
        #expect(ScheduledPulseLaunchdInstaller.plan(installed: nil, expected: nil, isLive: false) == .skipReserved)
    }

    @Test("installer writes only live plists and bootstraps the user GUI domain")
    func installerEffects() {
        var writes: [(URL, Data)] = []
        var launchctlCalls: [[String]] = []
        let installer = ScheduledPulseLaunchdInstaller(
            plistURL: { _ in URL(fileURLWithPath: "/dev/null") },
            installedPlist: { _ in nil },
            createDirectory: { _ in },
            writePlist: { url, data in writes.append((url, data)) },
            launchctl: { args in
                launchctlCalls.append(args)
                if args.first == "print" {
                    return .init(arguments: args, terminationStatus: 113, stdout: "", stderr: "Could not find service", launchError: nil)
                }
                return .init(arguments: args, terminationStatus: 0, stdout: "", stderr: "", launchError: nil)
            },
            currentTimeZoneIdentifier: { "Asia/Shanghai" }
        )

        let outcomes = installer.registerLiveJobs()
        #expect(outcomes == Array(repeating: .registered, count: 2))
        #expect(writes.count == 2)
        #expect(launchctlCalls.count == 4)
        #expect(launchctlCalls.filter { $0.first == "print" }.count == 2)
        #expect(launchctlCalls.filter { $0.first == "bootstrap" }.count == 2)
        #expect(launchctlCalls.filter { $0.first == "bootstrap" }.allSatisfy { $0.count == 3 && $0[1] == "gui/\(getuid())" })
        #expect(launchctlCalls.filter { $0.first == "bootstrap" }.allSatisfy { $0.count == 3 && $0[2] == "/dev/null" })
        #expect(!launchctlCalls.contains { $0.contains("workiq-digest") })
    }

    @Test("installer queries owned labels, bootstraps absent matches, and reboots stale jobs")
    func installerAccountsForJobState() throws {
        let definition = try #require(ScheduledPulseRegistry.job(for: .prAutoReview))
        let expected = try #require(ScheduledPulseLaunchdInstaller.plistData(
            for: definition,
            homeURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        ))
        var calls: [[String]] = []
        var writes = 0
        let installer = ScheduledPulseLaunchdInstaller(
            registry: [definition],
            plistURL: { _ in URL(fileURLWithPath: "/dev/null") },
            installedPlist: { _ in expected },
            createDirectory: { _ in },
            writePlist: { _, _ in writes += 1 },
            launchctl: { args in
                calls.append(args)
                if args.first == "print" {
                    return .init(arguments: args, terminationStatus: 113, stdout: "", stderr: "absent", launchError: nil)
                }
                return .init(arguments: args, terminationStatus: 0, stdout: "", stderr: "", launchError: nil)
            },
            currentTimeZoneIdentifier: { "Asia/Shanghai" }
        )
        #expect(installer.registerLiveJobs() == [.registered])
        #expect(calls.map { $0.first ?? "" } == ["print", "bootstrap"])
        #expect(writes == 1)

        calls.removeAll()
        writes = 0
        let staleInstaller = ScheduledPulseLaunchdInstaller(
            registry: [definition],
            plistURL: { _ in URL(fileURLWithPath: "/dev/null") },
            installedPlist: { _ in Data("stale".utf8) },
            createDirectory: { _ in },
            writePlist: { _, _ in writes += 1 },
            launchctl: { args in
                calls.append(args)
                return .init(arguments: args, terminationStatus: 0, stdout: "loaded", stderr: "", launchError: nil)
            },
            currentTimeZoneIdentifier: { "Asia/Shanghai" }
        )
        #expect(staleInstaller.registerLiveJobs() == [.registered])
        #expect(calls.map { $0.first ?? "" } == ["print", "bootout", "bootstrap"])
        #expect(writes == 1)
    }

    @Test("filters retain the reserved WorkIQ row and order exceptions critical then warning")
    func filteringAndExceptions() {
        let jobs = ScheduledPulseRegistry.jobs
        let statuses = jobs.map { definition -> ScheduledJobStatus in
            switch definition.id {
            case .prAutoReview:
                return ScheduledJobStatus(definition: definition, health: .critical)
            case .myPRSupervisor:
                return ScheduledJobStatus(definition: definition, health: .expectedOnButIdle)
            case .workiqDigest:
                return ScheduledJobStatus(definition: definition, health: .reserved)
            }
        }
        let snapshot = ScheduledPulseSnapshot(capturedAt: Date(timeIntervalSince1970: 0), jobs: statuses)
        #expect(ScheduledPulseLogic.defaultHealthFilter(for: snapshot) == .unhealthy)
        #expect(ScheduledPulseLogic.filteredJobs(from: snapshot, scheduler: .all, health: .unhealthy).last?.id == .workiqDigest)
        #expect(ScheduledPulseLogic.exceptions(from: snapshot).map(\.id) == [.prAutoReview, .myPRSupervisor])
    }

    @Test("live reader queries only owned labels and exposes launchd failures")
    func liveReaderReadsOwnedJobs() {
        var calls: [[String]] = []
        let snapshot = LiveDashboardTelemetryReader.loadScheduledPulseSnapshot(
            now: Date(timeIntervalSince1970: 0),
            launchctl: { args in
                calls.append(args)
                let label = args.last ?? ""
                if label.contains("pr-auto-review") {
                    return .init(arguments: args, terminationStatus: 113, stdout: "", stderr: "absent", launchError: nil)
                }
                return .init(
                    arguments: args,
                    terminationStatus: 0,
                    stdout: "state = running\nlast exit code = 0\nlast exit time = 2026-11-10T07:00:00Z",
                    stderr: "",
                    launchError: nil
                )
            }
        )
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.count == 2 && $0[0] == "print" })
        #expect(calls.allSatisfy { $0[1].contains("com.tianpli.aidash.job.") })
        #expect(snapshot.jobs.first(where: { $0.id == .prAutoReview })?.health == .expectedOnButIdle)
        #expect(snapshot.jobs.first(where: { $0.id == .myPRSupervisor })?.health == .healthy)
        #expect(snapshot.jobs.first(where: { $0.id == .myPRSupervisor })?.lastTick != nil)
        #expect(snapshot.jobs.count == 3)
    }

    @Test("menubar pulse routing is read-only and opens Scheduled Pulse")
    func menubarRouting() {
        var openCount = 0
        let snapshot = ScheduledPulseSnapshot(
            capturedAt: Date(timeIntervalSince1970: 0),
            jobs: ScheduledPulseRegistry.jobs.map { definition in
                ScheduledJobStatus(definition: definition, health: definition.isLive ? .critical : .reserved)
            }
        )
        let view = MenuBarStatusView(
            state: .populated(Self.populatedMenuBarSnapshot()),
            onOpenScheduledPulse: { openCount += 1 },
            scheduledPulseSnapshot: snapshot
        )
        _ = view.body
        view.onOpenScheduledPulse()
        #expect(openCount == 1)
        #expect(ScheduledPulseLogic.exceptions(from: snapshot).map(\.id) == [.myPRSupervisor, .prAutoReview])
        #expect(ScheduledPulseLogic.exceptions(from: snapshot).count == 2)
    }
}
#endif
