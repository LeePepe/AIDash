#if os(macOS)
import Foundation
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@MainActor
@Suite("AIDash Job Framework")
struct ScheduledPulseTests {
    @Test("registry is exactly the three live framework jobs")
    func registryShape() {
        #expect(ScheduledPulseRegistry.jobs.map(\.id) == [.myPRSupervisor, .prAutoReview, .aidataDigest])
        #expect(ScheduledPulseRegistry.liveJobs.count == 3)
        #expect(ScheduledPulseRegistry.reservedJobs.isEmpty)
        #expect(ScheduledPulseRegistry.jobs.allSatisfy { $0.isLive })
        #expect(ScheduledPulseRegistry.job(for: .myPRSupervisor)?.displayName == "我的 PR")
        #expect(ScheduledPulseRegistry.job(for: .prAutoReview)?.displayName == "特定人 PR")
        #expect(ScheduledPulseRegistry.job(for: .aidataDigest)?.displayName == "每日简报")
    }

    @Test("live plists use absolute programs and interpreter ProgramArguments")
    func plistShape() throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let expected: [(ScheduledPulseJobID, String, String)] = [
            (.myPRSupervisor, "/usr/bin/python3", "/Users/tester/Development/handoff/my-pr-supervisor/precheck.py"),
            (.prAutoReview, "/usr/bin/python3", "/Users/tester/Development/handoff/pr-auto-review/precheck.py"),
            (.aidataDigest, "/bin/zsh", "/Users/tester/Development/AIDash/aidata/scripts/aidata_digest_run.sh")
        ]
        let wrapper = "/Users/tester/Development/AIDash/scripts/scheduled-job-entrypoint.sh"
        for (id, interpreter, program) in expected {
            let definition = try #require(ScheduledPulseRegistry.job(for: id))
            let data = try #require(ScheduledPulseLaunchdInstaller.plistData(for: definition, homeURL: home))
            let plist = try #require(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
            #expect(plist["Label"] as? String == definition.launchAgentLabel)
            #expect(plist["Program"] as? String == "/bin/zsh")
            #expect(plist["ProgramArguments"] as? [String] == ["/bin/zsh", wrapper, id.rawValue, interpreter, program])
            if id == .aidataDigest {
                #expect(plist["StartCalendarInterval"] as? [String: Any] != nil)
                #expect((plist["StartCalendarInterval"] as? [String: Any])?["TimeZone"] == nil)
            } else {
                #expect(plist["StartInterval"] as? Int == 300)
            }
        }
    }

    @Test("owned start and stop use exact labels and never remove the plist")
    func startStopLabels() throws {
        let job = try #require(ScheduledPulseRegistry.job(for: .myPRSupervisor))
        var calls: [[String]] = []
        var removed = false
        let installer = ScheduledPulseLaunchdInstaller(
            registry: [job],
            plistURL: { _ in URL(fileURLWithPath: "/owned.plist") },
            installedPlist: { _ in Data() },
            createDirectory: { _ in },
            writePlist: { _, _ in },
            launchctl: { args in
                calls.append(args)
                if args.first == "bootout" { removed = true }
                return .init(arguments: args, terminationStatus: 0, stdout: "", stderr: "", launchError: nil)
            },
            currentTimeZoneIdentifier: { "Asia/Shanghai" }
        )
        #expect(installer.start(jobID: job.id).isHealthy)
        #expect(installer.stop(jobID: job.id).isHealthy)
        #expect(calls == [
            ["bootstrap", "gui/\(getuid())", "/owned.plist"],
            ["bootout", "gui/\(getuid())/\(job.launchAgentLabel)"]
        ])
        #expect(removed)
    }

    @Test("state and action files drive ordering, empty state, and controls")
    func dynamicStateAndActions() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let stateData = Data("""
        {"id":"pr-auto-review","updatedAt":"1970-01-01T00:16:40Z","lastResult":"failed","lastRunAt":"1970-01-01T00:16:30Z","summary":"失败","overviewMd":"失败详情"}
        """.utf8)
        let actionData = Data("""
        {"id":"a1","jobID":"pr-auto-review","title":"确认修复","descriptionMd":"请选择处理方式","controls":[{"id":"confirm","kind":"confirm","title":"确认"},{"id":"text","kind":"textInput","title":"备注","maxLength":120}]}
        """.utf8)
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let reader = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
            now: now,
            fileReader: { url in
                if url.lastPathComponent == "state.json" { return stateData }
                if url.lastPathComponent == "actions.jsonl" && url.path.contains("pr-auto-review") { return actionData }
                return nil
            },
            homeURL: home
        )
        #expect(reader.entries.count == 3)
        #expect(reader.overviewEntries.first?.id == ScheduledPulseJobID.prAutoReview)
        #expect(reader.overviewEntries.count == 1)
        #expect(reader.unacknowledgedActions.count == 1)
        let control = try #require(reader.unacknowledgedActions.first?.controls.last)
        #expect(control.effectiveMaxLength == 80)
        #expect(ScheduledJobActionResponse(controlID: "text", value: String(repeating: "x", count: 100)).value.count == 80)
        #expect(ScheduledJobFrameworkLogic.unacknowledgedActions(from: reader, acknowledgedIDs: ["a1"]).isEmpty)
        let reloaded = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
            now: now,
            fileReader: { url in
                if url.lastPathComponent == "state.json" { return stateData }
                if url.lastPathComponent == "actions.jsonl" && url.path.contains("pr-auto-review") { return actionData }
                return nil
            },
            homeURL: home,
            acknowledgedActionIDs: ["a1"]
        )
        #expect(reloaded.unacknowledgedActions.isEmpty)

        let empty = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
            now: now,
            fileReader: { _ in nil },
            homeURL: home
        )
        #expect(empty.allHaveNoState)
        #expect(empty.overviewEntries.isEmpty)
    }

    @Test("same-id fires coalesce without queueing")
    func coalescesSameID() async {
        let coordinator = ScheduledJobRunCoordinator()
        let gate = AsyncGate()
        let entered = AsyncGate()
        let first = Task { await coordinator.fire(id: .myPRSupervisor) { await entered.open(); await gate.wait() } }
        await entered.wait()
        let second = await coordinator.fire(id: .myPRSupervisor) {}
        #expect(second == .coalesced)
        await gate.open()
        #expect(await first.value == .started)
    }

    @Test("populated menubar renders one result row per registered job and routes failures")
    func populatedMenubarRouting() {
        var opens = 0
        let snapshot = ScheduledJobFrameworkSnapshot(
            capturedAt: .now,
            entries: ScheduledPulseRegistry.jobs.map {
                ScheduledJobFrameworkEntry(
                    definition: $0,
                    state: ScheduledJobState(id: $0.id, lastResult: $0.id == .prAutoReview ? .failed : .succeeded)
                )
            }
        )
        let view = MenuBarStatusView(
            state: .populated(Self.menuSnapshot()),
            onOpenScheduledPulse: { opens += 1 },
            scheduledJobFrameworkSnapshot: snapshot
        )
        _ = view.body
        #expect(ScheduledJobFrameworkLogic.successStripText(for: snapshot).contains("特定人 PR ✗"))
        #expect(snapshot.entries.count == 3)
        view.onOpenScheduledPulse()
        #expect(opens == 1)
    }

    private static func menuSnapshot() -> MenuBarSystemSnapshot {
        MenuBarSystemSnapshot(
            capturedAt: .now,
            machine: MachineStatusSnapshot(totalCores: 1, performanceCores: 1, efficiencyCores: 0, powerSummary: "AC"),
            cpu: CPUStatusSnapshot(usage: 0, user: 0, system: 0, idle: 1, coreCount: 1, loadOneMinute: 0, loadFiveMinutes: 0, loadFifteenMinutes: 0, gpu: GPUStatusSnapshot(deviceUtilization: 0), topProcessName: "", topProcessValueText: ""),
            memory: MemoryStatusSnapshot(usedBytes: 0, totalBytes: 1, freeBytes: 1, wiredBytes: 0, compressedBytes: 0, pressure: .normal, topProcessName: "", topProcessValueText: ""),
            storage: StorageStatusSnapshot(systemVolume: StorageVolumeSnapshot(id: "root", name: "Root", mountPoint: "/", isMounted: true, isExternalSSD: false, usedBytes: 0, availableBytes: 1, totalBytes: 1), ssdVolume: StorageVolumeSnapshot(id: "ssd", name: "SSD", mountPoint: "/Volumes/SSD", isMounted: false, isExternalSSD: true, usedBytes: 0, availableBytes: 0, totalBytes: 0)),
            tokenUsage: CLITokenUsageSnapshot(items: []),
            attention: AttentionStatusSnapshot(needsPersonCount: 0, items: [])
        )
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
#endif
