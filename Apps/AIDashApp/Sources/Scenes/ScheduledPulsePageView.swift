#if os(macOS)
import SwiftUI

@MainActor
public struct ScheduledPulsePageView: View {
    @Bindable public var store: DashboardWorkspaceStore
    @State private var copiedJobID: ScheduledPulseJobID?

    public init(store: DashboardWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            kpiStrip
            jobBoard
            inspector
        }
        .accessibilityElement(children: .contain)
    }

    private var kpiStrip: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.title", "Scheduled Pulse"),
            subtitle: DashboardL10n.tr("dashboard.scheduled_pulse.subtitle", "Local scheduled jobs · read-only"),
            symbolName: DashboardWorkspaceSection.scheduledPulse.symbolName
        ) {
            HStack(spacing: 12) {
                pulseKPICell(
                    metric: .enabled,
                    label: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.enabled", "Enabled"),
                    value: "\(enabledCount) / \(ScheduledPulseRegistry.liveJobs.count)"
                )
                pulseKPICell(
                    metric: .unhealthy,
                    label: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.unhealthy", "Unhealthy"),
                    value: "\(store.scheduledPulseUnhealthyCount)"
                )
                pulseKPICell(
                    metric: .lastTick,
                    label: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.last_tick", "Last tick"),
                    value: lastTickText
                )
            }
        }
    }

    private var jobBoard: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.scheduled_pulse.board.title", "Job board"),
            subtitle: DashboardL10n.tr("dashboard.scheduled_pulse.board.subtitle", "AIDash-owned schedulers"),
            symbolName: "list.bullet.rectangle"
        ) {
            HStack(spacing: 10) {
                Picker(
                    DashboardL10n.tr("dashboard.scheduled_pulse.filter.scheduler_label", "Scheduler"),
                    selection: $store.scheduledPulseSchedulerFilter
                ) {
                    ForEach(ScheduledPulseSchedulerFilter.allCases) { filter in
                        Text(filter.displayTitle).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)

                Picker(
                    DashboardL10n.tr("dashboard.scheduled_pulse.filter.health_label", "Health"),
                    selection: $store.scheduledPulseHealthFilter
                ) {
                    ForEach(ScheduledPulseHealthFilter.allCases) { filter in
                        Text(filter.displayTitle).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                boardHeader
                if store.scheduledPulseRows.isEmpty {
                    ContentUnavailableView(
                        DashboardL10n.tr("dashboard.scheduled_pulse.empty.title", "No scheduled jobs"),
                        systemImage: "clock.badge.checkmark",
                        description: Text(DashboardL10n.tr("dashboard.scheduled_pulse.empty.description", "No jobs match the active filters."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 128)
                } else {
                    ForEach(store.scheduledPulseRows) { status in
                        jobRow(status)
                    }
                }
            }
        }
    }

    private var boardHeader: some View {
        HStack(spacing: 12) {
            Text(DashboardL10n.tr("dashboard.scheduled_pulse.column.status", "Status"))
                .frame(width: 110, alignment: .leading)
            Text(DashboardL10n.tr("dashboard.scheduled_pulse.column.name", "Name"))
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            Text(DashboardL10n.tr("dashboard.scheduled_pulse.column.source", "Source"))
                .frame(width: 130, alignment: .leading)
            Text(DashboardL10n.tr("dashboard.scheduled_pulse.column.cadence", "Cadence"))
                .frame(width: 130, alignment: .leading)
            Text(DashboardL10n.tr("dashboard.scheduled_pulse.column.last_run", "Last run"))
                .frame(width: 110, alignment: .leading)
            Text(DashboardL10n.tr("dashboard.scheduled_pulse.column.result", "Result"))
                .frame(width: 150, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private func jobRow(_ status: ScheduledJobStatus) -> some View {
        let isSelected = store.selectedScheduledJobID == status.id
        let tint = DashboardSemanticColorPalette.color(for: status.health.semanticHealth)
        return Button {
            store.selectedScheduledJobID = status.id
        } label: {
            HStack(spacing: 12) {
                statusPill(status)
                    .frame(width: 110, alignment: .leading)
                Text(status.definition.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                Text(status.definition.sourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
                Text(status.cadenceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
                Text(lastRunText(status.lastRun))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                Text(status.resultText)
                    .font(.caption)
                    .foregroundStyle(status.health == .healthy ? .secondary : tint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 150, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(status.definition.displayName), \(status.health.label), \(status.cadenceText)"
        )
    }

    private func statusPill(_ status: ScheduledJobStatus) -> some View {
        let health = status.health.semanticHealth
        let tint = DashboardSemanticColorPalette.color(for: health)
        return HStack(spacing: 5) {
            Image(systemName: health.symbolName)
            Text(status.health.label)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
    }

    private var inspector: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.scheduled_pulse.inspector.title", "Inspector"),
            subtitle: DashboardL10n.tr("dashboard.scheduled_pulse.inspector.subtitle", "Selected job details"),
            symbolName: "info.circle"
        ) {
            if let status = store.selectedScheduledJob {
                inspectorContent(status)
            } else {
                Text(DashboardL10n.tr("dashboard.scheduled_pulse.inspector.empty", "选择一行查看详情"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            }
        }
    }

    private func inspectorContent(_ status: ScheduledJobStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(status.definition.displayName).font(.title3.weight(.semibold))
                statusPill(status)
                Spacer(minLength: 8)
                Text(status.definition.id.rawValue).font(.caption2).monospaced().foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                inspectorValue(
                    label: DashboardL10n.tr("dashboard.scheduled_pulse.inspector.cadence", "Cadence"),
                    value: status.cadenceText
                )
                inspectorValue(
                    label: DashboardL10n.tr("dashboard.scheduled_pulse.inspector.last_run", "Last run"),
                    value: lastRunText(status.lastRun)
                )
                inspectorValue(
                    label: DashboardL10n.tr("dashboard.scheduled_pulse.inspector.result", "Result"),
                    value: status.resultText
                )
            }
            if let lastError = status.lastError, !lastError.isEmpty {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let command = status.definition.commandHint {
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button {
                        store.copyScheduledJobCommand(status)
                        copiedJobID = status.id
                    } label: {
                        Label(
                            copiedJobID == status.id
                                ? DashboardL10n.tr("dashboard.scheduled_pulse.inspector.copied", "Copied")
                                : DashboardL10n.tr("dashboard.scheduled_pulse.inspector.copy", "Copy command hint"),
                            systemImage: copiedJobID == status.id ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func inspectorValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).monospacedDigit().lineLimit(1)
        }
    }

    private func pulseKPICell(metric: ScheduledPulseKPIMetric, label: String, value: String) -> some View {
        Button {
            store.selectScheduledPulseKPI(metric)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(value)")
    }

    private var enabledCount: Int {
        store.scheduledPulseSnapshot.jobs.filter { $0.definition.isLive }.count
    }

    private var lastTickText: String {
        guard let lastTick = store.scheduledPulseLastTick else {
            return DashboardL10n.tr("dashboard.scheduled_pulse.last_tick.never", "—")
        }
        return lastRunText(lastTick)
    }

    private func lastRunText(_ date: Date?) -> String {
        guard let date else {
            return DashboardL10n.tr("dashboard.scheduled_pulse.last_run.never", "—")
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
#endif
