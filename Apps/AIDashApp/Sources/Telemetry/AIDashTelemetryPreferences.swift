import Foundation

enum AIDashTelemetryPreferenceState: Equatable {
    case neverOpted
    case establishedDisabled(UUID)
    case establishedEnabled(UUID)
    case establishedInvalid
}

@MainActor
final class AIDashTelemetryPreferences {
    private enum Key {
        static let consent = "telemetry.sendUsageData"
        static let installID = "telemetry.installID"
        static let identityEstablished = "telemetry.identityEstablished"
    }

    private let defaults: UserDefaults
    private let uuidGenerator: () -> UUID

    init(
        defaults: UserDefaults = .standard,
        uuidGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.defaults = defaults
        self.uuidGenerator = uuidGenerator
    }

    var state: AIDashTelemetryPreferenceState {
        let markerObject = defaults.object(forKey: Key.identityEstablished)
        let identifierObject = defaults.object(forKey: Key.installID)
        let consent = defaults.object(forKey: Key.consent) as? Bool ?? false

        if markerObject == nil, identifierObject == nil {
            return consent ? .establishedInvalid : .neverOpted
        }
        guard let marker = markerObject as? Bool, marker,
              let identifierString = identifierObject as? String,
              let identifier = UUID(uuidString: identifierString),
              identifier.uuidString == identifierString else {
            return .establishedInvalid
        }
        return consent ? .establishedEnabled(identifier) : .establishedDisabled(identifier)
    }

    @discardableResult
    func setConsent(_ enabled: Bool) -> AIDashTelemetryPreferenceState {
        let currentState = state
        if !enabled {
            defaults.set(false, forKey: Key.consent)
            if currentState == .establishedInvalid {
                preserveInvalidState()
            }
            return state
        }

        switch currentState {
        case .neverOpted:
            let identifier = uuidGenerator()
            defaults.set(identifier.uuidString, forKey: Key.installID)
            defaults.set(true, forKey: Key.identityEstablished)
            defaults.set(true, forKey: Key.consent)
        case .establishedDisabled:
            defaults.set(true, forKey: Key.consent)
        case .establishedEnabled:
            break
        case .establishedInvalid:
            preserveInvalidState()
            defaults.set(false, forKey: Key.consent)
        }
        return state
    }

    private func preserveInvalidState() {
        if defaults.object(forKey: Key.identityEstablished) == nil,
           defaults.object(forKey: Key.installID) == nil {
            defaults.set(true, forKey: Key.identityEstablished)
        }
    }
}
