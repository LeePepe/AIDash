import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// ============================================================================
//  ColorSystem — the seed color system, shared verbatim with the web port
//  (design-system/templates/shared/color-system.ts) and with the
//  visual-design-modernization skill's references/color-system.md.
//
//  ONE seed → the whole primary token set. Semantic colors are FIXED.
//  Neutrals come from Radix slate or Tailwind neutral. Never invent a 2nd set.
// ============================================================================

public extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Preset seeds (identical to the web port)

public enum Seed: String, CaseIterable, Sendable {
    case blue, purple, teal, orange, appleBlue, lime

    public var hex: String {
        switch self {
        case .blue: return "#0090FF"
        case .purple: return "#8E4EC6"
        case .teal: return "#12A594"
        case .orange: return "#F76B15"
        case .appleBlue: return "#007AFF"
        // Electric-lime cockpit signal. The light value is deepened so the
        // accent survives on a white ground; the dark value is NOT derived
        // from it — see `darkAnchorHex`. Calibrated in the cockpit prototype.
        case .lime: return "#5A8A00"
        }
    }

    public var color: Color { Color(hex: hex) }

    /// An explicit dark-scheme primary for seeds whose light value cannot
    /// reach the required dark signature by brightness lift alone.
    ///
    /// The generic dark rule (`b + 0.06`, see `makePrimaryPalette`) assumes
    /// the light seed already sits near its dark target in hue and
    /// saturation, and only needs to be brought up off near-black. That
    /// assumption holds for the five Radix/Apple seeds, whose light values
    /// are already mid-to-high brightness.
    ///
    /// It does NOT hold for `lime`. Its light value `#5A8A00` is deliberately
    /// deepened to survive a white ground: hue 80.9°, saturation 1.00,
    /// brightness 0.54. The constitution 1.7.0 / `design/north-star.md` §10
    /// signature is `#C6F04A` — hue 75.2°, saturation 0.69, brightness 0.94.
    /// Hue must fall ~6° and saturation must DROP ~0.31; no brightness lift
    /// reaches it. `b + 0.06` yields `#679908`, a dark olive at 4.99:1 on the
    /// card ground where the signature reads 12.97:1.
    ///
    /// So this is a second value for ONE seed, not a second palette: the
    /// whole dark ramp is still derived from this single anchor by the same
    /// HSB math, and `Semantic` / `Classification` are untouched. Seeds that
    /// return `nil` keep the verbatim shared-with-web derivation.
    public var darkAnchorHex: String? {
        switch self {
        case .lime: return "#C6F04A"
        case .blue, .purple, .teal, .orange, .appleBlue: return nil
        }
    }

    /// The dark-scheme primary anchor, when this seed pins one.
    public var darkAnchor: Color? { darkAnchorHex.map { Color(hex: $0) } }
}

// MARK: - Primary palette derivation

public struct PrimaryPalette: Sendable {
    public let primary, primaryHover, primaryActive: Color
    public let primarySubtle, primaryMuted, primaryBorder: Color
    public let primaryText, onPrimary, onPrimarySubtle, ring: Color
}

private func hsbComponents(_ c: Color) -> (h: Double, s: Double, b: Double) {
    #if canImport(AppKit)
    let ns = NSColor(c).usingColorSpace(.deviceRGB) ?? .black
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return (Double(h), Double(s), Double(b))
    #else
    return (0.58, 0.8, 0.9)
    #endif
}

public func hsbHue(_ c: Color) -> Double { hsbComponents(c).h }

