import SwiftUI
import AIDashCore

/// Renders a `sectionHeader` card — a visual grouping element used to break up
/// a container without nesting (see spec D9 / `contracts/cardtype-payloads.md`).
///
/// All `CardSize` values render the same title + optional subtitle; size only
/// affects vertical spacing (small = compact, hero = generous).
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
            Text(payload.title)
                .font(titleFont)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            if let subtitle = payload.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundTint, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Size-driven typography & spacing

    private var titleFont: Font {
        switch size {
        case .small:  return .subheadline
        case .medium: return .headline
        case .wide:   return .title3
        case .hero:   return .title2
        }
    }

    private var subtitleFont: Font {
        switch size {
        case .small:  return .caption2
        case .medium: return .caption
        case .wide:   return .footnote
        case .hero:   return .subheadline
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

    private var verticalPadding: CGFloat {
        switch size {
        case .small:  return 6
        case .medium: return 10
        case .wide:   return 14
        case .hero:   return 20
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

#Preview("Small — neutral") {
    SectionHeaderCardView(
        payload: SectionHeaderPayload(title: "Engineering"),
        size: .small,
        style: .neutral
    )
    .frame(width: 320)
    .padding()
}

#Preview("Medium — success + subtitle") {
    SectionHeaderCardView(
        payload: SectionHeaderPayload(
            title: "Engineering",
            subtitle: "Backend, infra, tooling"
        ),
        size: .medium,
        style: .success
    )
    .frame(width: 420)
    .padding()
}

#Preview("Wide — warning + subtitle") {
    SectionHeaderCardView(
        payload: SectionHeaderPayload(
            title: "Incidents this week",
            subtitle: "3 resolved, 1 ongoing"
        ),
        size: .wide,
        style: .warning
    )
    .frame(width: 560)
    .padding()
}

#Preview("Hero — accent + subtitle") {
    SectionHeaderCardView(
        payload: SectionHeaderPayload(
            title: "Today's briefing",
            subtitle: "Highlights from your agents"
        ),
        size: .hero,
        style: .accent
    )
    .frame(width: 640)
    .padding()
}
