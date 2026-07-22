import SwiftUI
import AIDashCore
import DesignKit

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
        HStack(alignment: .top, spacing: 12) {
            CardTypeBadge(type: .trending)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style, minHeight: chromeMinHeight)
    }

    // The hero radar is an adaptive grid whose height depends entirely on how
    // many rows the columns wrap into — a fixed 280pt hero strut leaves a dead
    // band under a short tier (e.g. a single-row "拓展视野"). Let the card hug
    // its content instead by flooring at the low empty-height. Other sizes pass
    // nil so cardChrome applies the standard per-size floor.
    private var chromeMinHeight: CGFloat? {
        size == .hero ? AIDashSize.emptyMinHeight : nil
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

    // MARK: - Hero: topic + an adaptive multi-column grid of repo cells.
    //
    // On a wide dashboard a single-column list strands a huge empty middle
    // column (the row content hugs the left, the pills hug the right). An
    // adaptive grid instead packs each repo into a self-contained cell and
    // reflows to as many columns as the width affords (≈2 at 1000pt, 3 at
    // 2000pt), collapsing to one column when narrow. Cells are separated by
    // spacing only — no per-cell background (chrome lives in cardChrome).

    @ViewBuilder
    private var heroContent: some View {
        topicLabel
        LazyVGrid(columns: Self.gridColumns, alignment: .leading,
                  spacing: AIDashSpace.s24) {
            let top10 = Array(payload.items.prefix(10))
            ForEach(Array(top10.enumerated()), id: \.offset) { index, item in
                TrendingRepoCell(item: item, rank: index + 1)
            }
        }
    }

    // Reflow by available width: each column is ≥ 360pt, so the grid fits more
    // columns as the card widens and drops to one when it's narrow.
    private static let gridColumns = [
        GridItem(.adaptive(minimum: 360, maximum: 620),
                 spacing: AIDashSpace.s24, alignment: .top)
    ]

    @ViewBuilder
    private var topicLabel: some View {
        Text(payload.topic)
            .font(Self.recipe.secondary)
            .foregroundStyle(.secondary)
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

    // MARK: - Typography recipe

    static let recipe = AIDashTypography.detail(for: .trending)
}

// MARK: - TrendingItemRow
//
// A scannable recommendation block, not a bare ranking line. Two rows:
//   1. rank · repo name (a Link that opens GitHub) · star count + Δ pill
//   2. the one-line reason ("why it's worth a look") · category tag
// The reason is the point; the rank is just an index, so it's de-emphasized.
// Rows with neither reason nor category collapse to the single title line.

private struct TrendingItemRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.starredItemRefs) private var starredItemRefs
    let item: TrendingPayload.Item
    let rank: Int
    let showScore: Bool
    let size: CardSize

    private var url: URL? { URL(string: item.url) }

    var body: some View {
        // The star button sits outside the combined accessibility element so
        // VoiceOver keeps it as its own actionable control (constitution
        // §E.5 governs the row content itself).
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                titleLine
                if hasDetailLine {
                    detailLine
                        .padding(.leading, Self.gutter)   // align under the title, past the rank
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            StarItemButton(
                itemRef: item.url,
                itemTitle: item.title,
                isStarred: starredItemRefs.contains(item.url)
            )
        }
        .padding(.vertical, 2)
    }

    // Line 1: rank · title (link) · Δ pill · star pill.
    private var titleLine: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(TrendingCardView.recipe.primary)
                .foregroundStyle(theme.neutrals.text3)   // an index, not the point
                .frame(width: Self.rankWidth, alignment: .trailing)
            titleView
                .lineLimit(titleLineLimit)
            Spacer(minLength: 8)
            if let deltaLabel = deltaPillLabel {
                // Δ since the previous snapshot: ▲/▼ + magnitude. Higher score
                // is good, so up→success, down→danger (metric-cockpit tone).
                StatusPill(deltaLabel.text, tone: deltaLabel.tone)
            }
            if showScore, let score = item.score {
                StatusPill(formattedScore(score), tone: .neutral)
            }
        }
    }

    // The repo name is the primary affordance: a Link to its GitHub page,
    // tinted with the brand primary so it reads as tappable. Falls back to
    // plain text when the url is unparseable (never a dead link).
    @ViewBuilder
    private var titleView: some View {
        if let url {
            Link(destination: url) {
                Text(item.title)
                    .font(TrendingCardView.recipe.secondary)
                    .foregroundStyle(theme.primary.primary)
            }
            .buttonStyle(.plain)
        } else {
            Text(item.title)
                .font(TrendingCardView.recipe.secondary)
                .foregroundStyle(TrendingCardView.recipe.secondaryColor)
        }
    }

    // Line 2: reason (the "why") + trailing category tag. Either may be absent.
    private var detailLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let reason = item.reason, !reason.isEmpty {
                Text(reason)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let category = item.category, !category.isEmpty {
                StatusPill(category, tone: .neutral)
            }
        }
    }

    private var hasDetailLine: Bool {
        (item.reason?.isEmpty == false) || (item.category?.isEmpty == false)
    }

    /// The delta pill's text + tone, or nil when there's no delta signal.
    /// A zero delta carries no information (a lone arrow) so it's hidden; the
    /// day-1 case (delta == nil) likewise renders nothing.
    private var deltaPillLabel: (text: String, tone: PillTone)? {
        guard let delta = item.delta, delta != 0 else { return nil }
        let glyph = delta > 0 ? "▲" : "▼"
        return ("\(glyph) \(formattedScore(abs(delta)))",
                delta > 0 ? .success : .danger)
    }

    // Per constitution §E.2: hero and wide must wrap (no truncation).
    // Compact sizes still cap to keep card glanceable.
    private var titleLineLimit: Int? {
        switch size {
        case .small, .medium: return 2
        case .wide, .hero: return nil
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(rank). \(item.title)"]
        if let score = item.score { parts.append("\(formattedScore(score)) stars") }
        if let d = item.delta, d != 0 { parts.append("\(d > 0 ? "up" : "down") \(formattedScore(abs(d)))") }
        if let c = item.category, !c.isEmpty { parts.append(c) }
        if let r = item.reason, !r.isEmpty { parts.append(r) }
        return parts.joined(separator: ", ")
    }

    private func formattedScore(_ score: Double) -> String {
        if score >= 1000 {
            let k = score / 1000
            return String(format: "%.1fk", k)
        }
        return String(format: "%.0f", score)
    }

    private static let rankWidth: CGFloat = 24
    // Left inset for line 2 so the reason aligns under the title, not the rank.
    private static let gutter: CGFloat = rankWidth + 8
}

