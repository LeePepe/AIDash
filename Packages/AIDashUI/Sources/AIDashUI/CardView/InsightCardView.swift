import SwiftUI
import AIDashCore

public struct InsightCardView: View {
    let payload: InsightPayload
    let size: CardSize
    let style: CardStyle

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

    @ViewBuilder
    private var content: some View {
        let recipe = AIDashTypography.detail(for: .insight)
        Text(payload.title)
            .font(recipe.primary)

        switch size {
        case .small:
            EmptyView()

        case .medium:
            Text(truncatedBody)
                .font(recipe.secondary)
                .foregroundStyle(recipe.secondaryColor)
            if let citations = payload.citations, !citations.isEmpty {
                collapsedCitations(count: citations.count)
            }

        case .wide:
            Text(payload.body)
                .font(recipe.secondary)
                .foregroundStyle(recipe.secondaryColor)
            if let citations = payload.citations, !citations.isEmpty {
                collapsedCitations(count: citations.count)
            }

        case .hero:
            Text(payload.body)
                .font(recipe.secondary)
                .foregroundStyle(recipe.secondaryColor)
            if let citations = payload.citations, !citations.isEmpty {
                citationLinks(citations: citations)
            }
        }
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
