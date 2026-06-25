import SwiftUI
import AIDashCore

public struct DigestCardView: View {
    let payload: DigestPayload
    let size: CardSize
    let style: CardStyle

    public init(payload: DigestPayload, size: CardSize, style: CardStyle) {
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
            if let sections = payload.sections, let first = sections.first {
                sectionView(first)
            }

        case .hero:
            Text(payload.title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(payload.body)
                .font(.body)
                .foregroundStyle(.secondary)
            if let sections = payload.sections {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    sectionView(section)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: DigestPayload.Section) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.heading)
                .font(.subheadline)
                .fontWeight(.medium)
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var truncatedBody: String {
        if payload.body.count <= 200 {
            return payload.body
        }
        let prefix = payload.body.prefix(200)
        return String(prefix) + "\u{2026}"
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

#Preview("Small — Neutral") {
    DigestCardView(
        payload: DigestPayload(
            title: "Tuesday at a glance",
            body: "Yesterday was a moderate-pace day. Multica handled three Sapphire PRs without intervention."
        ),
        size: .small,
        style: .neutral
    )
    .padding()
}

#Preview("Medium — Accent") {
    DigestCardView(
        payload: DigestPayload(
            title: "Tuesday at a glance",
            body: "Yesterday was a moderate-pace day. Multica handled three Sapphire PRs without intervention, including the SAP-301 crash that had been blocking the v9 release. The new design system migration is now 70% complete. Today's main blocker is the performance review feedback."
        ),
        size: .medium,
        style: .accent
    )
    .padding()
}

#Preview("Wide — Success") {
    DigestCardView(
        payload: DigestPayload(
            title: "Tuesday at a glance",
            body: "Yesterday was a moderate-pace day. Multica handled three Sapphire PRs without intervention.",
            sections: [
                .init(heading: "What got shipped", paragraphs: [
                    "Sapphire merged 3 PRs overnight.",
                    "The crash that was blocking v9 is fixed.",
                ]),
                .init(heading: "What's blocking today", paragraphs: [
                    "Performance review feedback (due 5pm).",
                    "Decision needed on Q3 priorities.",
                ]),
            ]
        ),
        size: .wide,
        style: .success
    )
    .padding()
}

#Preview("Hero — Warning") {
    DigestCardView(
        payload: DigestPayload(
            title: "Tuesday at a glance",
            body: "Yesterday was a moderate-pace day. Multica handled three Sapphire PRs without intervention, including the SAP-301 crash that had been blocking the v9 release.",
            sections: [
                .init(heading: "What got shipped", paragraphs: [
                    "Sapphire merged 3 PRs overnight.",
                    "The crash that was blocking v9 is fixed.",
                ]),
                .init(heading: "What's blocking today", paragraphs: [
                    "Performance review feedback (due 5pm).",
                    "Decision needed on Q3 priorities.",
                ]),
            ]
        ),
        size: .hero,
        style: .warning
    )
    .padding()
}
