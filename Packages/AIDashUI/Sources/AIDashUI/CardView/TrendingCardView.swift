import SwiftUI
import AIDashCore
import DesignKit

public struct TrendingCardView: View {
    let payload: TrendingPayload
    let size: CardSize
    let style: CardStyle
    @Environment(\.theme) private var theme

    public init(payload: TrendingPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardTypeBadge(type: .trending)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style)
    }

    // MARK: - Size-driven content selection (geometry/density only)

    @ViewBuilder
    private var content: some View {
        switch size {
        case .small:
            smallContent
        case .medium:
            mediumContent
        case .wide:
            wideContent
        case .hero:
            heroContent
        }
    }

    // MARK: - Small: topic + top-1 item

    @ViewBuilder
    private var smallContent: some View {
        topicLabel
        if let first = payload.items.first {
            TrendingItemRow(item: first, rank: 1, showScore: true, size: size)
        }
    }

    // MARK: - Medium: topic + top-3

    @ViewBuilder
    private var mediumContent: some View {
        topicLabel
        let top3 = Array(payload.items.prefix(3))
        ForEach(Array(top3.enumerated()), id: \.offset) { index, item in
            TrendingItemRow(item: item, rank: index + 1, showScore: true, size: size)
        }
        if payload.items.count > 3 {
            Text(Self.moreItemsLabel(overflow: payload.items.count - 3))
                .font(Self.recipe.secondary)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Wide: topic + top-5 with titles + scores

    @ViewBuilder
    private var wideContent: some View {
        topicLabel
        let top5 = Array(payload.items.prefix(5))
        ForEach(Array(top5.enumerated()), id: \.offset) { index, item in
            TrendingItemRow(item: item, rank: index + 1, showScore: true, size: size)
        }
        if payload.items.count > 5 {
            Text(Self.moreItemsLabel(overflow: payload.items.count - 5))
                .font(Self.recipe.secondary)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Hero: topic + top-10 with titles + scores + sparkline

    @ViewBuilder
    private var heroContent: some View {
        topicLabel
        let top10 = Array(payload.items.prefix(10))
        let scoredCount = top10.compactMap(\.score).count
        if scoredCount >= 2 {
            ScoreSparkline(items: top10, tint: sparklineColor)
                .frame(height: 40)
                .accessibilityElement()
                .accessibilityLabel(Self.sparklineAccessibilityLabel)
                .accessibilityValue(sparklineAccessibilityValue(for: top10))
        }
        ForEach(Array(top10.enumerated()), id: \.offset) { index, item in
            TrendingItemRow(item: item, rank: index + 1, showScore: true, size: size)
        }
    }

    @ViewBuilder
    private var topicLabel: some View {
        Text(payload.topic)
            .font(Self.recipe.secondary)
            .foregroundStyle(.secondary)
    }

    private func sparklineAccessibilityValue(for items: [TrendingPayload.Item]) -> String {
        let scores = items.compactMap(\.score)
        guard let max = scores.max(), let min = scores.min() else {
            return Self.sparklineEmptyValue
        }
        return Self.sparklineRangeValue(min: Int(min), max: Int(max))
    }

    // MARK: - Localized strings
    //
    // Per constitution §F.1, user-visible literals are accessed via
    // `String(localized:)` and registered in `Resources/Localizable.xcstrings`
    // so translators can localize them without touching source.

    static func moreItemsLabel(overflow: Int) -> String {
        String(
            localized: "trending.more_items \(overflow)",
            bundle: .module,
            comment: "Trailing line on a Trending card listing how many additional items were truncated. The integer is the overflow count (always ≥ 1)."
        )
    }

    static let sparklineAccessibilityLabel = String(
        localized: "trending.sparkline.accessibility_label",
        defaultValue: "Score distribution sparkline",
        bundle: .module,
        comment: "VoiceOver label for the Hero Trending card's score-distribution sparkline element."
    )

    static let sparklineEmptyValue = String(
        localized: "trending.sparkline.accessibility_value.empty",
        defaultValue: "No scores available",
        bundle: .module,
        comment: "VoiceOver value for the Trending sparkline when no items in the visible window carry a score."
    )

    static func sparklineRangeValue(min: Int, max: Int) -> String {
        String(
            localized: "trending.sparkline.accessibility_value.range \(min) \(max)",
            bundle: .module,
            comment: "VoiceOver value for the Trending sparkline describing the min/max of scored items. The integers are the minimum and maximum scores."
        )
    }

    // MARK: - Typography recipe

    static let recipe = AIDashTypography.detail(for: .trending)

    // MARK: - Sparkline color
    //
    // The sparkline is data, not chrome — it visualizes the score series. Its
    // tint is derived from `style` only as a content-coloring hint (matches
    // the metric trend-arrow precedent in §Style table). It does NOT change
    // card background, padding, radius, or any other chrome dimension.

    private var sparklineColor: Color {
        switch style {
        case .neutral: return .secondary
        case .success: return theme.success
        case .warning: return theme.warning
        case .accent:  return theme.primary.primary
        }
    }
}

// MARK: - TrendingItemRow

private struct TrendingItemRow: View {
    let item: TrendingPayload.Item
    let rank: Int
    let showScore: Bool
    let size: CardSize

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(TrendingCardView.recipe.primary)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(item.title)
                .font(TrendingCardView.recipe.secondary)
                .foregroundStyle(TrendingCardView.recipe.secondaryColor)
                .lineLimit(titleLineLimit)
            Spacer(minLength: 0)
            if showScore, let score = item.score {
                // Score as a neutral content-level pill (§Content-Level Status
                // Pills) — a numeric badge, driven by the payload's `score`.
                StatusPill(formattedScore(score), tone: .neutral)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // Per constitution §E.2: hero and wide must wrap (no truncation).
    // Compact sizes still cap to keep card glanceable.
    private var titleLineLimit: Int? {
        switch size {
        case .small, .medium: return 2
        case .wide, .hero: return nil
        }
    }

    private func formattedScore(_ score: Double) -> String {
        if score >= 1000 {
            let k = score / 1000
            return String(format: "%.1fk", k)
        }
        return String(format: "%.0f", score)
    }
}

// MARK: - ScoreSparkline

private struct ScoreSparkline: View {
    let items: [TrendingPayload.Item]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let scores = items.compactMap(\.score)
            if scores.count >= 2 {
                let maxScore = scores.max() ?? 1
                let minScore = scores.min() ?? 0
                let range = maxScore - minScore
                let normalizedScores = scores.map { score in
                    range > 0 ? (score - minScore) / range : 0.5
                }
                Path { path in
                    let stepX = geometry.size.width / CGFloat(normalizedScores.count - 1)
                    for (index, value) in normalizedScores.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = geometry.size.height * (1 - CGFloat(value))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint, lineWidth: 2)
            }
        }
    }
}

// MARK: - Previews

#Preview("Small — Neutral") {
    TrendingCardView(
        payload: TrendingPayload(
            topic: "Swift / iOS news",
            items: [
                .init(title: "Swift 6.1 announces native macro caching", url: "https://swift.org/blog/macro-caching", score: 487),
                .init(title: "SwiftData query builder refactor", url: "https://example.com", score: 312),
            ]
        ),
        size: .small,
        style: .neutral
    )
    .padding()
}

#Preview("Medium — Accent") {
    TrendingCardView(
        payload: TrendingPayload(
            topic: "Swift / iOS news",
            items: [
                .init(title: "Swift 6.1 announces native macro caching", url: "https://swift.org/blog/macro-caching", score: 487),
                .init(title: "SwiftData query builder refactor", url: "https://example.com/swiftdata", score: 312),
                .init(title: "iOS 26.2 beta available", url: "https://example.com/ios26", score: 200),
                .init(title: "Xcode 27 preview", url: "https://example.com/xcode", score: 150),
            ]
        ),
        size: .medium,
        style: .accent
    )
    .padding()
}

