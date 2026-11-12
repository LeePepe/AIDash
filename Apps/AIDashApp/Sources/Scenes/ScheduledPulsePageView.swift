#if os(macOS)
import Darwin
import SwiftUI

@MainActor
public struct ScheduledPulsePageView: View {
    @Bindable public var store: DashboardWorkspaceStore
    @State private var installerError: String?

    public init(store: DashboardWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.scheduledJobFrameworkSnapshot.overviewEntries) { entry in
                scheduledJobCard(entry)
            }

            if let installerError {
                Text(installerError)
                    .font(.caption)
                    .foregroundStyle(DashboardSemanticColorPalette.color(for: .critical))
            }
        }
        .onAppear {
            if store.scheduledJobFrameworkSnapshot.entries.isEmpty {
                store.refreshFromProvider()
            }
        }
    }

    private func scheduledJobCard(_ entry: ScheduledJobFrameworkEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            statusPill(entry)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.definition.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.definition.cadence.displayText)
                    Text("·")
                    Text(ScheduledJobTimeFormatting.relativeText(from: entry.lastRunAt ?? entry.lastTick)
                        ?? DashboardL10n.tr("dashboard.scheduled_pulse.time.never", "尚未运行"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let summary = entry.state?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    Text(summary)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                }
            }

            Spacer(minLength: 8)

            if !entry.actions.isEmpty {
                Button {
                    store.selectedFrameworkJobID = entry.id
                    store.selectedSection = .actionItems
                } label: {
                    Label(
                        DashboardL10n.format("dashboard.scheduled_pulse.pending_actions_format", "去待办处理 (%lld)", entry.actions.count),
                        systemImage: "arrow.right"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint(DashboardL10n.tr("dashboard.scheduled_pulse.pending_actions_hint", "打开 Actionable Items"))
            }

            HStack(spacing: 6) {
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.run_now", "立即运行")) {
                    runNow(entry.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.start", "启动")) {
                    handle(store.startScheduledJob(entry.id))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.stop", "停止")) {
                    handle(store.stopScheduledJob(entry.id))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DashboardSemanticColorPalette.color(for: entry.semanticState.semanticHealth))
                .frame(width: 3)
        }
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
    }

    private func statusPill(_ entry: ScheduledJobFrameworkEntry) -> some View {
        Label(statusText(for: entry), systemImage: entry.semanticState.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DashboardSemanticColorPalette.color(for: entry.semanticState.semanticHealth))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .accessibilityElement(children: .combine)
    }

    private func statusText(for entry: ScheduledJobFrameworkEntry) -> String {
        switch entry.semanticState {
        case .coalesced:
            return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.skipped", "已跳过")
        case .noState:
            return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.not_run", "未运行")
        default:
            return entry.statusText
        }
    }

    private func runNow(_ id: ScheduledPulseJobID) {
        guard let definition = ScheduledPulseRegistry.job(for: id) else { return }
        let result = ScheduledPulseLaunchdInstaller.productionLaunchctl([
            "kickstart", "-k", "gui/\(getuid())/\(definition.launchAgentLabel)"
        ])
        if result.succeeded {
            installerError = nil
            store.refreshFromProvider()
        } else {
            installerError = result.diagnosticSummary
        }
    }

    private func handle(_ outcome: ScheduledPulseLaunchdInstaller.RegistrationOutcome) {
        installerError = outcome.failureDescription
        if outcome.isHealthy { store.refreshFromProvider() }
    }
}

#endif
