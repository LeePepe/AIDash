import SwiftUI
import AIDashCore
import DesignKit

// MARK: - Container chrome mode (MY-1306)
//
// A container renders as "title layer + card layer" (§Container Chrome).
// When it renders exactly ONE card those two layers express the same
// grouping, so the reader sees a frame inside a frame — the redundancy
// MY-1306 removes. §Card Chrome therefore branches on the container's
// EFFECTIVE CARD COUNT:
//
//   count == 1 → `.bare`   — no background / hairline / radius / padding;
//                            the content sits directly on the page
//                            background, flush with the container title,
//                            and `style` moves to a title-side bar.
//   count >= 2 → `.framed` — the card frame stays (cards still need
//                            boundaries against each other) but quieter:
//                            damped hairline, damped stripe, wider gaps.
//
// The decision is keyed on COUNT ALONE. It MUST NOT consult `CardType`:
// the three orthogonal card dimensions (type / size / style) stay
// unconflated (§Principle VI), and a container that happens to hold one
// card of any type gets the same treatment.

/// How much frame a card draws around itself, decided by its container.
public enum CardChromeMode: String, Sendable, Equatable, CaseIterable {
    /// No card frame at all — the content IS the block (single-card container).
    case bare
    /// The full §Card Chrome frame, damped for low contrast (multi-card).
    case framed
}

/// What a nested `innerSurface` panel represents inside its card. The role
/// decides whether the panel survives when the card itself goes bare.
public enum InnerSurfaceRole: String, Sendable, Equatable, CaseIterable {
    /// The panel wraps the card's WHOLE body. In a bare card this would just
    /// regrow the removed frame one level inward, so it collapses.
    case body
    /// The panel emphasises a local fragment (a chip group, an embedded
    /// gauge). It is content, not chrome, so it survives in both modes.
    case emphasis
}

/// The container-chrome decision functions. Pure, count-driven, testable
/// without a view graph — the render layer only consumes the result.
public enum AIDashContainerChrome {

    /// Resolve the chrome mode from the number of cards a container actually
    /// renders. Only an exactly-single card drops its frame; `0` (nothing to
    /// unframe) and any nonsensical negative count degrade to `.framed` rather
    /// than trapping (§red line: rendering failure degrades gracefully).
    public static func chromeMode(effectiveCardCount count: Int) -> CardChromeMode {
        count == 1 ? .bare : .framed
    }

    /// Whether an `innerSurface` panel still paints its fill under `mode`.
    /// A whole-card `.body` panel collapses in a bare card; local `.emphasis`
    /// panels stay in both modes.
    public static func drawsInnerSurface(role: InnerSurfaceRole, mode: CardChromeMode) -> Bool {
        switch role {
        case .body:     return mode == .framed
        case .emphasis: return true
        }
    }
}

// MARK: - Environment plumbing
//
// The mode travels down the environment rather than through every renderer's
// initializer: a card view keeps its `(payload, size, style)` signature, and
// a card rendered OUTSIDE a container (preview, snapshot, isolated test)
// keeps its frame via the `.framed` default.

private struct CardChromeModeKey: EnvironmentKey {
    static let defaultValue: CardChromeMode = .framed
}

extension EnvironmentValues {
    /// The chrome mode the enclosing container resolved from its card count.
    /// Defaults to `.framed` so a card outside any container keeps its frame.
    public var cardChromeMode: CardChromeMode {
        get { self[CardChromeModeKey.self] }
        set { self[CardChromeModeKey.self] = newValue }
    }
}

// MARK: - Title-side style bar
//
// Rule A moves `style` from the (now absent) card stripe to a bar beside the
// container title, so the accent/warning signal survives losing the frame.
// The bar hangs into the page margin by `titleBarGutter`, which keeps the
// title text and the card content on ONE left edge — the point of dropping
// the frame in the first place.
//
// It lives here, in the token layer, so `ContainerView` stays typography +
// spacing only per §Container Chrome (it never draws a shape itself).

public struct ContainerStyleBarModifier: ViewModifier {
    /// The style whose signal the bar carries. `nil` (or `.neutral`, which
    /// resolves no stripe color) draws nothing.
    public let style: CardStyle?
    @Environment(\.theme) private var theme

    public init(style: CardStyle?) {
        self.style = style
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if let style, let color = AIDashChrome.stripeColor(for: style, theme: theme) {
                Capsule(style: .continuous)
                    .fill(color.opacity(AIDashChrome.stripeOpacity))
                    .frame(width: AIDashChrome.stripeWidth)
                    .offset(x: -AIDashChrome.titleBarGutter)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Attach the title-side style bar — the bare-mode home of `style`.
    /// Apply it to the title line so the bar's height IS the line height.
    public func containerStyleBar(_ style: CardStyle?) -> some View {
        modifier(ContainerStyleBarModifier(style: style))
    }
}