private func relLuminance(_ c: Color) -> Double {
    #if canImport(AppKit)
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? .black
    func lin(_ v: CGFloat) -> Double {
        let x = Double(v)
        return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(ns.redComponent) + 0.7152 * lin(ns.greenComponent) + 0.0722 * lin(ns.blueComponent)
    #else
    return 0.5
    #endif
}

private func contrastChoose(_ bg: Color) -> Color {
    let lum = relLuminance(bg)
    return (1.05 / (lum + 0.05)) >= ((lum + 0.05) / 0.05) ? .white : .black
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

/// One seed → the whole primary token set. Same math as the web `makePrimaryPalette`.
///
/// `darkAnchor` overrides only the DARK primary hue/saturation/brightness
/// starting point (see `Seed.darkAnchorHex`); the rest of the dark ramp is
/// still derived from it by the same HSB relationships, so the "one seed
/// system" holds. Pass `nil` (the default) for the verbatim shared-with-web
/// derivation.
public func makePrimaryPalette(seed: Color, isDark: Bool, darkAnchor: Color? = nil) -> PrimaryPalette {
    let (h, s, b) = hsbComponents(seed)
    func c(_ hh: Double, _ ss: Double, _ bb: Double) -> Color {
        Color(hue: hh, saturation: clamp(ss), brightness: clamp(bb))
    }
    if isDark {
        // An anchored seed derives its ramp from the anchor's own HSB, so the
        // signature color IS the primary rather than a lift away from it.
        // Steps scale with the anchor's remaining headroom (`1 - b`) instead
        // of the fixed +0.06/+0.08/+0.14 the unanchored path uses: a bright
        // anchor has little room left, and fixed steps would clip hover and
        // active into the same near-white.
        let (ah, asat, ab) = darkAnchor.map(hsbComponents) ?? (h, s - 0.05, b + 0.06)
        let headroom = max(0, 1 - ab)
        let isAnchored = darkAnchor != nil
        // An anchored primary is the anchor ITSELF, not an HSB round-trip of
        // it — the signature color must land on its exact sRGB value.
        let primary = darkAnchor ?? c(ah, asat, ab)
        return PrimaryPalette(
            primary: primary,
            primaryHover: isAnchored ? c(ah, asat * 0.88, ab + headroom * 0.35) : c(h, s, b + 0.08),
            primaryActive: isAnchored ? c(ah, asat * 0.72, ab + headroom * 0.70) : c(h, s, b + 0.14),
            primarySubtle: c(ah, asat * 0.45, 0.18),
            primaryMuted: c(ah, asat * 0.50, 0.26),
            primaryBorder: c(ah, asat * 0.55, 0.36),
            primaryText: isAnchored ? c(ah, asat * 0.70, ab + headroom * 0.55) : c(h, s * 0.70, b + 0.28),
            onPrimary: contrastChoose(primary),
            onPrimarySubtle: isAnchored ? c(ah, asat * 0.70, ab + headroom * 0.55) : c(h, s * 0.70, b + 0.28),
            ring: primary.opacity(0.65)
        )
    } else {
        let primary = seed
        return PrimaryPalette(
            primary: primary,
            primaryHover: c(h, s, b - 0.08),
            primaryActive: c(h, s, b - 0.14),
            primarySubtle: c(h, s * 0.18, 0.97),
            primaryMuted: c(h, s * 0.40, 0.90),
            primaryBorder: c(h, s * 0.55, 0.80),
            primaryText: c(h, min(1, s + 0.10), b - 0.20),
            onPrimary: contrastChoose(primary),
            // Deeper than `primaryText`: this token is read as SMALL text on a
            // low-opacity tint of the primary (the status-pill fill), where
            // `b - 0.20` leaves the brightest seeds under 4.5:1 — `blue` lands
            // at 3.68:1 and `orange` at 3.71:1. `b * 0.60` scales with the
            // seed's own brightness instead of subtracting a fixed amount, so
            // every preset clears 4.5:1 on both the opaque `primarySubtle`
            // chip and the pill fill. `primaryText` keeps its own value: it is
            // a link/heading role on the page ground, not on a primary tint.
            onPrimarySubtle: c(h, min(1, s + 0.10), b * 0.60),
            ring: primary.opacity(0.55)
        )
    }
}

/// On-brand chart palette — walk the hue wheel from the seed (same offsets as web).
public func chartPalette(seed: Color, isDark: Bool) -> [Color] {
    let seedHue = hsbHue(seed) * 360
    let offsets: [Double] = [0, -15, 40, 95, 130, 175, -70, 210]
    return offsets.map { off in
        let h = (((seedHue + off).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)) / 360
        return isDark
            ? Color(hue: h, saturation: 0.66, brightness: 0.82)
            : Color(hue: h, saturation: 0.72, brightness: 0.62)
    }
}

// MARK: - Neutral palettes (fixed hex)

public struct Neutrals: Sendable {
    public let bg, card, inner, text1, text2, text3, border: Color
}

public enum Neutral: String, CaseIterable, Sendable {
    case slate, neutral

    public func palette(isDark: Bool) -> Neutrals {
        switch (self, isDark) {
        case (.slate, false):
            return Neutrals(bg: Color(hex: "#EDEEF2"), card: Color(hex: "#FFFFFF"), inner: Color(hex: "#F4F5F8"),
                            text1: Color(hex: "#1C2024"), text2: Color(hex: "#60646C"), text3: Color(hex: "#80838D"),
                            border: Color(hex: "#CDD0D8"))
        case (.slate, true):
            return Neutrals(bg: Color(hex: "#0E0F12"), card: Color(hex: "#1A1C20"), inner: Color(hex: "#242629"),
                            text1: Color(hex: "#EDEEF0"), text2: Color(hex: "#B0B4BA"), text3: Color(hex: "#777B84"),
                            border: Color(hex: "#3C4046"))
        case (.neutral, false):
            return Neutrals(bg: Color(hex: "#FAFAFA"), card: Color(hex: "#FFFFFF"), inner: Color(hex: "#F5F5F5"),
                            text1: Color(hex: "#171717"), text2: Color(hex: "#525252"), text3: Color(hex: "#737373"),
                            border: Color(hex: "#E5E5E5"))
        case (.neutral, true):
            // text3 is #7A7A7A, not the light palette's #737373: on this
            // palette's darker grounds the shared value fell to 3.19:1 on
            // `card` and 2.86:1 on `inner`, under the 3:1 floor the `meta`
            // role guarantees. Lifted to the nearest value clearing 3:1 on
            // all three grounds, so the tier stays visually a step below
            // text2 (3.53:1 vs 6.00:1 on card) while staying legible.
            return Neutrals(bg: Color(hex: "#171717"), card: Color(hex: "#262626"), inner: Color(hex: "#2E2E2E"),
                            text1: Color(hex: "#FAFAFA"), text2: Color(hex: "#A3A3A3"), text3: Color(hex: "#7A7A7A"),
                            border: Color(hex: "#404040"))
        }
    }
}

// MARK: - Semantic colors (FIXED — never seed-derived)

public enum Semantic {
    public static func success(isDark: Bool) -> Color { Color(hex: isDark ? "#30D158" : "#34C759") }
    public static func warning(isDark: Bool) -> Color { Color(hex: isDark ? "#FF9F0A" : "#FF9500") }
    public static func danger(isDark: Bool) -> Color { Color(hex: isDark ? "#FF453A" : "#FF3B30") }

    // ---- ON-SUBTLE variants: the same three semantics, as READABLE TEXT ----
    //
    // The values above are FILL colors: they are correct as a stripe, a bar,
    // a dot, or a pill background. They are NOT readable as small text on a
    // low-opacity tint of themselves, which is exactly what a status pill
    // asks of them. Measured on the pill recipe (`StatusPill`), the full-
    // saturation light values land at 1.95:1 (success), 1.93:1 (warning) and
    // 2.86:1 (danger) — far under the 4.5:1 small-text bar.
    //
    // These are darkened (light) / brightened (dark) variants of the SAME
    // three hues, calibrated so the text clears 4.5:1 against its own tint
    // over every neutral ground DesignKit ships (slate + neutral × card /
    // inner / bg). Hue is preserved, so green still reads as green — this is
    // a legibility calibration of the existing semantics, not a second
    // palette. The dark success/warning values are already legible and are
    // returned unchanged.

    /// `success` as small text on a `success`-tinted fill.
    public static func successOnSubtle(isDark: Bool) -> Color { Color(hex: isDark ? "#30D158" : "#0C7727") }
    /// `warning` as small text on a `warning`-tinted fill.
    public static func warningOnSubtle(isDark: Bool) -> Color { Color(hex: isDark ? "#FF9F0A" : "#965800") }
    /// `danger` as small text on a `danger`-tinted fill.
    public static func dangerOnSubtle(isDark: Bool) -> Color { Color(hex: isDark ? "#FF736A" : "#C3170E") }
}

// MARK: - Text roles
//
// `Neutrals` ships three brightness tiers; this maps them to the roles a
// consumer actually reaches for, so "which token do I use for body copy"
// has ONE answer that is accessible by construction. north-star.md §4 says
// "正文别用最淡的 text3(对比不足)" — that guidance is now enforceable
// rather than advisory: `TextRole.body` never resolves to `text3`.

public enum TextRole: String, CaseIterable, Sendable {
    /// Headings and primary numerals — the highest-contrast tier (`text1`).
    case heading
    /// Body copy, KPI subtitles, list rows — anything a reader READS.
    /// Resolves to `text2` (≥4.5:1 on every ground), never `text3`.
    case body
    /// Non-essential metadata: timestamps, index numbers, disabled glyphs.
    /// Resolves to `text3` (≥3:1). MUST NOT carry body copy.
    case meta
}

public extension Neutrals {
    /// Resolve a semantic text role to a concrete tier.
    ///
    /// The indirection exists so a consumer expresses INTENT ("this is body
    /// copy") rather than picking a brightness tier by eye — the failure mode
    /// that put KPI subtitles on `text3` at 1.69:1.
    func text(_ role: TextRole) -> Color {
        switch role {
        case .heading: return text1
        case .body: return text2
        case .meta: return text3
        }
    }
}

// MARK: - Classification tints (FIXED — per-category discriminator colors)
//
// One tint per content category, used as the leading icon-badge color so a
// reader tells categories apart by hue at a glance. These are NOT seed-derived:
// they must stay mutually distinguishable regardless of the active seed. Values
// are calibrated light/dark hex pairs tracking Apple's system palette (the hues
// the app shipped with) so dark mode keeps a proper variant.

public enum Classification: String, CaseIterable, Sendable {
    case metric, insight, digest, agentSummary, todoList, trending, barList, stackedBar
    case relationship

    /// Resolved tint for the current color scheme. Light/dark hex pairs mirror
    /// Apple's systemBlue/Purple/Teal/Indigo/Green/Orange.
    public func tint(isDark: Bool) -> Color {
        switch self {
        case .metric:       return Color(hex: isDark ? "#0A84FF" : "#007AFF") // blue
        case .insight:      return Color(hex: isDark ? "#BF5AF2" : "#AF52DE") // purple
        case .digest:       return Color(hex: isDark ? "#40C8E0" : "#30B0C7") // teal
        case .agentSummary: return Color(hex: isDark ? "#5E5CE6" : "#5856D6") // indigo
        case .todoList:     return Color(hex: isDark ? "#30D158" : "#34C759") // green
        case .trending:     return Color(hex: isDark ? "#FF9F0A" : "#FF9500") // orange
        // barList is a neutral ranking (failure root cause / app focus /
        // commits): a low-key brown that reads as "just data", NOT an alarm
        // hue — a red/pink tint would false-alarm a neutral leaderboard.
        case .barList:      return Color(hex: isDark ? "#B58A63" : "#A2845E") // brown
        // stackedBar is a composition-of-a-whole (session quality / model
        // tiers): a warm yellow badge, distinct from the orange trending hue.
        case .stackedBar:   return Color(hex: isDark ? "#FFD426" : "#FFCC00") // yellow
        // relationship is a cross-data correlation (cost×outcome, rework
        // concentration): a cyan that reads as "two things measured against
        // each other". It sits between metric blue and digest teal on the
        // wheel, so the pair is pushed apart deliberately — the light value
        // is deeper and the dark value brighter than either neighbor, keeping
        // all three separable at 32×32 badge size in both schemes.
        case .relationship: return Color(hex: isDark ? "#22D3EE" : "#0891B2") // cyan
        }
    }
}
