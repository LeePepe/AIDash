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

    @Test("coalescing entrypoint releases its lock after the child exits")
    func coalescingEntrypointReleasesLock() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/scheduled-job-entrypoint.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(script.contains("fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)"))
        #expect(script.contains("exit_code = proc.returncode"))
        #expect(script.contains("os.rmdir(lock_dir)"))
        #expect(!script.contains("exec \"$interpreter\""))

        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-entrypoint-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)

        let childScriptURL = tempHome.appendingPathComponent("job.py")
        try """
        import json, os, sys, time
        from pathlib import Path
        state_path = Path(os.environ["HOME"]) / "Library/Application Support/AIDash/jobs/my-pr-supervisor/state.json"
        state_path.write_text(json.dumps({
            "id": "my-pr-supervisor",
            "updatedAt": "2026-11-10T12:00:00Z",
            "lastResult": "succeeded",
            "lastRunAt": "2026-11-10T12:00:00Z",
            "summary": "自定义汇总",
            "overviewMd": "子任务自定义详情"
        }, ensure_ascii=False) + "\\n", encoding="utf-8")
        time.sleep(0.5)
        sys.exit(0)
        """.write(to: childScriptURL, atomically: true, encoding: .utf8)

        func makeProcess() -> Process {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = [scriptURL.path, "my-pr-supervisor", "/usr/bin/python3", childScriptURL.path]
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = tempHome.path
            proc.environment = env
            return proc
        }

        let jobDir = tempHome.appendingPathComponent("Library/Application Support/AIDash/jobs/my-pr-supervisor", isDirectory: true)
        let lockDirURL = jobDir.appendingPathComponent(".running.lock", isDirectory: true)
        let p1 = makeProcess()
        let p2 = makeProcess()
        try p1.run()
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: lockDirURL.path) {
            Thread.sleep(forTimeInterval: 0.02)
        }
        try p2.run()
        p2.waitUntilExit()
        #expect(p2.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: jobDir.appendingPathComponent(".coalesced").path))

        p1.waitUntilExit()
        #expect(p1.terminationStatus == 0)

        let finalData = try Data(contentsOf: jobDir.appendingPathComponent("state.json"))
        let finalText = try #require(String(data: finalData, encoding: .utf8))
        #expect(finalText.contains("\"lastResult\": \"succeeded\""))
        #expect(finalText.contains("\"summary\": \"自定义汇总\""))
        #expect(!FileManager.default.fileExists(atPath: jobDir.appendingPathComponent(".running.lock").path))

        try """
        import sys
        sys.exit(2)
        """.write(to: childScriptURL, atomically: true, encoding: .utf8)
        let p3 = makeProcess()
        try p3.run()
        p3.waitUntilExit()
        #expect(p3.terminationStatus == 2)

        let failedData = try Data(contentsOf: jobDir.appendingPathComponent("state.json"))
        let failedText = try #require(String(data: failedData, encoding: .utf8))
        #expect(failedText.contains("\"lastResult\": \"failed\""))
        #expect(failedText.contains("\"summary\": \"exit 2\""))

        let snapshot = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
            now: .now,
            homeURL: tempHome
        )
        let entry = try #require(snapshot.entries.first(where: { $0.id == .myPRSupervisor }))
        #expect(entry.state?.lastResult == .failed)
        #expect(entry.state?.lastRunAt != nil)
        #expect(entry.state?.summary == "exit 2")
    }

    @Test("acknowledging an action in one job does not hide a same-id action in another job")
    func acknowledgementIsScopedByJobIDAndActionID() {
        let store = DashboardWorkspaceStore(snapshot: Self.menuSnapshot())
        let action1 = ScheduledJobAction(
            id: "shared-id",
            jobID: .myPRSupervisor,
            title: "My PR Action",
            descriptionMd: "Action 1",
            controls: []
        )
        let action2 = ScheduledJobAction(
            id: "shared-id",
            jobID: .prAutoReview,
            title: "Watched PR Action",
            descriptionMd: "Action 2",
            controls: []
        )
        store.updateScheduledJobFrameworkSnapshot(
            ScheduledJobFrameworkSnapshot(
                capturedAt: .now,
                entries: [
                    ScheduledJobFrameworkEntry(definition: ScheduledPulseRegistry.jobs[0], state: nil, actions: [action1]),
                    ScheduledJobFrameworkEntry(definition: ScheduledPulseRegistry.jobs[1], state: nil, actions: [action2])
                ]
            )
        )
        store.acknowledgeScheduledAction(action1, responses: [])
        #expect(store.scheduledJobFrameworkSnapshot.unacknowledgedActions.map(\.jobID) == [.prAutoReview])
    }

    @Test("singleSelect control resolves to first option when user has not explicitly mutated values")
    func singleSelectResolvesDefaultFirstOption() {
        let action = ScheduledJobAction(
            id: "act-select",
            jobID: .prAutoReview,
            title: "Choose strategy",
            descriptionMd: "Select an action",
            controls: [
                ScheduledJobActionControl(
                    id: "strategy",
                    kind: .singleSelect,
                    title: "Strategy",
                    options: ["Re-run CI", "Skip", "Escalate"]
                ),
                ScheduledJobActionControl(
                    id: "confirm",
                    kind: .confirm,
                    title: "Confirm"
                )
            ]
        )
        let defaultResponses = action.resolvedResponses(values: [:], selectedValues: [:])
        #expect(defaultResponses == [
            ScheduledJobActionResponse(controlID: "strategy", value: "Re-run CI"),
            ScheduledJobActionResponse(controlID: "confirm", value: "确认")
        ])

        let explicitResponses = action.resolvedResponses(values: ["strategy": "Escalate"], selectedValues: [:])
        #expect(explicitResponses.first?.value == "Escalate")
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
        #expect(ScheduledJobFrameworkLogic.unacknowledgedActions(from: reader, acknowledgedIDs: ["pr-auto-review:a1"]).isEmpty)
        let reloaded = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
            now: now,
            fileReader: { url in
                if url.lastPathComponent == "state.json" { return stateData }
                if url.lastPathComponent == "actions.jsonl" && url.path.contains("pr-auto-review") { return actionData }
                return nil
            },
            homeURL: home,
            acknowledgedActionIDs: ["pr-auto-review:a1"]
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

    @Test("acknowledged actions disappear before the initial main-window render")
    func initialAcknowledgementFiltering() {
        let store = DashboardWorkspaceStore(snapshot: Self.menuSnapshot())
        let action = ScheduledJobAction(
            id: "initial-action",
            jobID: .myPRSupervisor,
            title: "确认",
            descriptionMd: "确认",
            controls: []
        )
        let definition = ScheduledPulseRegistry.jobs[0]
        store.updateScheduledJobFrameworkSnapshot(
            ScheduledJobFrameworkSnapshot(
                capturedAt: .now,
                entries: [ScheduledJobFrameworkEntry(definition: definition, state: nil, actions: [action])]
            )
        )
        store.acknowledgedScheduledActionIDs = ["my-pr-supervisor:initial-action"]
        #expect(store.scheduledJobFrameworkSnapshot.unacknowledgedActions.isEmpty)
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
