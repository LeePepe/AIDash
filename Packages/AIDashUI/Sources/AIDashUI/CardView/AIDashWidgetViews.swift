import Foundation
import SwiftUI
import AIDashCore
import DesignKit

public enum AIDashWidgetFamily: String, Sendable, Equatable, CaseIterable {
    case needsPersonLinear
    case efficiencyTime
    case spendQuota
    case macCockpit
}

@MainActor
public struct NeedsPersonLinearWidgetView: View {
    public let snapshot: WidgetBriefingSnapshot
    @Environment(\.theme) private var theme

    public init(snapshot: WidgetBriefingSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                HStack {
                    Text(String(localized: "widgets.needs_person.title", defaultValue: "Needs a Person", bundle: .module))
                        .font(AIDashTypography.section)
                        .foregroundStyle(theme.neutrals.text1)
                    Spacer(minLength: 0)
                    StatusPill(
                        snapshot.needsPersonCount == 0 ? "0 blocking" : "\(snapshot.needsPersonCount) blocking",
                        tone: snapshot.needsPersonCount == 0 ? .success : .warning
                    )
                }
                ForEach(snapshot.topActions.prefix(2)) { action in
                    CardInner {
                        VStack(alignment: .leading, spacing: AIDashSpace.s4) {
                            Text(action.title)
                                .font(AIDashTypography.detail(for: .todoList).primary)
                                .foregroundStyle(theme.neutrals.text1)
                                .lineLimit(2)
                            if let waitingOn = action.waitingOn {
                                Text(waitingOn)
                                    .font(AIDashTypography.detail(for: .todoList).secondary)
                                    .foregroundStyle(theme.neutrals.text2)
                            }
                        }
                    }
                }
                HStack(spacing: AIDashSpace.s4) {
                    Text(String(localized: "widgets.completed_goals", defaultValue: "Yesterday completed", bundle: .module))
                    Text("\(snapshot.completedGoalsCount)")
                        .monospacedDigit()
                }
                .font(AIDashTypography.detail(for: .todoList).secondary)
                .foregroundStyle(theme.neutrals.text2)
            }
        }
    }
}

@MainActor
public struct EfficiencyTimeWidgetView: View {
    public let snapshot: WidgetBriefingSnapshot
    @Environment(\.theme) private var theme

