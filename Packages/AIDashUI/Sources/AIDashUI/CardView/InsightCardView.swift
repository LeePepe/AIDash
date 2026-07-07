import SwiftUI
import AIDashCore
import DesignKit

public struct InsightCardView: View {
    let payload: InsightPayload
    let size: CardSize
    let style: CardStyle
    @Environment(\.theme) private var theme

    public init(payload: InsightPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardTypeBadge(type: .insight)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style)
    }

    // Insight renders as a PULL-QUOTE, distinct from digest's article layout:
    // a bold title statement, then the body as a large quote set off by a
    // thick leading accent rule. This makes "one key observation" read
    // differently at a glance from a prose digest or a checklist.

    @ViewBuilder
    private var content: some View {
        let recipe = AIDashTypography.detail(for: .insight)
        Text(payload.title)
            .font(recipe.primary)
        if size != .small, let subtitle = payload.subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        switch size {
        case .small:
            EmptyView()

        case .medium:
            quoteBody(truncatedBody, recipe: recipe)
            if let citations = payload.citations, !citations.isEmpty {
                collapsedCitations(count: citations.count)
            }

        case .wide:
            quoteBody(payload.body, recipe: recipe)
            if let citations = payload.citations, !citations.isEmpty {
                collapsedCitations(count: citations.count)
            }

        case .hero:
            quoteBody(payload.body, recipe: recipe)
            if let citations = payload.citations, !citations.isEmpty {
                citationLinks(citations: citations)
            }
        }
    }

    /// The body as a pull-quote: a thick accent rule on the leading edge +
    /// larger, softer quote text. The rule color is the seed primary (a token,
    /// never inlined) — this is content emphasis, not `style` chrome.
    @ViewBuilder
    private func quoteBody(_ text: String, recipe: AIDashTypography.DetailRecipe) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule(style: .continuous)
                .fill(theme.primary.primary)
                .frame(width: 3)
            Text(text)
                .font(.title3)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    var truncatedBody: String {
        if payload.body.count <= 150 {
            return payload.body
        }
        let prefix = payload.body.prefix(150)
        return String(prefix) + "\u{2026}"
    }

    @ViewBuilder
    private func collapsedCitations(count: Int) -> some View {
        Label(
            "\(count) source\(count == 1 ? "" : "s")",
            systemImage: "link"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func citationLinks(citations: [InsightPayload.Citation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(safeCitations(from: citations), id: \.url) { citation in
                Link(citation.label, destination: citation.url)
                    .font(.footnote)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    func safeCitations(
        from citations: [InsightPayload.Citation]
    ) -> [(label: String, url: URL)] {
        citations.compactMap { citation in
            guard let url = URLPolicy.validate(citation.url) else {
                return nil
            }
            return (label: citation.label, url: url)
        }
    }
}

#Preview("Small — Neutral") {
    InsightCardView(
        payload: InsightPayload(
            title: "Sapphire test suite is the bottleneck",
            body: "Over the past week, 64% of CI time was spent in Sapphire integration tests."
        ),
        size: .small,
        style: .neutral
    )
    .frame(width: 220, height: 140)
    .padding()
}

#Preview("Medium — Warning") {
    InsightCardView(
        payload: InsightPayload(
            title: "Sapphire test suite is the bottleneck",
            body: "Over the past week, 64% of CI time was spent in Sapphire integration tests. Splitting these into a separate workflow would reduce average PR feedback time by ~40s."
        ),
        size: .medium,
        style: .warning
    )
    .frame(width: 420, height: 200)
    .padding()
}

#Preview("Wide — Success") {
    InsightCardView(
        payload: InsightPayload(
            title: "Sapphire test suite is the bottleneck",
            body: "Over the past week, 64% of CI time was spent in Sapphire integration tests. Splitting these into a separate workflow would reduce average PR feedback time by ~40s.",
            citations: [
                .init(label: "PR #2104 timing", url: "https://github.com/example/sapphire/pull/2104/checks"),
                .init(label: "Workflow runs", url: "https://github.com/example/sapphire/actions"),
            ]
        ),
        size: .wide,
        style: .success
    )
    .frame(width: 640, height: 200)
    .padding()
}

#Preview("Hero — Accent") {
    InsightCardView(
        payload: InsightPayload(
            title: "Sapphire test suite is the bottleneck",
            body: "Over the past week, 64% of CI time was spent in Sapphire integration tests. Splitting these into a separate workflow would reduce average PR feedback time by ~40s.",
            citations: [
                .init(label: "PR #2104 timing", url: "https://github.com/example/sapphire/pull/2104/checks"),
                .init(label: "Workflow runs", url: "https://github.com/example/sapphire/actions"),
            ]
        ),
        size: .hero,
        style: .accent
    )
    .frame(width: 640, height: 320)
    .padding()
}
