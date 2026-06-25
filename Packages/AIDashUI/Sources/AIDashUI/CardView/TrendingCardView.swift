import SwiftUI
import AIDashCore

public struct TrendingCardView: View {
    let payload: TrendingPayload
    let size: CardSize
    let style: CardStyle

    public init(payload: TrendingPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundTint, in: RoundedRectangle(cornerRadius: 12))
    }

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

    // MARK: - Small: topic + top-1 item only

    @ViewBuilder
    private var smallContent: some View {
        Text(payload.topic)
            .font(.caption)
            .foregroundStyle(.secondary)
        if let first = payload.items.first {
            TrendingItemRow(item: first, rank: 1, showScore: false)
        }
    }

    // MARK: - Medium: topic + top-3

    @ViewBuilder
    private var mediumContent: some View {
        Text(payload.topic)
            .font(.caption)
            .foregroundStyle(.secondary)
        let top3 = Array(payload.items.prefix(3))
        ForEach(Array(top3.enumerated()), id: \.offset) { index, item in
            TrendingItemRow(item: item, rank: index + 1, showScore: true)
        }
        if payload.items.count > 3 {
            Text("+\(payload.items.count - 3) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Wide: topic + top-5 with titles + scores

    @ViewBuilder
    private var wideContent: some View {
        Text(payload.topic)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        let top5 = Array(payload.items.prefix(5))
        ForEach(Array(top5.enumerated()), id: \.offset) { index, item in
            TrendingItemRow(item: item, rank: index + 1, showScore: true)
        }
        if payload.items.count > 5 {
            Text("+\(payload.items.count - 5) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Hero: topic + top-10 with titles + scores + sparkline

    @ViewBuilder
    private var heroContent: some View {
        Text(payload.topic)
            .font(.headline)
        let top10 = Array(payload.items.prefix(10))
        if !top10.isEmpty {
            ScoreSparkline(items: top10)
                .frame(height: 40)
        }
        ForEach(Array(top10.enumerated()), id: \.offset) { index, item in
            TrendingItemRow(item: item, rank: index + 1, showScore: true)
        }
        if payload.items.count > 10 {
            Text("+\(payload.items.count - 10) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Background

    private var backgroundTint: Color {
        switch style {
        case .neutral: return Color.clear
        case .success: return Color.green.opacity(0.08)
        case .warning: return Color.orange.opacity(0.08)
        case .accent: return Color.accentColor.opacity(0.10)
        }
    }
}

// MARK: - TrendingItemRow

private struct TrendingItemRow: View {
    let item: TrendingPayload.Item
    let rank: Int
    let showScore: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            Text(item.title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            if showScore, let score = item.score {
                Text(formattedScore(score))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                .stroke(Color.accentColor, lineWidth: 2)
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
            ]
        ),
        size: .hero,
        style: .warning
    )
    .padding()
}