#Preview("Wide — Success") {
    TrendingCardView(
        payload: TrendingPayload(
            topic: "Swift / iOS news",
            items: [
                .init(title: "Swift 6.1 announces native macro caching", url: "https://swift.org/blog/macro-caching", score: 487),
                .init(title: "SwiftData query builder refactor", url: "https://example.com/swiftdata", score: 312),
                .init(title: "iOS 26.2 beta available", url: "https://example.com/ios26", score: 200),
                .init(title: "Xcode 27 preview", url: "https://example.com/xcode", score: 150),
                .init(title: "VisionOS 3 SDK announced", url: "https://example.com/vision", score: 120),
                .init(title: "Extra item beyond top-5", url: "https://example.com/extra", score: 80),
            ]
        ),
        size: .wide,
        style: .success
    )
    .padding()
}

#Preview("Hero — Warning") {
    TrendingCardView(
        payload: TrendingPayload(
            topic: "Swift / iOS news",
            items: [
                .init(title: "Swift 6.1 announces native macro caching", url: "https://swift.org/blog/macro-caching", score: 487),
                .init(title: "SwiftData query builder refactor", url: "https://example.com/swiftdata", score: 312),
                .init(title: "iOS 26.2 beta available", url: "https://example.com/ios26", score: 200),
                .init(title: "Xcode 27 preview", url: "https://example.com/xcode", score: 150),
                .init(title: "VisionOS 3 SDK announced", url: "https://example.com/vision", score: 120),
                .init(title: "New Swift Testing framework", url: "https://example.com/testing", score: 95),
                .init(title: "Core Data deprecated timeline", url: "https://example.com/coredata", score: 88),
                .init(title: "Async/Await best practices guide", url: "https://example.com/async", score: 72),
                .init(title: "TipKit recipes for onboarding", url: "https://example.com/tipkit", score: 60),
                .init(title: "App Intents 2.0 deep dive", url: "https://example.com/appintents", score: 55),
            ]
        ),
        size: .hero,
        style: .warning
    )
    .padding()
}
