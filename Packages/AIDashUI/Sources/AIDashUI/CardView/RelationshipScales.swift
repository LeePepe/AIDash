import SwiftUI
import Charts
import AIDashCore
import DesignKit

// MARK: - RelationshipHeatmapScale
//
// Maps a cell value to the *strength* (0…1) its rectangle is drawn at. The
// intensity channel is a single-hue ramp on the relationship classification
// tint, so a heatmap never invents a second color language.
//
// The domain is derived from the finite cell values. A FLAT domain (every
// cell equal, or a single cell, or no cells at all) would divide by zero in
// the naive `(v - min) / (max - min)` normalization — and a NaN opacity
// blanks the entire chart, not just one cell. The flat case therefore
// resolves to a fixed midpoint strength: every cell reads identically,
// which is exactly what "all values are equal" means.

enum RelationshipHeatmapScale {

    struct Domain: Equatable {
        let min: Double
        let max: Double

        /// True when the domain has no spread to normalize against.
        var isFlat: Bool { !(max > min) }
    }

    /// Weakest rendered strength. Kept well above zero so the coldest cell is
    /// still a visible mark rather than a hole in the matrix.
    static let minStrength: Double = 0.14
    /// Strongest rendered strength. Below 1 so the hottest cell stays a tinted
    /// surface rather than a saturated block that fights the card chrome.
    static let maxStrength: Double = 0.92
    /// Strength used when the domain is flat — the midpoint of the ramp.
    static let flatStrength: Double = (minStrength + maxStrength) / 2

    /// Domain over the finite values only. Non-finite values are rejected by
    /// `RelationshipPayload.validateInvariants()`, but the renderer decodes
    /// without validating, so they are filtered here too.
    static func domain(_ values: [Double]) -> Domain {
        let finite = values.filter(\.isFinite)
        guard let lo = finite.min(), let hi = finite.max() else {
            return Domain(min: 0, max: 0)
        }
        return Domain(min: lo, max: hi)
    }

    /// Strength for one cell, clamped into `[minStrength, maxStrength]`.
    static func strength(for value: Double, in domain: Domain) -> Double {
        guard value.isFinite else { return flatStrength }
        guard !domain.isFlat else { return flatStrength }
        let t = (value - domain.min) / (domain.max - domain.min)
        let clamped = Swift.min(Swift.max(t, 0), 1)
        return minStrength + clamped * (maxStrength - minStrength)
    }

    /// The single hue the ramp is built on — the card type's own classification
    /// token, resolved from the injected Theme (never a literal).
    static func baseColor(_ theme: Theme) -> Color {
        theme.classificationTint(.relationship)
    }
}

// MARK: - RelationshipSymbolScale
//
// Scatter symbol area from the optional `magnitude` third dimension. Symbol
// AREA is proportional to magnitude (Swift Charts' `symbolSize` takes an
// area), which is the perceptually honest mapping — scaling the radius
// instead exaggerates large values quadratically.
//
// `magnitude` is optional PER POINT, so one payload can mix points that carry
// it with points that don't. That mixed case is the dangerous one: rendering
// a magnitude-less point as an ordinary mid-size solid symbol makes ABSENT
// data indistinguishable from a genuine mid-low reading, so the chart asserts
// a third dimension it does not actually have for that point. In a mixed
// payload a missing magnitude therefore renders as a SMALL HOLLOW symbol —
// smaller than the smallest real reading and unfilled, so it reads as "no
// data" in both size and fill, and survives grayscale.
//
// When NO point carries a magnitude there is no third dimension at all, and
// every point is an ordinary uniform solid symbol — flagging them all as
// missing would be noise.

enum RelationshipSymbolScale {

    typealias Domain = RelationshipHeatmapScale.Domain