    public init(snapshot: WidgetBriefingSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AIDashSpace.s12) {
                Text(String(localized: "widgets.efficiency.title", defaultValue: "Efficiency & 4-Stage Time", bundle: .module))
                    .font(AIDashTypography.section)
                    .foregroundStyle(theme.neutrals.text1)
                HStack(alignment: .top, spacing: AIDashSpace.s16) {
                    metricRing(snapshot.ftrPercent, label: "FTR")
                    metricRing(snapshot.ciPassRate, label: "CI")
                    if let breakdown = snapshot.timeBreakdown {
                        VStack(alignment: .leading, spacing: AIDashSpace.s4) {
                            Text("\(Int(breakdown.leadTimeMinutesP50))m P50")
                                .font(AIDashTypography.detail(for: .hourlyTimeline).primary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            timeRow("Agent", breakdown.agentMinutes)
                            timeRow("Model", breakdown.modelMinutes)
                            timeRow("CI", breakdown.ciMinutes)
                            timeRow("Wait", breakdown.waitMinutes)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metricRing(_ value: Double?, label: String) -> some View {
        VStack(spacing: AIDashSpace.s4) {
            RingGauge(value: (value ?? 0) / 100, color: theme.primary.primary)
            Text(label)
                .font(AIDashTypography.detail(for: .metric).secondary)
                .foregroundStyle(theme.neutrals.text2)
        }
    }

    private func timeRow(_ label: String, _ minutes: Double) -> some View {
        HStack(spacing: AIDashSpace.s4) {
            Text(label)
            Spacer(minLength: AIDashSpace.s4)
            Text("\(Int(minutes))m").monospacedDigit()
        }
        .font(AIDashTypography.detail(for: .metric).secondary)
        .foregroundStyle(theme.neutrals.text2)
    }
}

@MainActor
public struct SpendQuotaWidgetView: View {
    public let snapshot: WidgetBriefingSnapshot
    @Environment(\.theme) private var theme

    public init(snapshot: WidgetBriefingSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                Text(String(localized: "widgets.spend.title", defaultValue: "Spend, ROI & Quota Gauge", bundle: .module))
                    .font(AIDashTypography.section)
                    .foregroundStyle(theme.neutrals.text1)
                HStack(spacing: AIDashSpace.s16) {
                    metric("$\(String(format: "%.2f", snapshot.dailySpendUSD ?? 0))", label: "Yesterday")
                    metric("$\(String(format: "%.2f", snapshot.costPerCompletedTask ?? 0))", label: "$/Issue")
                    metric("\(String(format: "%.1f", snapshot.cacheHitPct ?? 0))%", label: "Cache Hit")
                }
                Sparkline(
                    data: [0, snapshot.dailySpendUSD ?? 0],
                    color: theme.primary.primary
                )
                ForEach(snapshot.quotas) { quota in
                    VStack(alignment: .leading, spacing: AIDashSpace.s4) {
                        HStack {
                            Text(quota.provider)
                            Spacer(minLength: AIDashSpace.s4)
                            Text("\(quota.remainingPercent)%").monospacedDigit()
                        }
                        .font(AIDashTypography.detail(for: .metric).secondary)
                        .foregroundStyle(theme.neutrals.text2)
                        SegmentedGauge(value: Double(quota.remainingPercent) / 100, color: theme.primary.primary)
                    }
                }
            }
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s4) {
            Text(value)
                .font(AIDashTypography.detail(for: .barList).primary)
                .monospacedDigit()
                .foregroundStyle(theme.neutrals.text1)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(label)
                .font(AIDashTypography.detail(for: .metric).secondary)
                .foregroundStyle(theme.neutrals.text2)
        }
    }
}

@MainActor
public struct MacSiliconCockpitWidgetView: View {
    public let snapshot: WidgetSystemSnapshot
    @Environment(\.theme) private var theme

    public init(snapshot: WidgetSystemSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                HStack {
                    Text(snapshot.chipSummary)
                        .font(AIDashTypography.mastheadStatus)
                    Spacer(minLength: AIDashSpace.s4)
                    Text(snapshot.powerThermalSummary)
                        .font(AIDashTypography.detail(for: .metric).secondary)
                        .foregroundStyle(theme.neutrals.text2)
                }
                HStack(alignment: .top, spacing: AIDashSpace.s16) {
                    VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                        instrument("CPU (P+E)", value: "\(Int(snapshot.cpuUsage))%")
                        instrument("GPU", value: "\(Int(snapshot.gpuUsage))% · \(snapshot.vramSummary)")
                        if let process = snapshot.topCPUProcess {
                            instrument("Top CPU", value: process)
                        }
                    }
                    VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                        instrument("Memory", value: "\(Int(snapshot.memoryUsage))% · \(snapshot.memorySummary)")
                        if let process = snapshot.topMemoryProcess {
                            instrument("Top Mem", value: process)
                        }
                        HStack(spacing: AIDashSpace.s4) {
                            gateway("M", isUp: snapshot.magpieUp)
                            gateway("R", isUp: snapshot.ravenUp)
                            gateway("F", isUp: snapshot.falconUp)
                        }
                    }
                }
                if let ttftSummary = snapshot.ttftSummary {
                    Text(ttftSummary)
                        .font(AIDashTypography.detail(for: .metric).secondary)
                        .foregroundStyle(theme.neutrals.text2)
                }
            }
        }
    }

    private func instrument(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s2) {
            Text(label)
                .font(AIDashTypography.detail(for: .metric).secondary)
                .foregroundStyle(theme.neutrals.text2)
            Text(value)
                .font(AIDashTypography.detail(for: .agentSummary).primary)
                .monospacedDigit()
                .foregroundStyle(theme.neutrals.text1)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func gateway(_ label: String, isUp: Bool) -> some View {
        StatusPill("\(label) \(isUp ? "UP" : "DOWN")", tone: isUp ? .success : .danger)
    }
}
