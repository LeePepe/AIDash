import SwiftUI
import AIDashCore

public struct SectionHeaderCardView: View {
    let payload: SectionHeaderPayload
    let size: CardSize
    let style: CardStyle

    public init(payload: SectionHeaderPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: subtitleSpacing) {
            content
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundTint, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var content: some View {
        Text(payload.title)
            .font(titleFont)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

        if let subtitle = payload.subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Size-driven typography & spacing

    // Per contracts/cardtype-payloads.md §sectionHeader:
    // all sizes show the same header layout; size hint affects vertical
    // spacing only (small = compact, hero = generous).

    private var titleFont: Font {
        switch size {
        case .small:  return .headline
        case .medium: return .title3
        case .wide:   return .title2
        case .hero:   return .title
        }
    }

    private var subtitleFont: Font {
        switch size {
        case .small:  return .caption
        case .medium: return .subheadline
        case .wide:   return .subheadline
        case .hero:   return .body
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small:  return 12
        case .medium: return 16
        case .wide:   return 16
        case .hero:   return 20
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .small:  return 6
        case .medium: return 10
        case .wide:   return 12
        case .hero:   return 16
        }
    }

    private var subtitleSpacing: CGFloat {
        switch size {
        case .small:  return 2
        case .medium: return 4
        case .wide:   return 6
        case .hero:   return 8
        }
    }

    // MARK: - Style tint

    private var backgroundTint: Color {
        switch style {
        case .neutral: return Color.clear
        case .success: return Color.green.opacity(0.08)
        case .warning: return Color.orange.opacity(0.08)
        case .accent:  return Color.accentColor.opacity(0.10)
        }
    }
}

// MARK: - Previews

#Preview("Small / neutral / no subtitle") {
    SectionHeaderCardView(
        payload: SectionHeaderPayload(title: "Engineering"),
        size: .small,
        style: .neutral
    )
    .frame(width: 320)
    .padding()
}

#Preview("Medium / accent / subtitle") {
    SectionHeaderCardView(
        payload: SectionHeaderPayload(
            title: "Engineering",
            subtitle: "Backend, infra, tooling"
        ),
        size: .medium,
        style: .accent
    )
    .frame(width: 420)
    .padding()
}

#Preview("Wide / success / subtitle") {
    SectionHeaderCardView(
        payload: SectionHeaderPayload(
            title: "Today's wins",
            subtitle: "Shipped, merged, unblocked"
        ),
        size: .wide,
        style: .success
    )
    .frame(width: 560)
    .padding()
}

#Preview("Hero / warning / subtitle") {
    SectionHeaderCardView(
        payload: SectionHeaderPayload(
            title: "Blocking items",
            subtitle: "Needs attention before EOD"
        ),
        size: .hero,
        style: .warning
    )
    .frame(width: 640)
    .padding()
}
