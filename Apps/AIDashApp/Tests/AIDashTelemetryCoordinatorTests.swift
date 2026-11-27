import Foundation
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@Suite("AIDash telemetry coordinator")
@MainActor
struct AIDashTelemetryCoordinatorTests {
    private func defaults() -> UserDefaults {
        let name = "AIDashTelemetryCoordinatorTests.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: name)!
        value.removePersistentDomain(forName: name)
        return value
    }

    private func validConfiguration() -> AIDashTelemetryHostConfiguration {
        AIDashTelemetryHostConfiguration(
            endpoint: "https://example.invalid/container",
            sas: "sv=neutral&sr=c&sp=c&sig=value",
            app: "aidash",
            build: "1"
        )
    }

    @Test("eligible GUI emits exact typed events once with complete monotonic milliseconds")
    func readyEvents() async {
        let defaults = defaults()
        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: "telemetry.installID")
        defaults.set(true, forKey: "telemetry.identityEstablished")
        defaults.set(true, forKey: "telemetry.sendUsageData")
        let service = TelemetryServiceSpy()
        var now = Duration.milliseconds(2_250)
        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: defaults, uuidGenerator: UUID.init),
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory { _ in service },
            launchStart: .seconds(1),
            monotonicNow: { now },
            wallNow: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        coordinator.readySceneAppeared()
        coordinator.readySceneAppeared()
        await coordinator.awaitDelivery()

        #expect(service.events.count == 2)
        #expect(service.events[0].name == "aidash.action")
        #expect(service.events[0].properties == ["action_name": "briefing_viewed"])
        #expect(service.events[1].name == "aidash.performance.ready_scene")
        #expect(service.events[1].properties == ["duration_ms": "1250"])
        #expect(service.flushCount == 1)
        now = .milliseconds(4_000)
        coordinator.readySceneAppeared()
        #expect(service.events.count == 2)
    }

    @Test("negative and overflowing elapsed durations are rejected")
    func invalidReadyDurations() {
        for readyTime in [Duration.milliseconds(-1), Duration.seconds(Int64.max)] {
            let preferenceDefaults = defaults()
            let identifier = UUID()
            preferenceDefaults.set(identifier.uuidString, forKey: "telemetry.installID")
            preferenceDefaults.set(true, forKey: "telemetry.identityEstablished")
            preferenceDefaults.set(true, forKey: "telemetry.sendUsageData")
            let service = TelemetryServiceSpy()
            let coordinator = AIDashTelemetryCoordinator(
                mode: .gui,
                preferences: AIDashTelemetryPreferences(
                    defaults: preferenceDefaults,
                    uuidGenerator: UUID.init
                ),
                configuration: validConfiguration(),
                factory: AIDashTelemetryFactory { _ in service },
                launchStart: .zero,
                monotonicNow: { readyTime }
            )

            coordinator.readySceneAppeared()

            #expect(service.events.isEmpty)
            #expect(service.flushCount == 0)
        }
    }

    @Test("disabled modes and mid-lifecycle opt-in never emit retrospective events")
    func disabledModesAndLateOptIn() async {
        for mode in [RunMode.agent, .testHost] {
            var constructions = 0
            let coordinator = AIDashTelemetryCoordinator(
                mode: mode,
                preferences: AIDashTelemetryPreferences(defaults: defaults(), uuidGenerator: UUID.init),
                configuration: validConfiguration(),
                factory: AIDashTelemetryFactory { _ in
                    constructions += 1
                    return TelemetryServiceSpy()
                },
                launchStart: nil,
                monotonicNow: { .zero }
            )
            coordinator.readySceneAppeared()
            #expect(constructions == 0)
        }

        let preferenceDefaults = defaults()
        var generated = 0
        let service = TelemetryServiceSpy()
        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: preferenceDefaults) {
                generated += 1
                return UUID()
            },
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory { _ in service },
            launchStart: .zero,
            monotonicNow: { .milliseconds(10) }
        )
        coordinator.readySceneAppeared()
        await coordinator.setConsent(true)
        coordinator.readySceneAppeared()
        #expect(generated == 1)
        #expect(service.events.isEmpty)
    }

    @Test("disable closes admission, retains identity, and re-enable reuses it")
    func disableAndReenable() async {
        let preferenceDefaults = defaults()
        let identifier = UUID()
        preferenceDefaults.set(identifier.uuidString, forKey: "telemetry.installID")
        preferenceDefaults.set(true, forKey: "telemetry.identityEstablished")
        preferenceDefaults.set(true, forKey: "telemetry.sendUsageData")
        let service = TelemetryServiceSpy()
        var constructedIDs: [UUID] = []
        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: preferenceDefaults) {
                Issue.record("established state must never generate a replacement ID")
                return UUID()
            },
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory {
                constructedIDs.append($0.installID)
                return service
            },
            launchStart: .zero,
            monotonicNow: { .milliseconds(5) }
        )

        await coordinator.setConsent(false)
        #expect(!service.isEnabled)
        #expect(preferenceDefaults.bool(forKey: "telemetry.sendUsageData") == false)
        #expect(preferenceDefaults.string(forKey: "telemetry.installID") == identifier.uuidString)
        #expect(preferenceDefaults.bool(forKey: "telemetry.identityEstablished"))

        await coordinator.setConsent(true)
        #expect(service.isEnabled)
        #expect(constructedIDs == [identifier])
        #expect(preferenceDefaults.string(forKey: "telemetry.installID") == identifier.uuidString)
    }

    @Test("cold-start established-disabled re-enable reuses retained identity")
    func coldStartDisabledReenable() async {
        let preferenceDefaults = defaults()
        let identifier = UUID()
        preferenceDefaults.set(identifier.uuidString, forKey: "telemetry.installID")
        preferenceDefaults.set(true, forKey: "telemetry.identityEstablished")
        preferenceDefaults.set(false, forKey: "telemetry.sendUsageData")
        var generated = 0
        var constructedIDs: [UUID] = []
        let service = TelemetryServiceSpy()
        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: preferenceDefaults) {
                generated += 1
                return UUID()
            },
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory {
                constructedIDs.append($0.installID)
                return service
            },
            launchStart: .zero,
            monotonicNow: { .milliseconds(5) }
        )

        #expect(constructedIDs.isEmpty)
        await coordinator.setConsent(true)
        await coordinator.awaitDelivery()

        #expect(generated == 0)
        #expect(constructedIDs == [identifier])
        #expect(service.flushCount == 1)
        #expect(preferenceDefaults.string(forKey: "telemetry.installID") == identifier.uuidString)
    }

    @Test("re-enable resumes retained delivery without identity rotation or retrospective events")
    func reenableResumesRetainedDelivery() async {
        let preferenceDefaults = defaults()
        let identifier = UUID()
        preferenceDefaults.set(identifier.uuidString, forKey: "telemetry.installID")
        preferenceDefaults.set(true, forKey: "telemetry.identityEstablished")
        preferenceDefaults.set(true, forKey: "telemetry.sendUsageData")
        var generated = 0
        let service = TelemetryServiceSpy()
        service.flushHandler = {
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        var constructedIDs: [UUID] = []
        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: preferenceDefaults) {
                generated += 1
                return UUID()
            },
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory {
                constructedIDs.append($0.installID)
                return service
            },
            launchStart: .zero,
            monotonicNow: { .milliseconds(5) }
        )

        coordinator.readySceneAppeared()
        while service.flushCount == 0 {
            await Task.yield()
        }
        await coordinator.setConsent(false)
        let originalEvents = service.events
        service.flushHandler = nil

        await coordinator.setConsent(true)
        await coordinator.awaitDelivery()
        coordinator.readySceneAppeared()

        #expect(service.flushCount == 2)
        #expect(service.events == originalEvents)
        #expect(service.events.count == 2)
        #expect(constructedIDs == [identifier])
        #expect(generated == 0)
        #expect(preferenceDefaults.string(forKey: "telemetry.installID") == identifier.uuidString)
    }

    @Test("rapid off-on waits for cancelled delivery before retained resume")
    func rapidOffOnSerializesDeliveryGenerations() async {
        let preferenceDefaults = defaults()
        let identifier = UUID()
        preferenceDefaults.set(identifier.uuidString, forKey: "telemetry.installID")
        preferenceDefaults.set(true, forKey: "telemetry.identityEstablished")
        preferenceDefaults.set(true, forKey: "telemetry.sendUsageData")
        var generated = 0
        var cancellationObserved = false
        var allowCancelledGenerationToExit = false
        var order: [String] = []
        var activeWorkers = 0
        var maximumActiveWorkers = 0
        let service = TelemetryServiceSpy()
        service.flushHandler = {
            if service.flushCount == 1 {
                order.append("generation-1-start")
                while !Task.isCancelled {
                    await Task.yield()
                }
                cancellationObserved = true
                order.append("generation-1-cancelled")
                while !allowCancelledGenerationToExit {
                    await Task.yield()
                }
                order.append("generation-1-ended")
            } else {
                order.append("generation-2-start")
            }
        }
        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: preferenceDefaults) {
                generated += 1
                return UUID()
            },
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory { _ in service },
            launchStart: .zero,
            monotonicNow: { .milliseconds(5) },
            reconciliationObserver: { event in
                switch event {
                case .desiredConsentChanged:
                    break
                case .workerStarted:
                    activeWorkers += 1
                    maximumActiveWorkers = max(maximumActiveWorkers, activeWorkers)
                case .workerFinished:
                    activeWorkers -= 1
                }
            }
        )

        coordinator.readySceneAppeared()
        while service.flushCount == 0 {
            await Task.yield()
        }
        let disable = Task { await coordinator.setConsent(false) }
        while !cancellationObserved {
            await Task.yield()
        }
        let enable = Task { await coordinator.setConsent(true) }
        await Task.yield()

        #expect(service.flushCount == 1)
        #expect(!service.isEnabled)
        allowCancelledGenerationToExit = true
        await disable.value
        await enable.value
        await coordinator.awaitDelivery()

        #expect(service.flushCount == 2)
        #expect(order == [
            "generation-1-start",
            "generation-1-cancelled",
            "generation-1-ended",
            "generation-2-start",
        ])
        #expect(service.isEnabled)
        #expect(generated == 0)
        #expect(maximumActiveWorkers == 1)
        #expect(activeWorkers == 0)
        #expect(preferenceDefaults.string(forKey: "telemetry.installID") == identifier.uuidString)
    }

    @Test("latest opt-out suppresses an older queued opt-in")
    func rapidOffOnOffSuppressesStaleEnable() async {
        let preferenceDefaults = defaults()
        let identifier = UUID()
        preferenceDefaults.set(identifier.uuidString, forKey: "telemetry.installID")
        preferenceDefaults.set(true, forKey: "telemetry.identityEstablished")
        preferenceDefaults.set(true, forKey: "telemetry.sendUsageData")
        var cancellationObserved = false
        var allowCancelledGenerationToExit = false
        var observedIntermediateEnable = false
        var observedFinalDisable = false
        var activeWorkers = 0
        var maximumActiveWorkers = 0
        var factoryCalls = 0
        let service = TelemetryServiceSpy()
        service.flushHandler = {
            if service.flushCount == 1 {
                while !Task.isCancelled {
                    await Task.yield()
                }
                cancellationObserved = true
                while !allowCancelledGenerationToExit {
                    await Task.yield()
                }
            } else {
                Issue.record("stale opt-in must not start another delivery generation")
            }
        }
        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: preferenceDefaults) {
                Issue.record("established state must never generate a replacement ID")
                return UUID()
            },
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory { _ in
                factoryCalls += 1
                return service
            },
            launchStart: .zero,
            monotonicNow: { .milliseconds(5) },
            reconciliationObserver: { event in
                switch event {
                case .desiredConsentChanged(true):
                    observedIntermediateEnable = true
                case .desiredConsentChanged(false):
                    if observedIntermediateEnable {
                        observedFinalDisable = true
                    }
                case .workerStarted:
                    activeWorkers += 1
                    maximumActiveWorkers = max(maximumActiveWorkers, activeWorkers)
                case .workerFinished:
                    activeWorkers -= 1
                }
            }
        )

        coordinator.readySceneAppeared()
        while service.flushCount == 0 {
            await Task.yield()
        }
        let initialEvents = service.events
        let firstDisable = Task { await coordinator.setConsent(false) }
        while !cancellationObserved {
            await Task.yield()
        }
        let staleEnable = Task { await coordinator.setConsent(true) }
        while !observedIntermediateEnable {
            await Task.yield()
        }
        let latestDisable = Task { await coordinator.setConsent(false) }
        while !observedFinalDisable {
            await Task.yield()
        }

        #expect(!service.isEnabled)
        #expect(!preferenceDefaults.bool(forKey: "telemetry.sendUsageData"))
        #expect(maximumActiveWorkers == 1)
        #expect(activeWorkers == 1)
        allowCancelledGenerationToExit = true
        await firstDisable.value
        await staleEnable.value
        await latestDisable.value
        await coordinator.awaitDelivery()
        coordinator.readySceneAppeared()

        #expect(service.flushCount == 1)
        #expect(service.events == initialEvents)
        #expect(factoryCalls == 1)
        #expect(!coordinator.isConsentEnabled)
        #expect(!service.isEnabled)
        #expect(!preferenceDefaults.bool(forKey: "telemetry.sendUsageData"))
        #expect(maximumActiveWorkers == 1)
        #expect(activeWorkers == 0)
        #expect(preferenceDefaults.string(forKey: "telemetry.installID") == identifier.uuidString)
        #expect(preferenceDefaults.bool(forKey: "telemetry.identityEstablished"))
    }

    @Test("settings authority is present only for non-headless GUI composition")
    func settingsAuthorityPlacement() {
        #expect(AIDashTelemetrySettingsPlacement.isAvailable(headless: false, hasCoordinator: true))
        #expect(!AIDashTelemetrySettingsPlacement.isAvailable(headless: true, hasCoordinator: true))
        #expect(!AIDashTelemetrySettingsPlacement.isAvailable(headless: false, hasCoordinator: false))
    }

    @Test("invalid established state and invalid config construct nothing")
    func invalidStateAndConfig() async {
        let preferenceDefaults = defaults()
        preferenceDefaults.set(true, forKey: "telemetry.identityEstablished")
        preferenceDefaults.set(true, forKey: "telemetry.sendUsageData")
        var constructions = 0
        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: preferenceDefaults) {
                Issue.record("invalid established state must not generate")
                return UUID()
            },
            configuration: AIDashTelemetryHostConfiguration(
                endpoint: nil,
                sas: nil,
                app: "aidash",
                build: "1"
            ),
            factory: AIDashTelemetryFactory { _ in
                constructions += 1
                return TelemetryServiceSpy()
            },
            launchStart: .zero,
            monotonicNow: { .zero }
        )

        await coordinator.setConsent(true)
        coordinator.readySceneAppeared()
        #expect(constructions == 0)
        #expect(coordinator.preferenceState == .establishedInvalid)
    }

    @Test("scrollHitchSession emits typed event, enforces thresholds and section allowlist, and writes local JSONL")
    func scrollHitchSessionTelemetryAndMonitor() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-scroll-telemetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let logURL = tempDir.appendingPathComponent(".aidash-state/scroll-telemetry.jsonl")

        let preferenceDefaults = defaults()
        let identifier = UUID()
        preferenceDefaults.set(identifier.uuidString, forKey: "telemetry.installID")
        preferenceDefaults.set(true, forKey: "telemetry.identityEstablished")
        preferenceDefaults.set(true, forKey: "telemetry.sendUsageData")
        let service = TelemetryServiceSpy()
        let fixedWall = Date(timeIntervalSince1970: 1_764_246_000)

        let coordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: preferenceDefaults, uuidGenerator: UUID.init),
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory { _ in service },
            launchStart: .zero,
            monotonicNow: { .milliseconds(100) },
            wallNow: { fixedWall },
            scrollLogFileURL: logURL
        )

        // Zero hitches, negative durations, and unknown sections are ignored
        coordinator.recordScrollHitchSession(
            section: "goalWorkStream",
            hitchCount: 0,
            severeHitchCount: 0,
            maxFrameMilliseconds: 16,
            durationMilliseconds: 420
        )
        coordinator.recordScrollHitchSession(
            section: "unknown-free-text-section",
            hitchCount: 2,
            severeHitchCount: 1,
            maxFrameMilliseconds: 120,
            durationMilliseconds: 420
        )
        coordinator.recordScrollHitchSession(
            section: "goalWorkStream",
            hitchCount: 1,
            severeHitchCount: 2,
            maxFrameMilliseconds: 120,
            durationMilliseconds: 420
        )
        #expect(service.events.isEmpty)

        // Monitor samples >33ms as hitch and >100ms as severe hitch
        var clockMs: Int64 = 0
        var recordedSummaries: [AIDashScrollHitchSessionSummary] = []
        let monitor = AIDashScrollHitchMonitor(
            monotonicNow: { .milliseconds(clockMs) },
            onSessionCompleted: { summary in
                recordedSummaries.append(summary)
                coordinator.recordScrollHitchSession(
                    section: summary.section,
                    hitchCount: summary.hitchCount,
                    severeHitchCount: summary.severeHitchCount,
                    maxFrameMilliseconds: summary.maxFrameMilliseconds,
                    durationMilliseconds: summary.durationMilliseconds
                )
            }
        )

        monitor.beginScroll(section: "goalWorkStream", startSamplingLoop: false)
        clockMs += 16
        monitor.sampleFrame() // 16ms: smooth
        clockMs += 45
        monitor.sampleFrame() // 45ms: hitch (>33ms)
        clockMs += 118
        monitor.sampleFrame() // 118ms: hitch + severe hitch (>100ms)
        clockMs += 16
        let summary = try #require(monitor.endScroll())

        #expect(summary.section == "goalWorkStream")
        #expect(summary.hitchCount == 2)
        #expect(summary.severeHitchCount == 1)
        #expect(summary.maxFrameMilliseconds == 118)
        #expect(summary.durationMilliseconds == 195)
        #expect(recordedSummaries == [summary])

        await coordinator.awaitDelivery()
        await coordinator.awaitScrollLogWrites()

        #expect(service.events.count == 1)
        let emitted = try #require(service.events.first)
        #expect(emitted.name == "aidash.performance.scroll_hitch")
        #expect(emitted.timestamp == fixedWall)
        #expect(emitted.properties == [
            "section": "goalWorkStream",
            "hitch_count": "2",
            "severe_hitch_count": "1",
            "max_frame_ms": "118",
            "duration_ms": "195",
        ])
        #expect(service.flushCount == 1)

        // Never-opted coordinator must neither emit events nor create local scroll telemetry storage
        let neverOptedLogURL = tempDir.appendingPathComponent("never-opted/.aidash-state/scroll-telemetry.jsonl")
        let neverOptedCoordinator = AIDashTelemetryCoordinator(
            mode: .gui,
            preferences: AIDashTelemetryPreferences(defaults: defaults(), uuidGenerator: UUID.init),
            configuration: validConfiguration(),
            factory: AIDashTelemetryFactory { _ in TelemetryServiceSpy() },
            launchStart: .zero,
            monotonicNow: { .milliseconds(50) },
            wallNow: { fixedWall },
            scrollLogFileURL: neverOptedLogURL
        )
        neverOptedCoordinator.recordScrollHitchSession(
            section: "overview",
            hitchCount: 3,
            severeHitchCount: 1,
            maxFrameMilliseconds: 112,
            durationMilliseconds: 250
        )
        await neverOptedCoordinator.awaitScrollLogWrites()
        #expect(!FileManager.default.fileExists(atPath: neverOptedLogURL.path))

        // When consent is disabled, admission closes immediately for both remote service and local JSONL while retaining prior records
        await coordinator.setConsent(false)
        coordinator.recordScrollHitchSession(
            section: "agentEfficiency",
            hitchCount: 1,
            severeHitchCount: 0,
            maxFrameMilliseconds: 48,
            durationMilliseconds: 310
        )
        await coordinator.awaitScrollLogWrites()
        #expect(service.events.count == 1)

        let logLines = try String(contentsOf: logURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        #expect(logLines.count == 1)
        let firstObj = try #require(JSONSerialization.jsonObject(with: Data(logLines[0].utf8)) as? [String: Any])
        #expect(firstObj["name"] as? String == "aidash.performance.scroll_hitch")
        let firstProps = try #require(firstObj["properties"] as? [String: String])
        #expect(firstProps["section"] == "goalWorkStream")
        #expect(firstProps["max_frame_ms"] == "118")

        // Re-enabling consent admits subsequent scroll hitch sessions again
        await coordinator.setConsent(true)
        coordinator.recordScrollHitchSession(
            section: "agentEfficiency",
            hitchCount: 1,
            severeHitchCount: 0,
            maxFrameMilliseconds: 48,
            durationMilliseconds: 310
        )
        await coordinator.awaitDelivery()
        await coordinator.awaitScrollLogWrites()
        #expect(service.events.count == 2)
        let updatedLines = try String(contentsOf: logURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        #expect(updatedLines.count == 2)

        // XCTest environment guard returns nil default path so tests never touch live ~/.aidash-state
        #expect(AIDashTelemetryCoordinator.defaultScrollLogFileURL(environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]) == nil)
        #expect(AIDashTelemetryCoordinator.defaultScrollLogFileURL(environment: [:])?.path.hasSuffix("/.aidash-state/scroll-telemetry.jsonl") == true)
    }
}
