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
                titleText
                subtitleText
                bodyText(payload.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .cardChrome(size: size, style: style)
    }

    private var recipe: AIDashTypography.DetailRecipe {
        AIDashTypography.detail(for: .digest)
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
}

// MARK: - Previews

#Preview("Small — Neutral") {
    DigestCardView(
        payload: DigestPayload(
            title: "Tuesday at a glance",
            body: "Yesterday was a moderate-pace day. Multica handled three Atlas PRs without intervention."
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
            body: "Yesterday was a moderate-pace day. Multica handled three Atlas PRs without intervention, including the PROJ-301 crash that had been blocking the v9 release. The new design system migration is now 70% complete. Today's main blocker is the performance review feedback."
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
            body: "Yesterday was a moderate-pace day. Multica handled three Atlas PRs without intervention."
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
            body: "Yesterday was a moderate-pace day. Multica handled three Atlas PRs without intervention, including the PROJ-301 crash that had been blocking the v9 release."
        ),
        size: .hero,
        style: .warning
    )
    .frame(width: 640, height: 420)
    .padding()
}
