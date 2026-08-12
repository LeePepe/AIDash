import SwiftUI
import AIDashCore
import DesignKit

/// Renders a `relationship` card: a typed two-dimensional association drawn as
/// a scatter, a heatmap, or a slope chart, always paired with an evidence rail.
///
/// ## Why the evidence rail is not optional
///
/// Constitution §Relationship visualization: an association without its sample
/// size, observation window, and metric definition is a claim without evidence,
/// and an observational association must never be worded as causation. So the
/// rail renders `summary`, `n=<sampleSize>`, `timeWindow`, and
/// `metricDefinition` at EVERY size. `size` reduces the number of visible marks
/// (`RelationshipDensity.visibleMarkCap`) and the plot height — it never drops
/// an evidence row and never shrinks a font.
///
/// ## Layout
///
/// `ViewThatFits(in: .horizontal)` offers chart-beside-rail first and falls
/// back to chart-above-rail when the card is too narrow for both. This is
/// viewport adaptation driven by the *available width*, not a `switch size`
/// typography branch — a `medium` card in a wide column gets the side-by-side
/// layout, and a `wide` card in a narrow window gets the stacked one, both at
/// the same type scale.
public struct RelationshipCardView: View {
    let payload: RelationshipPayload
    let size: CardSize
    let style: CardStyle
    @Environment(\.theme) private var theme

    public init(payload: RelationshipPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        let isEmpty = markCount == 0
        let emptyHeight: CGFloat? = isEmpty ? AIDashSize.emptyMinHeight : nil
        return HStack(alignment: isEmpty ? .center : .top, spacing: AIDashSpace.s12) {
            CardTypeBadge(type: .relationship)
            VStack(alignment: .leading, spacing: AIDashSpace.s12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style, minHeight: emptyHeight)
    }

    @ViewBuilder
    private var content: some View {
        if markCount == 0 {
            // A payload whose mark collection is empty fails
            // `validateInvariants()`, but the router only DECODES — so an
            // already-stored card can still reach here. Degrade to the quiet
            // empty state rather than plotting an axis pair with nothing in it.
            CardEmptyState(message: Self.emptyMessage)
        } else {
            populatedContent
        }
    }

    @ViewBuilder
    private var populatedContent: some View {
        Text(payload.title)
            .font(Self.recipe.primary)
            .foregroundStyle(theme.neutrals.text1)
            .lineLimit(2)
        responsiveContent
    }

    /// Chart + evidence rail, side by side when the width allows and stacked
    /// when it does not. The horizontal candidate declares minimum widths for
    /// both children so `ViewThatFits` rejects it before either becomes an
    /// unreadable sliver.
    private var responsiveContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AIDashSpace.s16) {
                chart
                    .frame(minWidth: RelationshipDensity.chartMinWidth)
                evidenceRail
                    .frame(
                        minWidth: RelationshipDensity.evidenceRailMinWidth,
                        alignment: .topLeading
                    )
            }
            VStack(alignment: .leading, spacing: AIDashSpace.s12) {
                chart
                evidenceRail
            }
        }
    }

    private var chart: some View {
        RelationshipChart(payload: payload, size: size)
    }

    /// The four mandatory evidence rows. `summary` leads (it is the card's
    /// actual claim); the three context rows follow in the monospaced
    /// secondary recipe so `n=`, the window, and the definition read as
    /// instrument metadata against the plot.
    private var evidenceRail: some View {
        let evidence = RelationshipEvidence(payload: payload)
        return VStack(alignment: .leading, spacing: AIDashSpace.s8) {
            Text(evidence.summary)
                .font(Self.recipe.secondary)
                .foregroundStyle(theme.neutrals.text1)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: AIDashSpace.s4) {
                evidenceRow(evidence.sampleText)
                evidenceRow(evidence.windowText)
                evidenceRow(evidence.definitionText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func evidenceRow(_ text: String) -> some View {
        Text(text)
            .font(Self.recipe.secondary)
            .foregroundStyle(theme.neutrals.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Derived

    /// Marks in the collection this payload's `visualization` owns. The other
    /// two collections are empty by contract, so this is the card's real
    /// content count.
    private var markCount: Int {
        switch payload.visualization {
        case .scatter: return payload.points.count
        case .heatmap: return payload.cells.count
        case .slope:   return payload.slopes.count
        }
    }

    // MARK: - Localized strings

    private static let emptyMessage = String(
        localized: "relationship.empty",
        defaultValue: "No data",
        bundle: .module,
        comment: "Shown inside a relationship card when its payload decoded successfully but carries no marks to plot."
    )

    static let recipe = AIDashTypography.detail(for: .relationship)
}

#Preview("relationship — scatter, medium, light") {
    RelationshipCardView(
        payload: RelationshipCardPreviewData.scatter,
        size: .medium,
        style: .neutral
    )
    .frame(width: 340)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
    .environment(\.colorScheme, .light)
}

#Preview("relationship — scatter, wide, dark") {
    RelationshipCardView(
        payload: RelationshipCardPreviewData.scatter,
        size: .wide,
        style: .accent
    )
    .frame(width: 720)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
    .environment(\.colorScheme, .dark)
}

#Preview("relationship — heatmap, medium, dark") {
    RelationshipCardView(
        payload: RelationshipCardPreviewData.heatmap,
        size: .medium,
        style: .neutral
    )
    .frame(width: 340)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
    .environment(\.colorScheme, .dark)
}

#Preview("relationship — heatmap, wide, light") {
    RelationshipCardView(
        payload: RelationshipCardPreviewData.heatmap,
        size: .wide,
        style: .neutral
    )
    .frame(width: 720)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
    .environment(\.colorScheme, .light)
}

