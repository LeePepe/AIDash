import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// ============================================================================
//  Theme — the OS-appearance-adaptive token set for (seed, neutral).
//  `Theme.system` resolves every token directly at draw time from macOS
//  `NSAppearance` / iOS `UITraitCollection` with zero environment plumbing.
// ============================================================================

public struct Theme: Sendable {
    /// Global OS-dynamic system theme (`Seed.appleBlue` + `Neutral.slate`).
    public static let system = Theme()

    public let seed: Seed
    public let neutral: Neutral

    public let primary: PrimaryPalette
    public let neutrals: Neutrals
    public let charts: [Color]

    public var success: Color { Semantic.success }
    public var warning: Color { Semantic.warning }
    public var danger: Color { Semantic.danger }

    /// The three semantics as READABLE TEXT on a tint of themselves (status
    /// pills). The plain `success`/`warning`/`danger` above are FILL colors
    /// and do not meet small-text contrast in that role — see `Semantic`.
    public var successOnSubtle: Color { Semantic.successOnSubtle }
    public var warningOnSubtle: Color { Semantic.warningOnSubtle }
    public var dangerOnSubtle: Color { Semantic.dangerOnSubtle }

    /// Text color for a semantic role — `body` is accessible by construction.
    /// Prefer this over reaching for `neutrals.text1/2/3` directly.
    public func text(_ role: TextRole) -> Color { neutrals.text(role) }

    /// Per-category icon-badge tint, resolved dynamically for OS appearance.
    public func classificationTint(_ kind: Classification) -> Color {
        kind.dynamicTint
    }

    /// OS-dynamic theme. All palettes resolve light vs dark dynamically at draw time
    /// via `NSAppearance` / `UITraitCollection`.
    public init(seed: Seed = .appleBlue, neutral: Neutral = .slate) {
        self.seed = seed
        self.neutral = neutral
        self.primary = makeDynamicPrimaryPalette(seed: seed.color, darkAnchor: seed.darkAnchor)
        self.neutrals = neutral.dynamicPalette
        self.charts = dynamicChartPalette(seed: seed.color)
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
