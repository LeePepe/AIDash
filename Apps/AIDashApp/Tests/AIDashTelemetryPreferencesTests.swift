import Foundation
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@Suite("AIDash telemetry preferences")
@MainActor
struct AIDashTelemetryPreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let name = "AIDashTelemetryPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("never opted is off and first opt-in creates exactly one lifetime ID")
    func firstOptInAndLifetimeReuse() {
        let defaults = makeDefaults()
        var generated = 0
        let expected = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let preferences = AIDashTelemetryPreferences(defaults: defaults) {
            generated += 1
            return expected
        }

        #expect(preferences.state == .neverOpted)
        #expect(preferences.setConsent(true) == .establishedEnabled(expected))
        #expect(generated == 1)
        #expect(defaults.string(forKey: "telemetry.installID") == expected.uuidString)
        #expect(defaults.bool(forKey: "telemetry.identityEstablished"))
        #expect(defaults.bool(forKey: "telemetry.sendUsageData"))

        #expect(preferences.setConsent(false) == .establishedDisabled(expected))
        #expect(preferences.setConsent(true) == .establishedEnabled(expected))
        #expect(generated == 1)

        let relaunched = AIDashTelemetryPreferences(defaults: defaults) {
            generated += 1
            return UUID()
        }
        #expect(relaunched.state == .establishedEnabled(expected))
        #expect(generated == 1)
    }

    @Test("every inconsistent established identity fails closed without replacement")
    func invalidStateMatrix() {
        let malformedValues: [(Any?, Any?, Any?)] = [
            (true, nil, true),
            ("true", nil, true),
            (true, "not-a-uuid", false),
            (false, UUID().uuidString, false),
            (nil, UUID().uuidString, false),
            (nil, nil, true),
            (false, nil, true),
        ]

        for (marker, identifier, consent) in malformedValues {
            let defaults = makeDefaults()
            if let marker { defaults.set(marker, forKey: "telemetry.identityEstablished") }
            if let identifier { defaults.set(identifier, forKey: "telemetry.installID") }
            if let consent { defaults.set(consent, forKey: "telemetry.sendUsageData") }
            var generated = 0
            let preferences = AIDashTelemetryPreferences(defaults: defaults) {
                generated += 1
                return UUID()
            }

            #expect(preferences.state == .establishedInvalid)
            #expect(preferences.setConsent(true) == .establishedInvalid)
            #expect(generated == 0)
            #expect(defaults.bool(forKey: "telemetry.sendUsageData") == false)
        }
    }

    @Test("missing or malformed consent is disabled after identity establishment")
    func malformedConsentIsOff() {
        for consent in [nil, "yes"] as [Any?] {
            let defaults = makeDefaults()
            let identifier = UUID()
            defaults.set(true, forKey: "telemetry.identityEstablished")
            defaults.set(identifier.uuidString, forKey: "telemetry.installID")
            if let consent { defaults.set(consent, forKey: "telemetry.sendUsageData") }

            #expect(
                AIDashTelemetryPreferences(defaults: defaults, uuidGenerator: UUID.init).state
                    == .establishedDisabled(identifier)
            )
        }
    }
}
