import SwiftUI

struct AIDashTelemetrySettingsView: View {
    let coordinator: AIDashTelemetryCoordinator
    @State private var isEnabled: Bool

    init(coordinator: AIDashTelemetryCoordinator) {
        self.coordinator = coordinator
        _isEnabled = State(initialValue: coordinator.isConsentEnabled)
    }

    var body: some View {
        Toggle(
            String(
                localized: "telemetry.settings.send_usage_data",
                defaultValue: "Send usage data",
                bundle: .main,
                comment: "The sole opt-in control for anonymous product telemetry."
            ),
            isOn: $isEnabled
        )
        .onChange(of: isEnabled) { _, enabled in
            Task {
                await coordinator.setConsent(enabled)
                isEnabled = coordinator.isConsentEnabled
            }
        }
    }
}