// MARK: - TrendingRepoCell
//
// The hero grid cell: one repo as a self-contained recommendation block that
// tiles into columns. Unlike TrendingItemRow (a full-width line for compact
// sizes), this stacks vertically so it stays legible at ~360–620pt wide:
//   1. rank · repo Link · Δ pill        (title line; Δ sits with the name)
//   2. the reason ("why it's worth a look")
//   3. star count · category tag         (footer, de-emphasized)
// Separated from siblings by grid spacing only — no per-cell background.

private struct TrendingRepoCell: View {
    @Environment(\.theme) private var theme
    @Environment(\.starredItemRefs) private var starredItemRefs
    let item: TrendingPayload.Item
    let rank: Int

    private var url: URL? { URL(string: item.url) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: AIDashSpace.s4) {
                titleLine
                if let reason = item.reason, !reason.isEmpty {
                    Text(reason)
                        .font(TypeScale.meta)
                        .foregroundStyle(theme.neutrals.text2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Self.gutter)
                }
                footer
                    .padding(.leading, Self.gutter)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            StarItemButton(
                itemRef: item.url,
                itemTitle: item.title,
                isStarred: starredItemRefs.contains(item.url)
            )
        }
    }

    // Line 1: rank · repo link · Δ pill (the change is part of the headline).
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: AIDashSpace.s8) {
            Text("\(rank)")
                .font(TrendingCardView.recipe.primary)
                .foregroundStyle(theme.neutrals.text3)
                .frame(width: Self.rankWidth, alignment: .trailing)
            repoLink
                .lineLimit(1)
                .truncationMode(.middle)
            if let deltaLabel = deltaPillLabel {
                StatusPill(deltaLabel.text, tone: deltaLabel.tone)
            }
            Spacer(minLength: 0)
        }
    }

    // Footer: star count (neutral pill) + category tag. Both optional.
    private var footer: some View {
        HStack(spacing: AIDashSpace.s8) {
            if let score = item.score {
                StatusPill(formattedScore(score), tone: .neutral)
            }
            if let category = item.category, !category.isEmpty {
                StatusPill(category, tone: .neutral)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var repoLink: some View {
        if let url {
            Link(destination: url) {
                Text(item.title)
                    .font(TrendingCardView.recipe.secondary)
                    .foregroundStyle(theme.primary.primary)
            }
            .buttonStyle(.plain)
        } else {
            Text(item.title)
                .font(TrendingCardView.recipe.secondary)
                .foregroundStyle(TrendingCardView.recipe.secondaryColor)
        }
    }

    private var deltaPillLabel: (text: String, tone: PillTone)? {
        guard let delta = item.delta, delta != 0 else { return nil }
        let glyph = delta > 0 ? "▲" : "▼"
        return ("\(glyph) \(formattedScore(abs(delta)))",
                delta > 0 ? .success : .danger)
    }

    private var accessibilityLabel: String {
        var parts = ["\(rank). \(item.title)"]
        if let score = item.score { parts.append("\(formattedScore(score)) stars") }
        if let d = item.delta, d != 0 { parts.append("\(d > 0 ? "up" : "down") \(formattedScore(abs(d)))") }
        if let c = item.category, !c.isEmpty { parts.append(c) }
        if let r = item.reason, !r.isEmpty { parts.append(r) }
        return parts.joined(separator: ", ")
    }

    private func formattedScore(_ score: Double) -> String {
        if score >= 1000 { return String(format: "%.1fk", score / 1000) }
        return String(format: "%.0f", score)
    }

    private static let rankWidth: CGFloat = 24
    private static let gutter: CGFloat = rankWidth + AIDashSpace.s8
}

// MARK: - StarItemButton
//
// Spec 002 (star feedback loop, D3/D4): every radar item carries a star
// toggle that is deliberately more prominent than a status pill — a
// filled/outline SF Symbol tinted with the brand primary, a larger hit
// target, and a snappy replace animation on tap. The button only emits an
// intent through the injected `onStarItem` environment closure; when nothing
// is injected (previews, snapshots) it degrades to a visual no-op.
//
// Per D2 the toggle only ever *emits* a star (there is no unstar event in
// v1): repeated taps are idempotent — the App layer dedupes by
// cardId+itemRef — and the filled state is inferred from already-persisted
// star events via `starredItemRefs`.

private struct StarItemButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.onStarItem) private var onStarItem
    @Environment(\.currentCardId) private var currentCardId
    let itemRef: String
    let itemTitle: String
    let isStarred: Bool

    /// Optimistic fill: the persisted star event only flows back through
    /// `starredItemRefs` on the next SwiftData refresh, so the tap flips the
    /// glyph immediately (spec 002 US1: filled within 100ms).
    @State private var tappedStar = false

    private var filled: Bool { isStarred || tappedStar }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { tappedStar = true }
            onStarItem?(currentCardId, itemRef)
        } label: {
            Image(systemName: filled ? "star.fill" : "star")
                .font(TrendingCardView.recipe.secondary.weight(.semibold))
                .foregroundStyle(filled ? theme.primary.primary : theme.neutrals.text3)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: AIDashSpacing.starButtonHitTarget,
                       minHeight: AIDashSpacing.starButtonHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filled ? Self.starredLabel(itemTitle) : Self.starLabel(itemTitle))
    }

    private static func starLabel(_ title: String) -> String {
        String(
            localized: "trending.star_button.label \(title)",
            bundle: .module,
            comment: "VoiceOver label for the star button on a radar item that is not yet starred. The parameter is the item title (repo name)."
        )
    }

    private static func starredLabel(_ title: String) -> String {
        String(
            localized: "trending.star_button.label.starred \(title)",
            bundle: .module,
            comment: "VoiceOver label for the star button on a radar item that is already starred. The parameter is the item title (repo name)."
        )
    }
}

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

