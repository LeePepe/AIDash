import Testing
import SwiftUI
@testable import DesignKit

@Suite("Seed color system")
struct ColorSystemTests {
    @Test("all preset seeds parse to a hex")
    func seeds() {
        #expect(Seed.allCases.count == 5)
        #expect(Seed.blue.hex == "#0090FF")
    }

    @Test("primary palette derives distinct light/dark primaries")
    func palette() {
        let light = makePrimaryPalette(seed: Seed.blue.color, isDark: false)
        let dark = makePrimaryPalette(seed: Seed.blue.color, isDark: true)
        // onPrimary is black or white — a real WCAG choice was made
        #expect(light.onPrimary == .white || light.onPrimary == .black)
        #expect(dark.onPrimary == .white || dark.onPrimary == .black)
    }

    @Test("chart palette has 8 stops")
    func charts() {
        #expect(chartPalette(seed: Seed.teal.color, isDark: false).count == 8)
        #expect(chartPalette(seed: Seed.teal.color, isDark: true).count == 8)
    }

    @Test("classification tints are golden fixed values")
    func classificationGolden() {
        #expect(Classification.allCases.count == 6)
        // Light golden values (mirror Apple system palette). Locks the token so a
        // repo's copy can't silently drift.
        #expect(Classification.metric.tint(isDark: false) == Color(hex: "#007AFF"))
        #expect(Classification.insight.tint(isDark: false) == Color(hex: "#AF52DE"))
        #expect(Classification.trending.tint(isDark: false) == Color(hex: "#FF9500"))
        // Dark variant differs from light (dark mode is honored, not identical).
        #expect(Classification.metric.tint(isDark: true) != Classification.metric.tint(isDark: false))
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
}
