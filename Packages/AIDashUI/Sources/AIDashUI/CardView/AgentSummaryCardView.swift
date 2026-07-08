import SwiftUI
import AIDashCore
import DesignKit

public struct AgentSummaryCardView: View {
    let payload: AgentSummaryPayload
    let size: CardSize
    let style: CardStyle
    @Environment(\.theme) private var theme

    public init(payload: AgentSummaryPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardTypeBadge(type: .agentSummary)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: 680, alignment: .leading)
            Spacer(minLength: 0)
        }
        .cardChrome(size: size, style: style)
    }

    private var recipe: AIDashTypography.DetailRecipe {
        AIDashTypography.detail(for: .agentSummary)
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

    // MARK: - Size Layouts (density / item count only — no typography or chrome changes)

    @ViewBuilder
    private var smallLayout: some View {
        agentNameText
            .lineLimit(1)
        if let prStat = payload.stats?.first(where: { $0.label == "PRs" }) {
            Text("\(Int(prStat.value)) \(Self.prsLabel)")
                .font(recipe.secondary)
                .foregroundStyle(recipe.secondaryColor)
        } else if let firstStat = payload.stats?.first {
            Text("\(firstStat.label): \(formattedStatValue(firstStat.value))")
                .font(recipe.secondary)
                .foregroundStyle(recipe.secondaryColor)
        }
    }

    @ViewBuilder
    private var mediumLayout: some View {
        agentNameText
            .lineLimit(1)

        if let stats = payload.stats, !stats.isEmpty {
            statChips(stats)
        }

        ForEach(Array(payload.completed.prefix(2).enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }
    }

    @ViewBuilder
    private var wideLayout: some View {
        agentNameText
            .lineLimit(1)

        if let stats = payload.stats, !stats.isEmpty {
            statChips(stats)
        }

        ForEach(Array(payload.completed.prefix(5).enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }
    }

    @ViewBuilder
    private var heroLayout: some View {
        agentNameText

        Text(Self.heroSubtitle)
            .font(recipe.secondary)
            .foregroundStyle(.secondary)
            .italic()

        ForEach(Array(payload.completed.enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }

        if let stats = payload.stats, !stats.isEmpty {
            Divider()
            statsLayout(stats)
        }
    }

    // MARK: - Shared text styling

    private var agentNameText: Text {
        Text(payload.agentName)
            .font(recipe.primary)
    }

    @ViewBuilder
    private func completedRow(_ item: AgentSummaryPayload.Completed) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.success)
                .font(.caption)
                .accessibilityHidden(true)
            if let url = URLPolicy.validate(item.ref) {
                Link(item.title, destination: url)
                    .font(recipe.secondary)
                    .foregroundStyle(recipe.secondaryColor)
                    .lineLimit(completedRowLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            } else {
                Text(item.title)
                    .font(recipe.secondary)
                    .foregroundStyle(recipe.secondaryColor)
                    .lineLimit(completedRowLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Per constitution §E.2: `wide` and `hero` body text MUST wrap, not
    /// truncate. `small` and `medium` stay single-line for layout density.
    private var completedRowLineLimit: Int? {
        switch size {
        case .small, .medium: return 1
        case .wide, .hero:    return nil
        }
    }

    /// Battle-report stat chips shown at the TOP of the card — a horizontal
    /// row of number-over-label chips, so agentSummary reads "stats first" and
    /// looks distinct from a digest/insight prose card. The chip surface is a
    /// sibling Capsule (not `.background`, which chrome guards reserve for the
    /// shared cardChrome modifier) filled from the neutral inner token.
    @ViewBuilder
    private func statChips(_ stats: [AgentSummaryPayload.Stat]) -> some View {
        HStack(spacing: AIDashSpace.s8) {
            ForEach(Array(stats.prefix(4).enumerated()), id: \.offset) { _, stat in
                statChip(stat)
            }
        }
    }

    @ViewBuilder
    private func statChip(_ stat: AgentSummaryPayload.Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedStatValue(stat.value))
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text(stat.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .padding(.horizontal, AIDashSpace.s12)
        .padding(.vertical, AIDashSpace.s8)
        .statChipSurface()
    }

    /// Stats row that adapts to variable stat counts/labels without
    /// horizontal overflow. Uses a wrapping grid so long labels reflow
    /// to a new line instead of clipping.
    @ViewBuilder
    private func statsLayout(_ stats: [AgentSummaryPayload.Stat]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 80), spacing: 12, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                statBadge(stat)
            }
        }
    }

    @ViewBuilder
    private func statBadge(_ stat: AgentSummaryPayload.Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedStatValue(stat.value))
                .font(recipe.primary)
            Text(stat.label)
                .font(recipe.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formattedStatValue(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    // MARK: - Localized strings
    //
    // Per constitution §F.1, user-visible literals are accessed via
    // `String(localized:)`. These keys are also written to the package
    // String Catalog (`Resources/Localizable.xcstrings`) so translators
    // can localize them without touching source.

    private static let prsLabel = String(
        localized: "agent_summary.prs_label",
        defaultValue: "PRs",
        bundle: .module,
        comment: "Suffix shown after a pull-request count in the small Agent Summary card layout."
    )

    private static let heroSubtitle = String(
        localized: "agent_summary.hero_subtitle",
        defaultValue: "spent the day on",
        bundle: .module,
        comment: "Pull-quote shown under the agent name in the hero Agent Summary card layout."
    )
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
    .frame(width: 220, height: 120)
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
    .frame(width: 360, height: 200)
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
    .frame(width: 560, height: 280)
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
    .frame(width: 640, height: 380)
    .padding()
}