    /// Symbol area for a uniform (no magnitude dimension) scatter.
    static let baseSize: Double = 120
    /// Floor for a scaled symbol. Sized so the smallest real reading is still
    /// a legible disc (~10.7pt across), not a speck.
    static let minSize: Double = 90
    /// Ceiling for a scaled symbol, so one outlier cannot swallow its neighbors.
    static let maxSize: Double = 260
    /// Area for a magnitude-less point inside a MIXED payload. Below `minSize`
    /// so absence reads as smaller than any present value — but large enough
    /// (~9pt across) that the hollow centre is actually visible. An earlier
    /// 14pt² ring left a 1.2pt hole, which rendered as a tiny solid dot and
    /// silently defeated the whole point of the hollow channel.
    static let missingSize: Double = 64

    static func domain(_ magnitudes: [Double]) -> Domain {
        RelationshipHeatmapScale.domain(magnitudes)
    }

    /// True when this point has no usable magnitude. A non-finite magnitude is
    /// missing data too — rendering NaN as an area would blank the mark.
    static func isMissing(magnitude: Double?) -> Bool {
        guard let magnitude else { return true }
        return !magnitude.isFinite
    }

    /// Missing-ness that matters for RENDERING: only meaningful inside a mixed
    /// payload. With no magnitude dimension at all, nothing is "missing".
    static func isMissing(magnitude: Double?, inMixedPayload: Bool) -> Bool {
        inMixedPayload && isMissing(magnitude: magnitude)
    }

    /// True when SOME points carry a magnitude and others do not — the case
    /// where absence must be made visible.
    static func hasMixedMagnitudes(_ points: [RelationshipPayload.Point]) -> Bool {
        let withMagnitude = points.filter { !isMissing(magnitude: $0.magnitude) }.count
        return withMagnitude > 0 && withMagnitude < points.count
    }

    static func size(for magnitude: Double?, in domain: Domain) -> Double {
        guard let magnitude, magnitude.isFinite else { return baseSize }
        guard !domain.isFlat else { return baseSize }
        let t = (magnitude - domain.min) / (domain.max - domain.min)
        let clamped = Swift.min(Swift.max(t, 0), 1)
        return minSize + clamped * (maxSize - minSize)
    }

    /// Rendering size that accounts for the mixed case: a magnitude-less point
    /// in a mixed payload collapses to the distinct `missingSize`.
    static func size(for magnitude: Double?, in domain: Domain, inMixedPayload: Bool) -> Double {
        if isMissing(magnitude: magnitude, inMixedPayload: inMixedPayload) { return missingSize }
        return size(for: magnitude, in: domain)
    }
}

// MARK: - RelationshipCategoryPalette
//
// Resolves a scatter point's optional `category` to a categorical color slot.
// Slots are assigned in FIRST-APPEARANCE order over the payload's own category
// sequence, so the legend reads top-to-bottom in the order the author wrote
// the points.
//
// `category` is optional PER POINT, so one payload can mix categorized points
// with uncategorized ones. That mixed case is the dangerous one, and it is the
// direct analogue of the mixed-`magnitude` case above: folding an uncategorized
// point into the first real category makes ABSENT grouping indistinguishable
// from membership, so the chart asserts the point belongs to a group it was
// never placed in — in its color AND in the legend key that describes it. An
// uncategorized point therefore gets its OWN legend entry, drawn in a neutral
// (non-categorical) token, so absence reads as absence.
//
// The color for a real category always comes from `Theme.chartCategorical`,
// whose remap keeps the first categories ≥40° apart in hue and clear of the
// semantic hues — the same rule stackedBar's pure-category segments follow.

enum RelationshipCategoryPalette {

    /// True when a point carries no usable grouping key. An empty string is
    /// absence too — a blank legend row explains nothing.
    static func isUncategorized(_ category: String?) -> Bool {
        guard let category, !category.isEmpty else { return true }
        return false
    }

    /// Distinct categories in first-appearance order.
    static func ordered(_ categories: [String?]) -> [String] {
        var seen: Set<String> = []
        var order: [String] = []
        for category in categories where !isUncategorized(category) {
            guard let category else { continue }
            if seen.insert(category).inserted { order.append(category) }
        }
        return order
    }

