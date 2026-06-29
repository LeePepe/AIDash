import SwiftUI
import AIDashCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Typography
//
// Authoritative source: .specify/memory/constitution.md
// §Design System & Tokens — Two-Level Typography Hierarchy
//                          Per-Type Visual Recipes (detail tier)

public enum AIDashTypography {

    /// Overview tier — container titles, section dividers, briefing date header.
    /// `.caption2 / rounded / semibold`, color `.secondary`, letter spacing +0.6pt.
    public static let section: Font = .system(.caption2, design: .rounded, weight: .semibold)

    /// Overview-tier color. Apply with `.foregroundStyle(AIDashTypography.sectionColor)`.
    public static let sectionColor: Color = .secondary

    /// Overview-tier letter spacing. Apply with `.tracking(AIDashTypography.sectionTracking)`.
    public static let sectionTracking: CGFloat = 0.6

    /// Detail-tier typography recipe for a single `CardType`.
    /// `sectionHeader` is NOT a content card; its row exists only to keep callers
    /// from special-casing the enum.
    public struct DetailRecipe: Sendable, Equatable {
        public let primary: Font
        public let secondary: Font
        public let secondaryLineSpacing: CGFloat
        public let secondaryColor: Color

        public init(
            primary: Font,
            secondary: Font,
            secondaryLineSpacing: CGFloat = 0,
            secondaryColor: Color = .primary
        ) {
            self.primary = primary
            self.secondary = secondary
            self.secondaryLineSpacing = secondaryLineSpacing
            self.secondaryColor = secondaryColor
        }
    }

    public static func detail(for type: CardType) -> DetailRecipe {
        switch type {
        case .metric:
            return DetailRecipe(
                primary: .system(size: 36, weight: .bold, design: .rounded),
                secondary: .caption,
                secondaryColor: .secondary
            )
        case .insight:
            return DetailRecipe(
                primary: .title3.weight(.semibold),
                secondary: .body,
                secondaryColor: .primary
            )
        case .digest:
            return DetailRecipe(
                primary: .headline,
                secondary: .body,
                secondaryLineSpacing: 4,
                secondaryColor: .primary
            )
        case .agentSummary:
            return DetailRecipe(
                primary: .headline,
                secondary: .callout,
                secondaryColor: .primary
            )
        case .todoList:
            return DetailRecipe(
                primary: .body,
                secondary: .caption2,
                secondaryColor: .secondary
            )
        case .trending:
            return DetailRecipe(
                primary: .callout.monospaced(),
                secondary: .body,
                secondaryColor: .primary
            )
        case .sectionHeader:
            return DetailRecipe(
                primary: .title3.weight(.semibold),
                secondary: .subheadline,
                secondaryColor: .secondary
            )
        }
    }
}

// MARK: - Per-type icon badge (`type` discriminator)
//
// §Per-Type Visual Recipes table — icon + icon tint.
// §Icon badge specification — 32×32, 8pt rounded, 0.15 tinted container, 16pt semibold glyph.

extension CardType {

    /// SF Symbol glyph for the leading 32×32 icon badge.
    /// `sectionHeader` returns `nil` — it renders without a badge per §Card Chrome.
    public var iconSymbol: String? {
        switch self {
        case .metric:        return "chart.bar.fill"
        case .insight:       return "sparkles"
        case .digest:        return "doc.text.fill"
        case .agentSummary:  return "bubble.left.and.bubble.right.fill"
        case .todoList:      return "checklist"
        case .trending:      return "chart.line.uptrend.xyaxis"
        case .sectionHeader: return nil
        }
    }

    /// Tint color for the leading icon badge.
    /// `sectionHeader` returns `nil` — it has no badge.
    public var iconTint: Color? {
        switch self {
        case .metric:        return .blue
        case .insight:       return .purple
        case .digest:        return .teal
        case .agentSummary:  return .indigo
        case .todoList:      return .green
        case .trending:      return .orange
        case .sectionHeader: return nil
        }
    }

    /// True if this card type renders the leading 32×32 icon badge.
    public var hasIconBadge: Bool {
        iconSymbol != nil && iconTint != nil
    }
}

public struct CardTypeBadge: View {
    public let type: CardType

    public init(type: CardType) {
        self.type = type
    }