#Preview("Hero — Radar (delta + category + reason)") {
    TrendingCardView(
        payload: TrendingPayload(
            topic: "值得现在看 · 多关联 Financial",
            items: [
                .init(title: "VoltAgent/awesome-design-md", url: "https://github.com/VoltAgent/awesome-design-md", score: 102743, delta: 12, category: "设计系统/AI编码", reason: "DESIGN.md 让 AI agents 生成匹配 UI，直接加速 AIDashUI 的设计系统建设"),
                .init(title: "TauricResearch/TradingAgents", url: "https://github.com/TauricResearch/TradingAgents", score: 93459, delta: 412, category: "AI-agent/交易投资", reason: "多 Agent LLM 金融交易框架，与 Financial 项目直接相关，可用于交易策略开发"),
                .init(title: "HKUDS/OpenHarness", url: "https://github.com/HKUDS/OpenHarness", score: 14887, delta: -3, category: "AI-agent 框架", reason: "开源 Agent 框架，与 AIDash 的智能助手系统直接相关，可参考其架构设计"),
                .init(title: "oh-my-mermaid/oh-my-mermaid", url: "https://github.com/oh-my-mermaid/oh-my-mermaid", score: 1793, delta: nil, category: "开发工具", reason: "用 Claude Code 自动生成架构图，适合理解复杂系统"),
            ]
        ),
        size: .hero,
        style: .accent
    )
    .frame(width: 560)
    .padding()
}
