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
}
