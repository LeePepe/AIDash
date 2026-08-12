import Testing
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import DesignKit

// ============================================================================
//  ContrastTests — the accessibility half of the token contract.
//
//  ColorSystemTests pins token VALUES (golden hex). This suite pins what
//  those values have to DO: every text role and every status pill must be
//  readable on every ground DesignKit ships, in BOTH schemes.
//
//  The ratios are measured, not asserted from a table — a future token edit
//  that keeps the hex "looking right" but drops below the bar fails here.
// ============================================================================

/// WCAG 2.1 relative luminance / contrast ratio, computed on the resolved
/// sRGB components. Mirrors the private `relLuminance` in ColorSystem so the
/// test measures the SHIPPED color rather than re-deriving it.
enum WCAG {
    static func luminance(_ color: Color) -> Double {
        #if canImport(AppKit)
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func lin(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(ns.redComponent)
            + 0.7152 * lin(ns.greenComponent)
            + 0.0722 * lin(ns.blueComponent)
        #else
        return 0.5
        #endif
    }

    static func ratio(_ a: Color, _ b: Color) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Source-over composite of `fg` at `alpha` onto `bg` — how SwiftUI
    /// resolves `fill.opacity(x)` over a ground. Needed because a status
    /// pill's text sits on a TINT, not on the raw neutral.
    static func composite(_ fg: Color, over bg: Color, alpha: Double) -> Color {
        #if canImport(AppKit)
        let f = NSColor(fg).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(bg).usingColorSpace(.sRGB) ?? .black
        func mix(_ x: CGFloat, _ y: CGFloat) -> Double { alpha * Double(x) + (1 - alpha) * Double(y) }
        return Color(.sRGB,
                     red: mix(f.redComponent, b.redComponent),
                     green: mix(f.greenComponent, b.greenComponent),
                     blue: mix(f.blueComponent, b.blueComponent),
                     opacity: 1)
        #else
        return bg
        #endif
    }

    /// WCAG AA for small text.
    static let smallText = 4.5
    /// WCAG AA for large text / non-text UI — the floor for the `meta` role.
    static let largeText = 3.0
}

/// Every (neutral palette × scheme) DesignKit ships, with its three grounds.
/// A token is only accessible if it holds across ALL of them — a value tuned
/// against `card` alone silently fails inside a `CardInner`.
private struct Ground {
    let neutral: Neutral
    let isDark: Bool
    var label: String { "\(neutral.rawValue)/\(isDark ? "dark" : "light")" }
    var neutrals: Neutrals { neutral.palette(isDark: isDark) }
    var all: [(String, Color)] {
        [("card", neutrals.card), ("inner", neutrals.inner), ("bg", neutrals.bg)]
    }

    static let every: [Ground] = Neutral.allCases.flatMap { n in
        [false, true].map { Ground(neutral: n, isDark: $0) }
    }
}

@Suite("Text role contrast")
struct TextRoleContrastTests {
    @Test("body text clears AA small-text contrast on every ground, both schemes")
    func bodyIsAccessible() {
        for ground in Ground.every {
            let body = ground.neutrals.text(.body)
            for (name, bg) in ground.all {
                let r = WCAG.ratio(body, bg)
                #expect(r >= WCAG.smallText,
                        "\(ground.label) body on \(name) = \(r), needs >= \(WCAG.smallText)")
            }
        }
    }

    @Test("meta text clears the 3:1 floor on every ground, both schemes")
    func metaClearsFloor() {
        for ground in Ground.every {
            let meta = ground.neutrals.text(.meta)
            for (name, bg) in ground.all {
                let r = WCAG.ratio(meta, bg)
                #expect(r >= WCAG.largeText,
                        "\(ground.label) meta on \(name) = \(r), needs >= \(WCAG.largeText)")
            }
        }
    }

    @Test("body role never resolves to text3 — north-star §4 made enforceable")
    func bodyIsNotTheFaintestTier() {
        for ground in Ground.every {
            #expect(ground.neutrals.text(.body) != ground.neutrals.text3,
                    "\(ground.label): body must not be the meta tier")
            #expect(ground.neutrals.text(.body) == ground.neutrals.text2)
            #expect(ground.neutrals.text(.heading) == ground.neutrals.text1)
            #expect(ground.neutrals.text(.meta) == ground.neutrals.text3)
        }
    }

    @Test("the three tiers stay ordered heading > body > meta in contrast")
    func tiersAreOrdered() {
        for ground in Ground.every {
            let card = ground.neutrals.card
            let heading = WCAG.ratio(ground.neutrals.text(.heading), card)
            let body = WCAG.ratio(ground.neutrals.text(.body), card)
            let meta = WCAG.ratio(ground.neutrals.text(.meta), card)
            #expect(heading > body, "\(ground.label): heading \(heading) must exceed body \(body)")
            #expect(body > meta, "\(ground.label): body \(body) must exceed meta \(meta)")
        }
    }
}

