import SwiftUI
import AIDashCore
import DesignKit

/// Renders a `barList` card: a descending horizontal-bar ranking. Each row is
/// a label, a bar whose length is proportional to its value against the
/// largest, and a trailing value read-out. Covers failure root-cause, app
/// focus time, and commits-by-repo (north-star §7, proposal §2 C/E/F).
///
/// Two coloring modes, chosen by whether ANY row carries a `semantic`:
///   - Semantic present (e.g. failure root cause): neutral rows get a quiet
///     grey bar, and the flagged row(s) get a status color + a leading icon so
///     the hot row pops (color is never the *only* channel — §accessibility).
///   - Pure ranking (app focus / commits): every bar takes the brand primary.
///
/// The value text is always neutral (`text1`) — it never inherits the bar
/// color, so a warning row doesn't tint its own number (proposal design law).
public struct BarListCardView: View {
    let payload: BarListPayload
    let size: CardSize
    let style: CardStyle
    @Environment(\.theme) private var theme

    public init(payload: BarListPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        let isEmpty = payload.items.isEmpty
        let emptyHeight: CGFloat? = isEmpty ? AIDashSize.emptyMinHeight : nil
        return HStack(alignment: isEmpty ? .center : .top, spacing: AIDashSpace.s12) {
            CardTypeBadge(type: .barList)
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style, minHeight: emptyHeight)
    }

    @ViewBuilder
    private var content: some View {
        if payload.items.isEmpty {
            CardEmptyState(message: Self.emptyMessage)
        } else {
            populatedContent
        }
    }

    @ViewBuilder
    private var populatedContent: some View {
        let visible = Array(payload.items.prefix(rowCap))
        ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
            BarListRow(
                item: item,
                fraction: fraction(for: item.value),
                anySemantic: anySemantic
            )
        }
        if payload.items.count > rowCap {
            Text(Self.moreItemsLabel(overflow: payload.items.count - rowCap))
                .font(Self.recipe.secondary)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Derived

    /// The largest magnitude drives the full-width bar; guard a non-positive
    /// max so a payload of zeros renders empty bars rather than dividing by 0.
    private var maxValue: Double {
        max(payload.items.map(\.value).max() ?? 0, 0)
    }

    private func fraction(for value: Double) -> Double {
        guard maxValue > 0 else { return 0 }
        return max(0, min(1, value / maxValue))
    }

    /// Whether any row is flagged — switches the card into "one hot row"
    /// coloring (neutral grey bars + a colored flagged row) instead of the
    /// all-primary pure-ranking coloring.
    private var anySemantic: Bool {
        payload.items.contains { ($0.semantic?.isEmpty == false) }
    }

    /// How many rows a given geometry shows before folding into "+N more".
    private var rowCap: Int {
        switch size {
        case .small:  return 3
        case .medium: return 5
        case .wide:   return 8
        case .hero:   return 12
        }
    }

    // MARK: - Localized strings

    private static let emptyMessage = String(
        localized: "bar_list.empty",
        defaultValue: "No data",
        bundle: .module,
        comment: "Shown inside a barList card when its payload decoded successfully but has no items to rank."
    )

    static func moreItemsLabel(overflow: Int) -> String {
        // Static key + interpolated defaultValue: under SPM the .xcstrings is
        // not compiled, so only the defaultValue fallback renders — the key
        // carries the count via the defaultValue, not the key string.
        String(
            localized: "bar_list.more_items",
            defaultValue: "+\(overflow) more",
            bundle: .module,
            comment: "Trailing line on a barList card listing how many additional rows were truncated. The integer is the overflow count (always ≥ 1)."
        )
    }

    static let recipe = AIDashTypography.detail(for: .barList)
}

// MARK: - BarListRow
//
// One ranking row: label · proportional bar · trailing value. The bar sits on
// a quiet inner-surface track so a short bar still reads as "a fraction of the
// whole", not a stray mark. Semantic rows lead with a status icon so the
// distinction survives grayscale / color-blind viewing.

private struct BarListRow: View {
    @Environment(\.theme) private var theme
    let item: BarListPayload.Item
    let fraction: Double
    let anySemantic: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s4) {
            labelLine
            bar
        }
        .padding(.vertical, AIDashSpace.s2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var labelLine: some View {
        HStack(spacing: AIDashSpace.s8) {
            if let icon = semantic?.iconName {
                Image(systemName: icon)
                    .font(BarListCardView.recipe.primary)
                    .foregroundStyle(semantic?.color(theme) ?? theme.neutrals.text2)
                    .accessibilityHidden(true)
            }
            Text(item.label)
                .font(BarListCardView.recipe.primary)
                .foregroundStyle(theme.neutrals.text1)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: AIDashSpace.s8)
            // Value text is deliberately neutral — never the bar color — so a
            // warning row doesn't tint its own number.
            Text(valueText)
                .font(BarListCardView.recipe.secondary)
                .foregroundStyle(theme.neutrals.text1)
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(theme.neutrals.inner)
                Capsule(style: .continuous)
                    .fill(barColor)
                    .frame(width: max(Self.minBarWidth, geo.size.width * fraction))
            }
        }
        .frame(height: Self.barHeight)
        .accessibilityHidden(true)
    }

    /// Bar tint: in "one hot row" mode neutral rows are quiet grey and only the
    /// flagged row takes its status color; in pure-ranking mode every bar takes
    /// the brand primary.
    private var barColor: Color {
        if anySemantic {
            return semantic?.color(theme) ?? theme.neutrals.text2
        }
        return theme.primary.primary
    }

    private var semantic: SemanticTone? {
        SemanticTone(rawValue: item.semantic)
    }

    private var valueText: String {
        if let text = item.valueText, !text.isEmpty { return text }
        return BarListFormat.value(item.value)
    }

    private var accessibilityLabel: String {
        var parts = [item.label, valueText]
        if let s = item.semantic, !s.isEmpty { parts.append(s) }
        return parts.joined(separator: ", ")
    }

    private static let barHeight: CGFloat = 8
    private static let minBarWidth: CGFloat = 4
}

