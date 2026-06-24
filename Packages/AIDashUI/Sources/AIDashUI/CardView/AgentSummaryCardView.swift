import SwiftUI
import AIDashCore

public struct AgentSummaryCardView: View {
    let payload: AgentSummaryPayload
    let size: CardSize
    let style: CardStyle

    public init(payload: AgentSummaryPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundTint, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .small:
            smallLayout
        case .medium:
            mediumLayout
        case .wide:
            wideLayout
        case .hero:
            heroLayout
        }
    }

    // MARK: - Size Layouts

    @ViewBuilder
    private var smallLayout: some View {
        Text(payload.agentName)
            .font(.headline)
            .lineLimit(1)
        if let prStat = payload.stats?.first(where: { $0.label == "PRs" }) {
            Text("\(Int(prStat.value)) PRs")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(payload.completed.count) completed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mediumLayout: some View {
        Text(payload.agentName)
            .font(.headline)
            .lineLimit(1)

        ForEach(Array(payload.completed.prefix(2).enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }

        if let stat = mostRelevantStat {
            Text("\(stat.label): \(formattedStatValue(stat.value))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var wideLayout: some View {
        Text(payload.agentName)
            .font(.headline)
            .lineLimit(1)

        ForEach(Array(payload.completed.prefix(5).enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }

        if let stats = payload.stats, !stats.isEmpty {
            HStack(spacing: 12) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    statBadge(stat)
                }
            }
        }
    }

    @ViewBuilder
    private var heroLayout: some View {
        Text(payload.agentName)
            .font(.title2)
            .fontWeight(.semibold)

        ForEach(Array(payload.completed.enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }

        if let stats = payload.stats, !stats.isEmpty {
            Divider()
            HStack(spacing: 16) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    statBadge(stat)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func completedRow(_ item: AgentSummaryPayload.Completed) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            if let ref = item.ref {
                Link(item.title, destination: URL(string: ref) ?? URL(string: "about:blank")!)
                    .font(.subheadline)
                    .lineLimit(1)
            } else {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func statBadge(_ stat: AgentSummaryPayload.Stat) -> some View {
        VStack(spacing: 2) {
            Text(formattedStatValue(stat.value))
                .font(.headline)
            Text(stat.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var mostRelevantStat: AgentSummaryPayload.Stat? {
        payload.stats?.first
    }

    private func formattedStatValue(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private var backgroundTint: Color {
        switch style {
        case .neutral: return Color.clear
        case .success: return Color.green.opacity(0.08)
        case .warning: return Color.orange.opacity(0.08)
        case .accent: return Color.accentColor.opacity(0.10)
        }
    }
}

// MARK: - Previews

#Preview("Small") {
    AgentSummaryCardView(
        payload: AgentSummaryPayload(
            agentName: "multica/sapphire",
            completed: [
                .init(title: "Fixed SAP-301 crash on launch")
            ],
            stats: [.init(label: "PRs", value: 3)]
        ),
        size: .small,
        style: .neutral
    )
    .frame(width: 160, height: 100)
    .padding()
}

#Preview("Medium") {
    AgentSummaryCardView(
        payload: AgentSummaryPayload(
            agentName: "multica/sapphire",
            completed: [
                .init(title: "Fixed SAP-301 crash on launch", ref: "https://example.com/pr/4521"),
                .init(title: "Migrated Activity Tabs", ref: "https://example.com/pr/4522"),
            ],
            stats: [
                .init(label: "PRs", value: 3),
                .init(label: "Hours active", value: 6.5),
            ]
        ),
        size: .medium,
        style: .success
    )
    .frame(width: 300, height: 180)
    .padding()
}

#Preview("Wide") {
    AgentSummaryCardView(
        payload: AgentSummaryPayload(
            agentName: "multica/sapphire",
            completed: [
                .init(title: "Fixed SAP-301 crash on launch", ref: "https://example.com/pr/4521"),
                .init(title: "Migrated Activity Tabs to new design system", ref: "https://example.com/pr/4522"),
                .init(title: "Added telemetry for tab switching", ref: "https://example.com/pr/4530"),
            ],
            stats: [
                .init(label: "PRs", value: 3),
                .init(label: "Hours active", value: 6.5),
                .init(label: "Tokens used", value: 1_200_000),
            ]
        ),
        size: .wide,
        style: .accent
    )
    .frame(width: 500, height: 250)
    .padding()
}

#Preview("Hero") {
    AgentSummaryCardView(
        payload: AgentSummaryPayload(
            agentName: "multica/sapphire",
            completed: [
                .init(title: "Fixed SAP-301 crash on launch", ref: "https://example.com/pr/4521"),
                .init(title: "Migrated Activity Tabs to new design system", ref: "https://example.com/pr/4522"),
                .init(title: "Added telemetry for tab switching", ref: "https://example.com/pr/4530"),
            ],
            stats: [
                .init(label: "PRs", value: 3),
                .init(label: "Hours active", value: 6.5),
                .init(label: "Tokens used", value: 1_200_000),
            ]
        ),
        size: .hero,
        style: .warning
    )
    .frame(width: 600, height: 350)
    .padding()
}