#Preview("relationship — slope, medium, light") {
    RelationshipCardView(
        payload: RelationshipCardPreviewData.slope,
        size: .medium,
        style: .neutral
    )
    .frame(width: 340)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
    .environment(\.colorScheme, .light)
}

#Preview("relationship — slope, wide, dark") {
    RelationshipCardView(
        payload: RelationshipCardPreviewData.slope,
        size: .wide,
        style: .success
    )
    .frame(width: 720)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
    .environment(\.colorScheme, .dark)
}

// MARK: - Preview fixtures
//
// Mirrors the contract examples in
// `specs/001-core-briefing-cli/contracts/cardtype-payloads.md` so a preview
// shows what an agent actually publishes, not an idealized shape.

enum RelationshipCardPreviewData {

    static let scatter = RelationshipPayload(
        title: "Cost × outcome",
        visualization: .scatter,
        xAxis: .init(label: "Cost per completed task", unit: "USD"),
        yAxis: .init(label: "First-pass completion proxy", unit: "%"),
        points: [
            .init(label: "AIDash", x: 2.1, y: 88, magnitude: 34, category: "project"),
            .init(label: "Financial", x: 3.4, y: 81, magnitude: 21, category: "project"),
            .init(label: "Skills", x: 4.8, y: 74, magnitude: 12, category: "workspace"),
            .init(label: "Multica", x: 5.6, y: 69, magnitude: 28, category: "workspace"),
            .init(label: "aidata", x: 6.9, y: 62, magnitude: 9, category: "project"),
        ],
        sampleSize: 34,
        timeWindow: "7d",
        metricDefinition: "completed is a pipeline proxy, not objective correctness",
        summary: "AIDash has the lowest observed cost at the highest completion proxy."
    )

    static let heatmap = RelationshipPayload(
        title: "Rework concentration",
        visualization: .heatmap,
        xAxis: .init(label: "Day"),
        yAxis: .init(label: "Workspace"),
        cells: [
            .init(column: "08-09", row: "AIDash", value: 12_000),
            .init(column: "08-10", row: "AIDash", value: 48_000),
            .init(column: "08-11", row: "AIDash", value: 6_000),
            .init(column: "08-09", row: "Financial", value: 3_000),
            .init(column: "08-10", row: "Financial", value: 9_000),
            .init(column: "08-11", row: "Financial", value: 27_000),
        ],
        sampleSize: 4,
        timeWindow: "7d",
        metricDefinition: "tokens on issues completed after cancellation",
        summary: "Observed rework is concentrated on one day; no causal claim."
    )

    static let slope = RelationshipPayload(
        title: "Before × after",
        visualization: .slope,
        xAxis: .init(label: "Period"),
        yAxis: .init(label: "Tokens per completed task"),
        slopes: [
            .init(label: "AIDash", before: 21_000, after: 18_000),
            .init(label: "Financial", before: 17_500, after: 19_200),
            .init(label: "Skills", before: 12_400, after: 9_800),
        ],
        sampleSize: 12,
        timeWindow: "previous 7d vs current 7d",
        metricDefinition: "total tokens divided by completed pipeline tasks",
        summary: "Observed unit token use decreased."
    )
}
