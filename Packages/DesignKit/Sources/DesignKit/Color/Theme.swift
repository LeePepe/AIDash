import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// ============================================================================
//  Theme — a resolved token set for the current (seed, neutral, colorScheme).
//  Inject via .environment(\.theme, …); read with @Environment(\.theme).
//  This is the SwiftUI equivalent of the web CSS-variable set.
// ============================================================================

public struct Theme: Sendable {
    public let seed: Seed
    public let neutral: Neutral
    public let isDark: Bool

    public let primary: PrimaryPalette
    public let neutrals: Neutrals
    public let charts: [Color]

    public var success: Color { Semantic.success(isDark: isDark) }
    public var warning: Color { Semantic.warning(isDark: isDark) }
    public var danger: Color { Semantic.danger(isDark: isDark) }

    /// Per-category icon-badge tint, resolved for the current color scheme.
    public func classificationTint(_ kind: Classification) -> Color {
        kind.tint(isDark: isDark)
    }

    public init(seed: Seed = .appleBlue, neutral: Neutral = .slate, isDark: Bool = false) {
        self.seed = seed
        self.neutral = neutral
        self.isDark = isDark
        self.primary = makePrimaryPalette(seed: seed.color, isDark: isDark)
        self.neutrals = neutral.palette(isDark: isDark)
        self.charts = chartPalette(seed: seed.color, isDark: isDark)
    }

    /// Chart color by index, wrapping the 8-stop palette.
    public func chart(_ i: Int) -> Color { charts[i % charts.count] }

    /// Categorical chart color for a PURE-CATEGORY slot (e.g. a stackedBar's
    /// model-tier segments), by category ordinal.
    ///
    /// The raw 8-stop `charts` palette walks the hue wheel in small steps, so
    /// adjacent stops (chart(0)/chart(1)) are near-identical and stop 0 sits on
    /// the seed hue — bad for telling 3–4 categories apart and for keeping them
    /// clear of the fixed semantic green/warning/danger. `chartCategorical`
    /// remaps the ordinal through the sequence `[1, 3, 7, 2, 4, 0, 5]`, whose
    /// first four entries are pairwise ≥40° apart in hue and each ≥22° away
    /// from the semantic hues — so a legend of categories reads as distinct,
    /// non-semantic swatches. Wraps for ordinals beyond the sequence length.
    public func chartCategorical(_ i: Int) -> Color {
        let order = Self.categoricalOrder
        return chart(order[i % order.count])
    }

    /// Slot-remap sequence for `chartCategorical` — see its doc comment for the
    /// hue-separation rationale. Kept as a named constant so tests can pin it.
    public static let categoricalOrder = [1, 3, 7, 2, 4, 0, 5]
}

// MARK: - Design tokens (shape, spacing, type) — one language, all platforms

public enum Radius {
    public static let card: CGFloat = 14
    public static let inner: CGFloat = 10
}

public enum Space {
    public static let cardPadding: CGFloat = 16
    public static let gap: CGFloat = 12
    public static let contentMaxWidth: CGFloat = 1200
}

public enum TypeScale {
    public static let display = Font.system(size: 26, weight: .semibold).monospacedDigit()
    public static let title = Font.system(size: 16, weight: .semibold)
    public static let body = Font.system(size: 14)
    public static let meta = Font.system(size: 12)
    public static let num = Font.system(size: 14).monospacedDigit()
}

// MARK: - Environment plumbing

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(seed: .appleBlue, neutral: .slate)
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

public extension View {
    /// Resolve the theme from a (seed, neutral) + the current colorScheme.
    func designTheme(seed: Seed = .appleBlue, neutral: Neutral = .slate) -> some View {
        modifier(ThemeResolver(seed: seed, neutral: neutral))
    }
}

private struct ThemeResolver: ViewModifier {
    let seed: Seed
    let neutral: Neutral
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = Theme(seed: seed, neutral: neutral, isDark: scheme == .dark)
        content
            .environment(\.theme, theme)
            .background(theme.neutrals.bg)
            .foregroundStyle(theme.neutrals.text1)
    }
}