    /// Ordinal of a REAL category within its payload's category sequence.
    ///
    /// This addresses the categorical palette only. It deliberately does NOT
    /// model absence: a nil / empty / unknown category has no ordinal, and the
    /// `0` returned here is a palette fallback, not a claim of membership.
    /// Legend keying and per-point coloring must go through `Legend` instead,
    /// which gives an uncategorized point its own entry.
    static func slot(for category: String?, in categories: [String?]) -> Int {
        guard !isUncategorized(category), let category else { return 0 }
        return ordered(categories).firstIndex(of: category) ?? 0
    }

    static func color(slot: Int, theme: Theme) -> Color {
        theme.chartCategorical(slot)
    }

    /// Color for the uncategorized legend row. Deliberately NOT a categorical
    /// slot: every `chartCategorical` color reads as "a group", and absence of
    /// a group is not one. The neutral `meta` tier is the token that already
    /// means "present but non-essential", and it clears the 3:1 non-text
    /// contrast floor on every ground, so the mark stays visible.
    static func uncategorizedColor(_ theme: Theme) -> Color {
        theme.neutrals.text(.meta)
    }

    /// The scatter's color KEY: the resolved legend domain plus the mapping
    /// from a point to its entry.
    ///
    /// This exists because a legend and a color assignment must not be derived
    /// independently. Swift Charts only emits a legend for a mark styled `by:`
    /// a data value against a declared scale, so the chart needs BOTH a domain
    /// (the legend rows, in order) and a per-point key — and if those two ever
    /// disagreed, the legend would confidently mislabel the plot. Resolving
    /// both from one value makes that class of drift unrepresentable.
    struct Legend: Equatable {

        /// Where one point sits in the color encoding. Three cases, because
        /// "no category" and "the first category" are genuinely different
        /// things and collapsing them is what made the plot lie.
        enum Entry: Equatable {
            /// The payload declares no categories at all — one uniform series,
            /// nothing for color to discriminate, legend hidden.
            case unkeyed
            /// A real category, at this ordinal in `categories`.
            case category(Int)
            /// No grouping key while siblings have one — its own legend row and
            /// its own non-categorical color.
            case uncategorized
        }

        /// Real categories in first-appearance order — the leading legend rows.
        /// Empty when no point carries a category at all.
        let categories: [String]

        /// The row uncategorized points belong to, present only when the payload
        /// MIXES them with real categories. nil when every point is categorized
        /// (nothing to explain), and nil when NO point is (there is no category
        /// encoding at all, so absence is not a distinction worth drawing).
        let uncategorizedKey: String?

        /// Legend rows in render order: real categories first, the uncategorized
        /// row last. Falls back to a single unkeyed row so the style scale always
        /// has a non-empty domain to bind against.
        var domain: [String] {
            guard !categories.isEmpty else { return [Self.unkeyed] }
            guard let uncategorizedKey else { return categories }
            return categories + [uncategorizedKey]
        }

        /// Whether the color channel actually discriminates anything. One key
        /// (or none) means every point is the same color, so a legend would be
        /// a row that explains nothing. One real category PLUS uncategorized
        /// points is two rows — two colors are genuinely on screen, and the
        /// reader needs to be told which is which.
        var isKeyed: Bool { domain.count > 1 }

        /// The encoding entry a point belongs to. An uncategorized point can
        /// never resolve to `.category`, so it can never be colored as, or
        /// described as, a group it was not placed in.
        func entry(for point: RelationshipPayload.Point) -> Entry {
            guard !categories.isEmpty else { return .unkeyed }
            if let category = point.category,
               !RelationshipCategoryPalette.isUncategorized(category),
               let index = categories.firstIndex(of: category) {
                return .category(index)
            }
            return .uncategorized
        }

        /// The legend entry a point belongs to, as the scale's domain value.
        func key(for point: RelationshipPayload.Point) -> String {
            switch entry(for: point) {
            case .unkeyed:              return Self.unkeyed
            case .category(let index):  return categories[index]
            case .uncategorized:        return uncategorizedKey ?? Self.unkeyed
            }
        }

