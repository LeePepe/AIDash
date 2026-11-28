import SwiftUI
import AIDashCore
import DesignKit

public struct DigestCardView: View {
    let payload: DigestPayload
    let size: CardSize
    let style: CardStyle
    private let theme = Theme.system
    @State private var isExpanded = false

    public init(payload: DigestPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: AIDashSpace.s12) {
            CardTypeBadge(type: .digest)
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                titleText
                subtitleText
                bodyText(payload.body, clamped: !showsExpandedContent)
                if showsExpandedContent {
                    sectionsContent
                }
                if supportsDisclosure {
                    disclosureButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .cardChrome(size: size, style: style)
    }

    var showsExpandedContent: Bool {
        size == .hero || isExpanded
    }

    var supportsDisclosure: Bool {
        guard size != .hero else { return false }
        let hasSections = !(payload.sections?.isEmpty ?? true)
        return hasSections || payload.body.count > Self.overviewClampThreshold
    }

    nonisolated static let overviewClampLineLimit = 2
    nonisolated static let overviewClampThreshold = 80

    private var recipe: AIDashTypography.DetailRecipe {
        AIDashTypography.detail(for: .digest)
    }

    @ViewBuilder
    private var subtitleText: some View {
        if let subtitle = payload.subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(showsExpandedContent ? nil : 1)
        }
    }

    private var titleText: Text {
        Text(payload.title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(theme.neutrals.text1)
    }

    private func bodyText(_ text: String, clamped: Bool = false) -> some View {
        Text(text)
            .font(recipe.secondary)
            .foregroundStyle(recipe.secondaryColor)
            .lineSpacing(recipe.secondaryLineSpacing)
            .lineLimit(clamped ? Self.overviewClampLineLimit : nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: AIDashSpace.s4) {
                Text(isExpanded ? "收起" : "展开全文 ↗")
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.neutrals.text2)
            .padding(.horizontal, AIDashSpace.s8)
            .padding(.vertical, AIDashSpace.s4)
            .statChipSurface()
            .frame(minHeight: AIDashSpacing.controlHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sectionsContent: some View {
        if let sections = payload.sections, !sections.isEmpty {
            VStack(alignment: .leading, spacing: AIDashSpace.s16) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                        Text(section.heading)
                            .font(recipe.primary)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            bodyText(paragraph)
                        }
                    }
                }
            }
        }
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
