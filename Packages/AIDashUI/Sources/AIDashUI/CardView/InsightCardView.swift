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
            Text(payload.title)
                .font(.headline)
                .lineLimit(2)

        case .medium:
            Text(payload.title)
                .font(.headline)
            Text(truncatedBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .wide:
            Text(payload.title)
                .font(.headline)
            Text(payload.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let citations = payload.citations, !citations.isEmpty {
                citationLinks(citations: citations)
            }

        case .hero:
            Text(payload.title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(payload.body)
                .font(.body)
                .foregroundStyle(.secondary)
            if let citations = payload.citations, !citations.isEmpty {
                citationLinks(citations: citations)
            }
        }
    }

    private var truncatedBody: String {
        if payload.body.count <= 150 {
            return payload.body
        }
        let prefix = payload.body.prefix(150)
        return String(prefix) + "…"
    }

    @ViewBuilder
    private func citationLinks(citations: [InsightPayload.Citation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(citations, id: \.url) { citation in
                if let url = URL(string: citation.url) {
                    Link(citation.label, destination: url)
                        .font(.footnote)
                }
            }
        }
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

#Preview("Small — Neutral") {
    InsightCardView(
        payload: InsightPayload(
            title: "Sapphire test suite is the bottleneck",
            body: "Over the past week, 64% of CI time was spent in Sapphire integration tests."
        ),
        size: .small,
        style: .neutral
    )
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
    .padding()
}