    public var body: some View {
        if let symbol = type.iconSymbol, let tint = type.iconTint {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Size geometry (`size` discriminator)
//
// §Size = Geometry Only — grid span, min height, corner radius, padding ladder.
// The corner radius and padding columns of the Card Chrome rendering come from
// AIDashSize, NOT from any flat chrome constant.

public enum AIDashSize {

    /// Number of grid columns this card occupies. `wide` and `hero` span every
    /// column the container's grid renders.
    public static func gridSpan(_ size: CardSize) -> Int {
        switch size {
        case .small:  return 1
        case .medium: return 2
        case .wide:   return .max
        case .hero:   return .max
        }
    }

    /// Minimum card height in points.
    public static func minHeight(_ size: CardSize) -> CGFloat {
        switch size {
        case .small:  return 96
        case .medium: return 140
        case .wide:   return 140
        case .hero:   return 280
        }
    }

    /// Card corner radius in points. Single source of truth for both the card
    /// background shape and the hairline overlay stroke.
    public static func cornerRadius(_ size: CardSize) -> CGFloat {
        switch size {
        case .small:  return 10
        case .medium: return 14
        case .wide:   return 14
        case .hero:   return 20
        }
    }

    /// Inner padding (EdgeInsets) per §Size = Geometry Only ladder.
    /// - `small`: 12 horizontal, 14 vertical
    /// - `medium`: 16 all sides
    /// - `wide`: 16 vertical, 20 horizontal
    /// - `hero`: 24 all sides
    public static func padding(_ size: CardSize) -> EdgeInsets {
        switch size {
        case .small:
            return EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)
        case .medium:
            return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        case .wide:
            return EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        case .hero:
            return EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
        }
    }

    /// Container grid column count for the given viewport width.
    /// iPhone = 1, iPad portrait = 2, iPad landscape / Mac small = 3,
    /// Mac large = 4. Breakpoints chosen to match Apple's regular/compact size
    /// classes and standard Mac window widths.
    public static func columnCount(forWidth width: CGFloat) -> Int {
        if width < 480 { return 1 }
        if width < 768 { return 2 }
        if width < 1100 { return 3 }
        return 4
    }
}

// MARK: - Spacing
//
// §Spacing & Color Tokens + §Page Chrome.

public enum AIDashSpacing {
    /// 24pt between containers.
    public static let containerVertical: CGFloat = 24
    /// 12pt between a container's header and its first card.
    public static let containerHeaderToFirstCard: CGFloat = 12
    /// 12pt between cards inside a container.
    public static let cardVertical: CGFloat = 12
    /// 12pt grid column gap.
    public static let gridGap: CGFloat = 12
    /// 24pt page horizontal padding on macOS.
    public static let pageHorizontalMac: CGFloat = 24
    /// 20pt page horizontal padding on iOS / iPadOS.
    public static let pageHorizontalCompact: CGFloat = 20
    /// 24pt top/bottom page padding.
    public static let pageVertical: CGFloat = 24
}

// MARK: - Chrome (stripe + hairline only)
//
// §Card Chrome — corner radius and padding live in §Size = Geometry Only,
// NOT here. AIDashChrome carries only the non-size-owned chrome tokens.

public enum AIDashChrome {
    /// Width of the left-edge accent stripe drawn for non-neutral styles.
    public static let stripeWidth: CGFloat = 3
    /// Width of the hairline overlay that defines card edges.
    public static let hairlineWidth: CGFloat = 0.5
    /// Opacity applied to `.separator` for the hairline overlay.
    public static let hairlineOpacity: Double = 0.5

    /// Stripe color per `style`. `neutral` returns `nil` — no stripe drawn.
    public static func stripeColor(for style: CardStyle) -> Color? {
        switch style {
        case .neutral: return nil
        case .success: return .green
        case .warning: return .orange
        case .accent:  return .accentColor
        }
    }
}

// MARK: - Shared card chrome modifier

public struct CardChromeModifier: ViewModifier {
    public let size: CardSize
    public let style: CardStyle

    public init(size: CardSize, style: CardStyle) {
        self.size = size
        self.style = style
    }

    public func body(content: Content) -> some View {
        let radius = AIDashSize.cornerRadius(size)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .padding(AIDashSize.padding(size))
            .frame(minHeight: AIDashSize.minHeight(size), alignment: .topLeading)
            .background(.background.secondary, in: shape)
            .overlay(
                shape.strokeBorder(
                    Self.separatorColor.opacity(AIDashChrome.hairlineOpacity),
                    lineWidth: AIDashChrome.hairlineWidth
                )
            )
            .overlay(alignment: .leading) {
                if let stripe = AIDashChrome.stripeColor(for: style) {
                    Rectangle()
                        .fill(stripe)
                        .frame(width: AIDashChrome.stripeWidth)
                }
            }
            .clipShape(shape)
    }

    private static var separatorColor: Color {
        #if canImport(UIKit)
        return Color(UIColor.separator)
        #elseif canImport(AppKit)
        return Color(NSColor.separatorColor)
        #else
        return Color.gray
        #endif
    }
}

extension View {
    /// Apply the §Card Chrome contract — background, padding, hairline overlay,
    /// and optional left stripe. Per-card override is forbidden by the
    /// constitution; renderers MUST consume this modifier.
    public func cardChrome(size: CardSize, style: CardStyle) -> some View {
        modifier(CardChromeModifier(size: size, style: style))
    }
}
