import Foundation

enum AIDashTelemetryAction: String, Sendable {
    case briefingViewed = "briefing_viewed"
}

struct AIDashTelemetryEvent: Equatable, Sendable {
    let name: String
    let properties: [String: String]
    let timestamp: Date

    static func action(_ action: AIDashTelemetryAction, timestamp: Date) -> Self {
        AIDashTelemetryEvent(
            name: "aidash.action",
            properties: ["action_name": action.rawValue],
            timestamp: timestamp
        )
    }

    static func readyScene(durationMilliseconds: Int64, timestamp: Date) -> Self {
        AIDashTelemetryEvent(
            name: "aidash.performance.ready_scene",
            properties: ["duration_ms": String(durationMilliseconds)],
            timestamp: timestamp
        )
    }
}

@MainActor
final class AIDashTelemetryCoordinator {
    private let preferences: AIDashTelemetryPreferences
    private let configuration: AIDashTelemetryHostConfiguration
    private let factory: AIDashTelemetryFactory
    private let mode: RunMode
    private let launchStart: Duration?
    private let monotonicNow: () -> Duration
    private let wallNow: () -> Date
    private var service: AIDashTelemetryServicing?
    private var deliveryTask: Task<Void, Never>?
    private var acceptsReadyEvent = false
    private var didRecordReady = false

    init(
        mode: RunMode,
        preferences: AIDashTelemetryPreferences,
        configuration: AIDashTelemetryHostConfiguration,
        factory: AIDashTelemetryFactory = .live,
        launchStart: Duration?,
        monotonicNow: @escaping () -> Duration,
        wallNow: @escaping () -> Date = Date.init
    ) {
        self.mode = mode
        self.preferences = preferences
        self.configuration = configuration
        self.factory = factory
        self.launchStart = launchStart
        self.monotonicNow = monotonicNow
        self.wallNow = wallNow

        guard mode == .gui,
              case .establishedEnabled(let identifier) = preferences.state,
              let service = factory.make(configuration: configuration, installID: identifier),
              launchStart != nil else {
            return
        }
        self.service = service
        acceptsReadyEvent = true
    }

    var preferenceState: AIDashTelemetryPreferenceState {
        preferences.state
    }

    var isConsentEnabled: Bool {
        if case .establishedEnabled = preferences.state {
            return true
        }
        return false
    }

    func setConsent(_ enabled: Bool) async {
        if !enabled {
            _ = preferences.setConsent(false)
            acceptsReadyEvent = false
            service?.isEnabled = false
            let task = deliveryTask
            deliveryTask = nil
            task?.cancel()
            await task?.value
            return
        }

        guard mode == .gui else { return }
        let state = preferences.setConsent(true)
        guard case .establishedEnabled(let identifier) = state else { return }
        if let service {
            service.isEnabled = true
            resumeDelivery(using: service)
        } else {
            service = factory.make(configuration: configuration, installID: identifier)
            if let service {
                resumeDelivery(using: service)
            }
        }
    }

    func readySceneAppeared() {
        guard acceptsReadyEvent,
              !didRecordReady,
              isConsentEnabled,
              let launchStart,
              let service,
              let milliseconds = Self.completeMilliseconds(monotonicNow() - launchStart) else {
            return
        }
        didRecordReady = true
        let timestamp = wallNow()
        service.track(.action(.briefingViewed, timestamp: timestamp))
        service.track(.readyScene(durationMilliseconds: milliseconds, timestamp: timestamp))
        deliveryTask = Task { await service.flush() }
    }

    func awaitDelivery() async {
        await deliveryTask?.value
    }

    private func resumeDelivery(using service: AIDashTelemetryServicing) {
        deliveryTask?.cancel()
        deliveryTask = Task { await service.flush() }
    }

    private static func completeMilliseconds(_ duration: Duration) -> Int64? {
        let components = duration.components
        guard components.seconds >= 0, components.attoseconds >= 0 else { return nil }
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000)
        guard !seconds.overflow else { return nil }
        let milliseconds = Int64(components.attoseconds / 1_000_000_000_000_000)
        let total = seconds.partialValue.addingReportingOverflow(milliseconds)
        return total.overflow ? nil : total.partialValue
    }
}
