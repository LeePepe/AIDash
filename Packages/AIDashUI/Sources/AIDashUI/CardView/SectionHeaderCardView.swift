import SwiftUI
import AIDashCore

/// `sectionHeader` is the one structural variant that renders **no card
/// chrome at all** — no background, no border, no padding wrapper, no
/// leading icon badge. Per constitution §Card Chrome it exists as a
/// typography-only divider so containers can group cards with a
/// sub-heading without nesting containers (Principle III, spec D9).
///
/// `size` only affects vertical divider spacing (small = compact,
/// hero = generous). Typography is invariant across sizes per
/// `contracts/cardtype-payloads.md` §sectionHeader. `style` has no
/// chrome effect on this card type.
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
                .font(Self.recipe.primary)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle = payload.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Self.recipe.secondary)
                    .foregroundStyle(Self.recipe.secondaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Invariant typography
    //
    // Typography comes from the shared per-type recipe and never varies
    // with `size`. Holding these as static lets tests assert the
    // invariant without instantiating the view.

    static let recipe = AIDashTypography.detail(for: .sectionHeader)

    // MARK: - Size-driven vertical spacing only

    var verticalPadding: CGFloat {
        switch size {
        case .small:  return 6
        case .medium: return 10
        case .wide:   return 12
        case .hero:   return 16
        }
    }

    var subtitleSpacing: CGFloat {
        switch size {
        case .small:  return 2
        case .medium: return 4
        case .wide:   return 6
        case .hero:   return 8
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
