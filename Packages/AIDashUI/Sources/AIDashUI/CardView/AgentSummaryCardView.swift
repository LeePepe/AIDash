import SwiftUI
import AIDashCore
import DesignKit

public struct AgentSummaryCardView: View {
    let payload: AgentSummaryPayload
    let size: CardSize
    let style: CardStyle
    private let theme = Theme.system

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
        primaryStatHero
    }

    @ViewBuilder
    private var mediumLayout: some View {
        agentNameText
            .lineLimit(1)

        primaryStatHero
        secondaryStatsLine

        ForEach(Array(payload.completed.prefix(2).enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }
    }

    @ViewBuilder
    private var wideLayout: some View {
        agentNameText
            .lineLimit(1)

        primaryStatHero
        secondaryStatsLine

        ForEach(Array(payload.completed.prefix(5).enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }
    }

    @ViewBuilder
    private var heroLayout: some View {
        agentNameText

        primaryStatHero
        secondaryStatsLine

        ForEach(Array(payload.completed.enumerated()), id: \.offset) { _, item in
            completedRow(item)
        }
    }

    // MARK: - Single P0 focal hierarchy

    var primaryStatDisplay: (value: String, label: String) {
        if let prStat = payload.stats?.first(where: { $0.label == "PRs" }) {
            return ("\(Int(prStat.value))", Self.prsLabel)
        }
        if let first = payload.stats?.first {
            return (formattedStatValue(first.value), first.label)
        }
        return ("\(payload.completed.count)", "Completed")
    }

    var secondaryStatsSummary: String? {
        guard let stats = payload.stats, stats.count > 1 else { return nil }
        let primaryLabel = payload.stats?.first(where: { $0.label == "PRs" })?.label ?? stats.first?.label
        let remaining = stats.filter { $0.label != primaryLabel }
        guard !remaining.isEmpty else { return nil }
        return remaining.prefix(3)
            .map { "\($0.label) \(formattedStatValue($0.value))" }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var primaryStatHero: some View {
        let hero = primaryStatDisplay
        HStack(alignment: .firstTextBaseline, spacing: AIDashSpace.s8) {
            Text(hero.value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.neutrals.text1)
                .fixedSize(horizontal: true, vertical: false)
            Text(hero.label)
                .font(recipe.secondary)
                .foregroundStyle(theme.neutrals.text2)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var secondaryStatsLine: some View {
        if let summary = secondaryStatsSummary {
            Text(summary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.neutrals.text2)
                .lineLimit(1)
        }
    }

    // MARK: - Shared text styling

    private var agentNameText: some View {
        Text(payload.agentName)
            .font(recipe.primary)
            .foregroundStyle(theme.neutrals.text1)
    }

    @ViewBuilder
    private func completedRow(_ item: AgentSummaryPayload.Completed) -> some View {
        HStack(spacing: AIDashSpace.s8) {
            Image(systemName: "checkmark")
                .foregroundStyle(theme.neutrals.text2)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            if let url = URLPolicy.validate(item.ref) {
                Link(item.title, destination: url)
                    .font(recipe.secondary)
                    .foregroundStyle(recipe.secondaryColor)
                    .lineLimit(completedRowLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: AIDashSpacing.controlHitTarget)
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
}

// MARK: - Previews

#Preview("Small") {
    AgentSummaryCardView(
        payload: AgentSummaryPayload(
            agentName: "multica/atlas",
            completed: [
                .init(title: "Fixed PROJ-301 crash on launch")
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
            agentName: "multica/atlas",
            completed: [
                .init(title: "Fixed PROJ-301 crash on launch", ref: "https://example.com/pr/4521"),
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
            agentName: "multica/atlas",
            completed: [
                .init(title: "Fixed PROJ-301 crash on launch", ref: "https://example.com/pr/4521"),
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
            agentName: "multica/atlas",
            completed: [
                .init(title: "Fixed PROJ-301 crash on launch", ref: "https://example.com/pr/4521"),
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
