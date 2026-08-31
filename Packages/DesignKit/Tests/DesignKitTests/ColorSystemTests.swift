import Testing
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import DesignKit

/// Resolved sRGB hex of a `Color`.
///
/// `Color` equality is by CONSTRUCTION, not by value: a color built with
/// `Color(hue:saturation:brightness:)` is never `==` to the `Color(hex:)`
/// naming the same pixel. Golden assertions on derived tokens therefore have
/// to compare resolved components, not the `Color` values themselves.
func resolvedHex(_ color: Color) -> String {
    #if canImport(AppKit)
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
    let r = Int((ns.redComponent * 255).rounded())
    let g = Int((ns.greenComponent * 255).rounded())
    let b = Int((ns.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", r, g, b)
    #else
    return "#000000"
    #endif
}

/// HSB components of a `Color`, resolved the same way `ColorSystem` resolves
/// them internally. Mirrors the source's private `hsbComponents` so a test
/// can restate the web derivation independently of the implementation.
func testHSB(_ color: Color) -> (h: Double, s: Double, b: Double) {
    #if canImport(AppKit)
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return (Double(h), Double(s), Double(b))
    #else
    return (0.58, 0.8, 0.9)
    #endif
}

/// Whether `color` resolves to `hex` within `tolerance` per 8-bit channel.
///
/// Tokens that pass through an HSB round-trip (`Color(hue:saturation:
/// brightness:)`) can land a step off the arithmetic value depending on how
/// the component read resolves. A ±2/255 window is far tighter than any real
/// palette drift — the olive regression this suite guards against differs by
/// ~95/255 in the red channel — while staying immune to that rounding.
func resolves(_ color: Color, to hex: String, tolerance: Int = 2) -> Bool {
    func channels(_ s: String) -> [Int] {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return stride(from: 0, to: 6, by: 2).map {
            let i = t.index(t.startIndex, offsetBy: $0)
            return Int(t[i ..< t.index(i, offsetBy: 2)], radix: 16) ?? -1
        }
    }
    return zip(channels(resolvedHex(color)), channels(hex)).allSatisfy { abs($0 - $1) <= tolerance }
}

@Suite("Seed color system")
struct ColorSystemTests {
    @Test("all preset seeds parse to a hex")
    func seeds() {
        #expect(Seed.allCases.count == 6)
        #expect(Seed.blue.hex == "#0090FF")
        #expect(Seed.lime.hex == "#5A8A00")
    }

    @Test("primary palette derives distinct light/dark primaries")
    func palette() {
        let light = makePrimaryPalette(seed: Seed.blue.color, isDark: false)
        let dark = makePrimaryPalette(seed: Seed.blue.color, isDark: true)
        // onPrimary is black or white — a real WCAG choice was made
        #expect(light.onPrimary == .white || light.onPrimary == .black)
        #expect(dark.onPrimary == .white || dark.onPrimary == .black)
    }

    @Test("dark lime resolves to the mandated signature color")
    func darkLimeIsTheSignature() {
        // constitution 1.7.0 / design/north-star.md §10: the cockpit
        // signature is `#C6F04A` on near-black. This is the acceptance
        // criterion for MY-1399 — before the anchor, the generic `b + 0.06`
        // lift produced `#679908`, an unusably dark olive.
        let theme = Theme(seed: .lime, neutral: .slate, isDark: true)
        #expect(resolvedHex(theme.primary.primary) == "#C6F04A")
        #expect(Seed.lime.darkAnchorHex == "#C6F04A")
    }

    @Test("light lime is unchanged — the anchor is dark-only")
    func lightLimeIsUnchanged() {
        #expect(Seed.lime.hex == "#5A8A00")
        let theme = Theme(seed: .lime, neutral: .slate, isDark: false)
        #expect(resolvedHex(theme.primary.primary) == "#5A8A00")
    }

    @Test("only lime pins a dark anchor — the other seeds keep the shared math")
    func onlyLimeIsAnchored() {
        for seed in Seed.allCases where seed != .lime {
            #expect(seed.darkAnchor == nil, "\(seed.rawValue) must not pin a dark anchor")
        }
        // The unanchored dark derivation is the verbatim web math
        // (`c(h, s - 0.05, b + 0.06)`). Pinned as golden values so a future
        // anchor change cannot silently alter the other five seeds.
        #expect(resolves(Theme(seed: .blue, isDark: true).primary.primary, to: "#0D96FF"))
        #expect(resolves(Theme(seed: .purple, isDark: true).primary.primary, to: "#9E5FD5"))
        #expect(resolves(Theme(seed: .teal, isDark: true).primary.primary, to: "#1DB4A3"))
        #expect(resolves(Theme(seed: .orange, isDark: true).primary.primary, to: "#FF7622"))
        #expect(resolves(Theme(seed: .appleBlue, isDark: true).primary.primary, to: "#0D81FF"))
    }

    /// The unanchored dark subtle/muted/border chips, per seed.
    ///
    /// These are pinned SEPARATELY from `primary` because they derive from a
    /// different saturation base: the shared-with-web math multiplies the
    /// seed's own `s`, while `primary` uses `s - 0.05`. A refactor that
    /// routes the chips through the primary's base drifts them 1–3 per
    /// channel — visible to a golden, invisible to a primary-only test.
    private static let unanchoredDarkChips: [(Seed, subtle: String, muted: String, border: String)] = [
        (.blue, subtle: "#19252E", muted: "#213442", border: "#29465C"),
        (.purple, subtle: "#28212E", muted: "#392E42", border: "#4E3D5C"),
        (.teal, subtle: "#1B2E2C", muted: "#25423F", border: "#2F5C57"),
        (.orange, subtle: "#2E221B", muted: "#423024", border: "#5C3F2E"),
        (.appleBlue, subtle: "#19232E", muted: "#213142", border: "#29415C")
    ]

    @Test("unanchored dark subtle/muted/border keep the seed's own saturation base")
    func unanchoredDarkChipsAreGolden() {
        for (seed, subtle, muted, border) in Self.unanchoredDarkChips {
            let p = Theme(seed: seed, neutral: .slate, isDark: true).primary
            // Tolerance 1, not the default 2: the regression this guards
            // against is a 1–3 per-channel shift, so a ±2 window would let
            // two thirds of it through.
            #expect(resolves(p.primarySubtle, to: subtle, tolerance: 1),
                    "\(seed.rawValue) primarySubtle = \(resolvedHex(p.primarySubtle)), want \(subtle)")
            #expect(resolves(p.primaryMuted, to: muted, tolerance: 1),
                    "\(seed.rawValue) primaryMuted = \(resolvedHex(p.primaryMuted)), want \(muted)")
            #expect(resolves(p.primaryBorder, to: border, tolerance: 1),
                    "\(seed.rawValue) primaryBorder = \(resolvedHex(p.primaryBorder)), want \(border)")
        }
    }

    @Test("unanchored dark chips match the web formula exactly, not the primary's base")
    func unanchoredDarkChipsMatchWebFormula() {
        // Differential check against the web derivation spelled out here
        // independently of the implementation. Both sides are built through
        // the same `Color(hue:saturation:brightness:)` path, so this compares
        // EXACTLY (tolerance 0) and catches even a 1-per-channel drift that
        // the hex goldens above would round past.
        for seed in Seed.allCases where seed != .lime {
            let (h, s, _) = testHSB(seed.color)
            let p = Theme(seed: seed, neutral: .slate, isDark: true).primary
            let expected: [(String, Color, Color)] = [
                ("primarySubtle", p.primarySubtle, Color(hue: h, saturation: s * 0.45, brightness: 0.18)),
                ("primaryMuted", p.primaryMuted, Color(hue: h, saturation: s * 0.50, brightness: 0.26)),
                ("primaryBorder", p.primaryBorder, Color(hue: h, saturation: s * 0.55, brightness: 0.36))
            ]
            for (name, actual, want) in expected {
                #expect(resolvedHex(actual) == resolvedHex(want),
                        "\(seed.rawValue) \(name) = \(resolvedHex(actual)), web formula gives \(resolvedHex(want))")
            }
            // And prove the distinction is real: the primary's own base
            // (s - 0.05) would produce a DIFFERENT value for at least one
            // chip, so this test cannot pass by coincidence.
            let wrongBase = Color(hue: h, saturation: (s - 0.05) * 0.55, brightness: 0.36)
            #expect(resolvedHex(p.primaryBorder) != resolvedHex(wrongBase),
                    "\(seed.rawValue) primaryBorder still derives from the primary's base")
        }
    }

    @Test("the anchored dark ramp stays monotonic and derived from one anchor")
    func anchoredRampIsWellFormed() {
        let p = Theme(seed: .lime, neutral: .slate, isDark: true).primary
        // hover/active brighten away from the anchor without clipping into
        // one indistinguishable near-white.
        let steps = [p.primary, p.primaryHover, p.primaryActive].map(resolvedHex)
        #expect(Set(steps).count == 3, "ramp collapsed: \(steps)")
        // The whole ramp shares the anchor's hue: still ONE seed system.
        let anchorHue = hsbHue(Color(hex: "#C6F04A"))
        for color in [p.primary, p.primaryHover, p.primaryActive, p.primaryText, p.primaryBorder] {
            #expect(abs(hsbHue(color) - anchorHue) < 0.01, "ramp left the anchor hue")
        }
        // Lime is bright enough that black is the correct foreground on it.
        #expect(p.onPrimary == .black)
    }

    @Test("chart palette has 8 stops")
    func charts() {
        #expect(chartPalette(seed: Seed.teal.color, isDark: false).count == 8)
        #expect(chartPalette(seed: Seed.teal.color, isDark: true).count == 8)
    }

    @Test("classification tints are golden fixed values")
    func classificationGolden() {
        #expect(Classification.allCases.count == 10)
        // Light golden values (mirror Apple system palette). Locks the token so a
        // repo's copy can't silently drift.
        #expect(Classification.metric.tint(isDark: false) == Color(hex: "#007AFF"))
        #expect(Classification.insight.tint(isDark: false) == Color(hex: "#AF52DE"))
        #expect(Classification.trending.tint(isDark: false) == Color(hex: "#FF9500"))
        #expect(Classification.teamAudit.tint(isDark: false) == Color(hex: "#E6294D"))
        #expect(Classification.teamAudit.tint(isDark: true) == Color(hex: "#FF375F"))
        // barList is a low-key brown (a neutral ranking must NOT alarm), NOT a
        // red/pink; stackedBar is a warm yellow, distinct from trending orange.
        #expect(Classification.barList.tint(isDark: false) == Color(hex: "#A2845E"))
        #expect(Classification.stackedBar.tint(isDark: false) == Color(hex: "#FFCC00"))
        // relationship is a cyan that must not collapse into metric blue or
        // digest teal — the three ride the same cool arc of the wheel.
        #expect(Classification.relationship.tint(isDark: false) == Color(hex: "#0891B2"))
        #expect(Classification.relationship.tint(isDark: true) == Color(hex: "#22D3EE"))
        // Dark variant differs from light (dark mode is honored, not identical).
        #expect(Classification.metric.tint(isDark: true) != Classification.metric.tint(isDark: false))
        #expect(Classification.barList.tint(isDark: true) != Classification.barList.tint(isDark: false))
    }

    @Test("relationship cyan stays distinct from metric blue and digest teal")
    func relationshipDistinctFromCoolNeighbors() {
        for isDark in [false, true] {
            let relationship = Classification.relationship.tint(isDark: isDark)
            #expect(relationship != Classification.metric.tint(isDark: isDark))
            #expect(relationship != Classification.digest.tint(isDark: isDark))
        }
    }

    @Test("classification tints are pairwise distinguishable")
    func classificationDistinct() {
        for isDark in [false, true] {
            let tints = Classification.allCases.map { $0.tint(isDark: isDark) }
            let unique = Set(tints.map { String(describing: $0) })
            #expect(unique.count == Classification.allCases.count)
        }
    }
}

