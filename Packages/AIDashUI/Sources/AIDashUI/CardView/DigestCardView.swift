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
        HStack(alignment: .top, spacing: 12) {
            CardTypeBadge(type: .digest)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .cardChrome(size: size, style: style)
    }

    /// A full-row `wide` digest lets its section columns spread across the card;
    /// smaller sizes keep a comfortable reading measure.
    private var contentMaxWidth: CGFloat {
        size == .wide ? 900 : 680
    }

    private var recipe: AIDashTypography.DetailRecipe {
        AIDashTypography.detail(for: .digest)
    }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .small:
            titleText
                .lineLimit(2)

        case .medium:
            titleText
            subtitleText
            bodyText(truncatedBody)

        case .wide:
            titleText
            subtitleText
            bodyText(payload.body)
                .frame(maxWidth: 640, alignment: .leading)
            if let sections = payload.sections, !sections.isEmpty {
                sectionColumns(sections)
            }

        case .hero:
            titleText
            subtitleText
            bodyText(payload.body)
                .frame(maxWidth: 640, alignment: .leading)
            if let sections = payload.sections {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    sectionView(section)
                }
            }
        }
    }

    @ViewBuilder
    private var subtitleText: some View {
        if let subtitle = payload.subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var titleText: Text {
        Text(payload.title)
            .font(.title3.weight(.semibold))
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(recipe.secondary)
            .foregroundStyle(recipe.secondaryColor)
            .lineSpacing(recipe.secondaryLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func sectionView(_ section: DigestPayload.Section) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.heading)
                .font(recipe.primary)
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(recipe.secondary)
                    .foregroundStyle(recipe.secondaryColor)
                    .lineSpacing(recipe.secondaryLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    /// `wide` sections laid out in equal columns (with a hairline divider
    /// between them) so a full-row digest fills its width symmetrically instead
    /// of stranding one section on the left (design-review r4/r5).
    @ViewBuilder
    private func sectionColumns(_ sections: [DigestPayload.Section]) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(Array(sections.prefix(3).enumerated()), id: \.offset) { index, section in
                if index > 0 {
                    Divider()
                }
                sectionView(section)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var truncatedBody: String {
        if payload.body.count <= 200 {
            return payload.body
        }
        let prefix = payload.body.prefix(200)
        return String(prefix) + "\u{2026}"
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
    .frame(width: 220, height: 120)
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
    .frame(width: 360, height: 200)
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
    .frame(width: 560, height: 320)
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
    .frame(width: 640, height: 420)
    .padding()
}