@Suite("Status pill contrast")
struct StatusPillContrastTests {
    /// Mirrors `StatusPill`'s recipe: text over `fill.opacity(fillOpacity)`.
    private func pillRatio(text: Color, fill: Color, over ground: Color) -> Double {
        WCAG.ratio(text, WCAG.composite(fill, over: ground, alpha: 0.12))
    }

    @Test("every semantic pill tone is readable on its own tint, both schemes")
    func semanticTonesAreReadable() {
        for ground in Ground.every {
            let dark = ground.isDark
            let tones: [(String, Color, Color)] = [
                ("success", Semantic.success(isDark: dark), Semantic.successOnSubtle(isDark: dark)),
                ("warning", Semantic.warning(isDark: dark), Semantic.warningOnSubtle(isDark: dark)),
                ("danger", Semantic.danger(isDark: dark), Semantic.dangerOnSubtle(isDark: dark))
            ]
            for (tone, fill, text) in tones {
                for (name, bg) in ground.all {
                    let r = pillRatio(text: text, fill: fill, over: bg)
                    #expect(r >= WCAG.smallText,
                            "\(ground.label) \(tone) pill on \(name) = \(r), needs >= \(WCAG.smallText)")
                }
            }
        }
    }

    @Test("the neutral pill pairs a meta fill with body text, not text-on-itself")
    func neutralToneIsReadable() {
        for ground in Ground.every {
            for (name, bg) in ground.all {
                let r = pillRatio(text: ground.neutrals.text(.body), fill: ground.neutrals.text3, over: bg)
                #expect(r >= WCAG.smallText,
                        "\(ground.label) neutral pill on \(name) = \(r), needs >= \(WCAG.smallText)")
            }
        }
    }

    @Test("the primary pill is readable for EVERY seed, both schemes")
    func primaryToneIsReadableForAllSeeds() {
        for seed in Seed.allCases {
            for ground in Ground.every {
                let theme = Theme(seed: seed, neutral: ground.neutral, isDark: ground.isDark)
                for (name, bg) in ground.all {
                    let r = pillRatio(text: theme.primary.onPrimarySubtle,
                                      fill: theme.primary.primary, over: bg)
                    #expect(r >= WCAG.smallText,
                            "\(seed.rawValue) \(ground.label) primary pill on \(name) = \(r), needs >= \(WCAG.smallText)")
                }
            }
        }
    }

    @Test("on-subtle text is a DISTINCT value from the fill it sits on")
    func onSubtleIsNotTheFill() {
        // The original bug in one assertion: text and fill were the same
        // color, so the pill was text on a 16% wash of itself (1.93:1).
        // Light mode must always differ; dark success/warning are already
        // legible on their own tint and are deliberately left unchanged.
        #expect(WCAG.ratio(Semantic.successOnSubtle(isDark: false), Semantic.success(isDark: false)) > 1.0)
        #expect(WCAG.ratio(Semantic.warningOnSubtle(isDark: false), Semantic.warning(isDark: false)) > 1.0)
        #expect(WCAG.ratio(Semantic.dangerOnSubtle(isDark: false), Semantic.danger(isDark: false)) > 1.0)
        #expect(WCAG.ratio(Semantic.dangerOnSubtle(isDark: true), Semantic.danger(isDark: true)) > 1.0)
    }

    @Test("on-subtle variants keep their hue — green still reads as green")
    func onSubtleKeepsHue() {
        for dark in [false, true] {
            let pairs = [
                (Semantic.success(isDark: dark), Semantic.successOnSubtle(isDark: dark)),
                (Semantic.warning(isDark: dark), Semantic.warningOnSubtle(isDark: dark)),
                (Semantic.danger(isDark: dark), Semantic.dangerOnSubtle(isDark: dark))
            ]
            for (fill, text) in pairs {
                let delta = abs(hsbHue(fill) - hsbHue(text))
                // Within 8° on the wheel: a legibility calibration of the
                // same semantic, not a swap to a different color.
                #expect(min(delta, 1 - delta) <= 8.0 / 360.0,
                        "hue drifted by \(min(delta, 1 - delta) * 360)°")
            }
        }
    }
}