@Suite("Theme")
struct ThemeTests {
    @Test("theme resolves all three layers")
    func resolve() {
        let t = Theme(seed: .purple, neutral: .neutral, isDark: true)
        #expect(t.seed == .purple)
        #expect(t.charts.count == 8)
        // chart(_:) wraps around
        #expect(t.chart(8) == t.chart(0))
    }

    @Test("semantic colors are fixed regardless of seed")
    func semanticFixed() {
        let a = Theme(seed: .blue, neutral: .slate, isDark: false)
        let b = Theme(seed: .orange, neutral: .slate, isDark: false)
        #expect(a.success == b.success) // green=good never breaks
        #expect(a.danger == b.danger)
    }

    @Test("chartCategorical remaps ordinals through the [1,3,7,2,4,0,5] sequence")
    func chartCategoricalOrder() {
        #expect(Theme.categoricalOrder == [1, 3, 7, 2, 4, 0, 5])
        let t = Theme(seed: .lime, neutral: .slate, isDark: true)
        // The ordinal is remapped, not identity: category 0 → chart stop 1.
        #expect(t.chartCategorical(0) == t.chart(1))
        #expect(t.chartCategorical(1) == t.chart(3))
        #expect(t.chartCategorical(2) == t.chart(7))
        // Wraps past the sequence length.
        #expect(t.chartCategorical(7) == t.chartCategorical(0))
    }

    @Test("chartCategorical keeps the first categories mutually distinct")
    func chartCategoricalDistinct() {
        let t = Theme(seed: .lime, neutral: .slate, isDark: true)
        let first4 = (0..<4).map { t.chartCategorical($0) }
        let unique = Set(first4.map { String(describing: $0) })
        #expect(unique.count == 4, "the first four categorical slots must be visually distinct")
    }
}
