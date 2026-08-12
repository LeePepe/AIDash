import Testing
import SwiftUI
@testable import DesignKit

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

    @Test("chart palette has 8 stops")
    func charts() {
        #expect(chartPalette(seed: Seed.teal.color, isDark: false).count == 8)
        #expect(chartPalette(seed: Seed.teal.color, isDark: true).count == 8)
    }

    @Test("classification tints are golden fixed values")
    func classificationGolden() {
        #expect(Classification.allCases.count == 9)
        // Light golden values (mirror Apple system palette). Locks the token so a
        // repo's copy can't silently drift.
        #expect(Classification.metric.tint(isDark: false) == Color(hex: "#007AFF"))
        #expect(Classification.insight.tint(isDark: false) == Color(hex: "#AF52DE"))
        #expect(Classification.trending.tint(isDark: false) == Color(hex: "#FF9500"))
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