// MARK: - SemanticTone
//
// Maps a payload `semantic` string to a fixed status color + an accompanying
// SF Symbol, so the semantic channel is carried by BOTH hue and glyph. Shared
// by barList rows and stackedBar segments. Unknown / nil strings yield nil.

enum SemanticTone: String {
    case success, warning, danger

    init?(rawValue: String?) {
        guard let rawValue, let tone = SemanticTone(rawValue: rawValue) else { return nil }
        self = tone
    }

    func color(_ theme: Theme) -> Color {
        switch self {
        case .success: return theme.success
        case .warning: return theme.warning
        case .danger:  return theme.danger
        }
    }

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger:  return "xmark.octagon.fill"
        }
    }
}

// MARK: - BarListFormat
//
// Compact numeric read-out for a bar's trailing value when the payload does
// not supply pre-formatted `valueText`. Kept tiny and rounded/tabular per
// north-star §3 (numbers are monospaced tabular via the row's recipe font).

enum BarListFormat {
    static func value(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }
}

#Preview("barList — failure root cause (semantic)") {
    BarListCardView(
        payload: BarListPayload(items: [
            .init(label: "runtime-offline", value: 39, valueText: "39%", semantic: "warning"),
            .init(label: "codex-init-fail", value: 21, valueText: "21%"),
            .init(label: "queue-timeout", value: 14, valueText: "14%"),
            .init(label: "rate-limited", value: 9, valueText: "9%"),
        ]),
        size: .medium,
        style: .neutral
    )
    .frame(width: 320)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
}

#Preview("barList — app focus (pure ranking)") {
    BarListCardView(
        payload: BarListPayload(items: [
            .init(label: "cmux", value: 4.4, valueText: "4.4min"),
            .init(label: "Chrome", value: 1.4, valueText: "1.4min"),
            .init(label: "Outlook", value: 1.3, valueText: "1.3min"),
        ]),
        size: .medium,
        style: .neutral
    )
    .frame(width: 320)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
}