        /// Row index of a point's entry within `domain` — the index its swatch
        /// occupies in `colors(theme:)`, so symbol and legend swatch agree.
        func slot(for point: RelationshipPayload.Point) -> Int {
            domain.firstIndex(of: key(for: point)) ?? 0
        }

        func color(for point: RelationshipPayload.Point, theme: Theme) -> Color {
            switch entry(for: point) {
            case .unkeyed:
                return RelationshipCategoryPalette.color(slot: 0, theme: theme)
            case .category(let index):
                return RelationshipCategoryPalette.color(slot: index, theme: theme)
            case .uncategorized:
                return RelationshipCategoryPalette.uncategorizedColor(theme)
            }
        }

        /// The scale's range: one color per domain entry, in domain order.
        func colors(theme: Theme) -> [Color] {
            guard !categories.isEmpty else {
                return [RelationshipCategoryPalette.color(slot: 0, theme: theme)]
            }
            let categoryColors = categories.indices.map {
                RelationshipCategoryPalette.color(slot: $0, theme: theme)
            }
            guard uncategorizedKey != nil else { return categoryColors }
            return categoryColors + [RelationshipCategoryPalette.uncategorizedColor(theme)]
        }

        /// Single key used when the payload carries no categories at all. The
        /// scale still needs a non-empty domain to bind against; the legend is
        /// hidden in that case, so this string never reaches the screen.
        static let unkeyed = "—"

        /// Legend row label for points that carry no grouping key while their
        /// siblings do. This one IS user-visible — it is the row a reader looks
        /// at to learn that those marks were never assigned a group.
        static let uncategorizedLabel = String(
            localized: "relationship.scatter.category.uncategorized",
            defaultValue: "Uncategorized",
            bundle: .module,
            comment: "Legend row for relationship scatter points that carry no category while other points in the same chart do. It labels absence of a grouping key, not a group named this."
        )

        /// The uncategorized row's key, guaranteed distinct from every real
        /// category. A payload may legitimately name a real category
        /// "Uncategorized"; two identical domain values would collapse into one
        /// row inside Swift Charts and reintroduce the exact conflation this
        /// entry exists to prevent, so the collision is broken visibly.
        static func uncategorizedKey(avoiding categories: [String]) -> String {
            var key = uncategorizedLabel
            while categories.contains(key) { key = "\(key) ·" }
            return key
        }
    }

    static func legend(for points: [RelationshipPayload.Point]) -> Legend {
        let categories = ordered(points.map(\.category))
        let hasUncategorized = points.contains { isUncategorized($0.category) }
        return Legend(
            categories: categories,
            uncategorizedKey: hasUncategorized && !categories.isEmpty
                ? Legend.uncategorizedKey(avoiding: categories)
                : nil
        )
    }
}

// MARK: - RelationshipDensity
//
// `size` is geometry and visible density ONLY (constitution §Size = Geometry
// Only): a smaller card plots fewer marks and stands shorter, but every mark
// it does plot is drawn at the same type scale. Nothing here returns a Font.

enum RelationshipDensity {

    /// How many marks a given geometry plots before truncating. Monotonic in
    /// the size ladder — a bigger card never shows fewer marks.
    static func visibleMarkCap(_ size: CardSize) -> Int {
        switch size {
        case .small:  return 8
        case .medium: return 16
        case .wide:   return 40
        case .hero:   return 80
        }
    }

    /// Plot height. Monotonic in the size ladder, and always below the size's
    /// own min-height so the evidence rail still has room to sit beside or
    /// under the chart.
    static func chartHeight(_ size: CardSize) -> CGFloat {
        switch size {
        case .small:  return 96
        case .medium: return 120
        case .wide:   return 160
        case .hero:   return 220
        }
    }

    /// Minimum width the evidence rail needs before `ViewThatFits` is willing
    /// to place it BESIDE the chart. Narrower than this and the horizontal
    /// candidate is rejected, so the rail drops below the chart at full width
    /// rather than squeezing into an unreadable column.
    static let evidenceRailMinWidth: CGFloat = 200
    /// Minimum width the chart itself needs in the side-by-side candidate.
    static let chartMinWidth: CGFloat = 220
}
