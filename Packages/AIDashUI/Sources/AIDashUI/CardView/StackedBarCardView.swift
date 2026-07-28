import SwiftUI
import AIDashCore
import DesignKit

/// Renders a `stackedBar` card: a single horizontal bar split into
/// proportional segments, with a legend below. Covers session quality
/// (end_turn / tool_use / max_tokens) and model-tier usage (opus / gpt …) —
/// a composition-of-a-whole where the mix is the point (proposal §2 D + model
/// tiers, north-star §7).
///
/// Segment coloring is two-channel:
///   - A segment with a `semantic` takes its fixed status color (e.g. a
///     `max_tokens` truncation → warning orange) so a quality alert pops.
///   - A pure-category segment (model tiers) takes a `chartCategorical` color,
///     whose remap keeps the first categories ≥40° apart in hue and clear of
///     the semantic hues, so the legend reads as distinct non-semantic swatches.
///
/// Segments are separated by a 2px surface seam so adjacent slices stay legible
/// even at similar tones. Legend value text is neutral (`text2`), never the
/// segment color (proposal design law).
public struct StackedBarCardView: View {
    let payload: StackedBarPayload
    let size: CardSize
    let style: CardStyle
    @Environment(\.theme) private var theme

    public init(payload: StackedBarPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        let isEmpty = payload.segments.isEmpty
        let emptyHeight: CGFloat? = isEmpty ? AIDashSize.emptyMinHeight : nil
        return HStack(alignment: isEmpty ? .center : .top, spacing: AIDashSpace.s12) {
            CardTypeBadge(type: .stackedBar)
            VStack(alignment: .leading, spacing: AIDashSpace.s12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style, minHeight: emptyHeight)
    }

    @ViewBuilder
    private var content: some View {
        if payload.segments.isEmpty {
            CardEmptyState(message: Self.emptyMessage)
        } else {
            populatedContent
        }
    }

    @ViewBuilder
    private var populatedContent: some View {
        if let title = payload.title, !title.isEmpty {
            Text(title)
                .font(Self.recipe.primary)
                .foregroundStyle(theme.neutrals.text1)
                .lineLimit(1)
        }
        StackedBarTrack(slices: slices)
        legend
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s4) {
            ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                StackedBarLegendRow(slice: slice, total: total)
            }
        }
    }

    // MARK: - Derived

    /// Total of all segment magnitudes; drives each slice's share. Guarded so a
    /// payload of zeros renders empty rather than dividing by zero.
    private var total: Double {
        max(payload.segments.map(\.value).reduce(0, +), 0)
    }

    /// Resolve each segment to a colored slice via the shared resolver (kept
    /// out of the view so the color/fraction rules are unit-testable).
    private var slices: [StackedBarSlice] {
        StackedBarSliceResolver.resolve(segments: payload.segments, theme: theme)
    }

    // MARK: - Localized strings

    private static let emptyMessage = String(
        localized: "stacked_bar.empty",
        defaultValue: "No data",
        bundle: .module,
        comment: "Shown inside a stackedBar card when its payload decoded successfully but has no segments to plot."
    )

    static let recipe = AIDashTypography.detail(for: .stackedBar)
}

// MARK: - StackedBarSlice
//
// A resolved segment: its share of the whole and its final color/tone.

struct StackedBarSlice {
    let label: String
    let value: Double
    let fraction: Double
    let color: Color
    let tone: SemanticTone?
}

// MARK: - StackedBarSliceResolver
//
// Turns raw segments into colored, proportioned slices. Pure-category segments
// consume `chartCategorical` in appearance order (their own running index) so
// the first categories stay maximally distinct; semantic segments take their
// fixed status color and DO NOT advance the category index (so a warning
// segment never "uses up" a category slot). Extracted from the view so these
// rules are unit-testable without rendering.

enum StackedBarSliceResolver {
    static func resolve(segments: [StackedBarPayload.Segment], theme: Theme) -> [StackedBarSlice] {
        let total = max(segments.map(\.value).reduce(0, +), 0)
        // Two coloring modes, mirroring barList:
        //   - Quality-gradient bar (ANY segment carries a semantic, e.g. session
        //     quality end_turn/max_tokens): semantic segments take their status
        //     color; the in-between neutral segments render a quiet `text2` grey
        //     so the good/neutral/bad reads as three plain tiers.
        //   - Pure-category bar (NO semantics, e.g. model tiers): every segment
        //     takes a distinct `chartCategorical` color so the mix is legible.
        let anySemantic = segments.contains { SemanticTone(rawValue: $0.semantic) != nil }
        var categoryIndex = 0
        return segments.map { segment in
            let fraction = total > 0 ? max(0, segment.value / total) : 0
            if let tone = SemanticTone(rawValue: segment.semantic) {
                return StackedBarSlice(
                    label: segment.label, value: segment.value,
                    fraction: fraction, color: tone.color(theme), tone: tone
                )
            }
            let color: Color
            if anySemantic {
                color = theme.neutrals.text2      // quiet middle tier
            } else {
                color = theme.chartCategorical(categoryIndex)
                categoryIndex += 1
            }
            return StackedBarSlice(
                label: segment.label, value: segment.value,
                fraction: fraction, color: color, tone: nil
            )
        }
    }
}

// MARK: - StackedBarTrack
//
// The single bar. Segments are laid end-to-end proportional to their fraction,
// separated by a 2px surface seam so adjacent slices stay legible. Clipped to a
// continuous capsule so the whole reads as one rounded bar.

private struct StackedBarTrack: View {
    let slices: [StackedBarSlice]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: Self.seam) {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    Rectangle()
                        .fill(slice.color)
                        .frame(width: max(0, sliceWidth(slice, in: geo.size.width)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.height)
        .clipShape(Capsule(style: .continuous))
        .accessibilityHidden(true)
    }

    /// Slice pixel width, deducting the total seam width shared across gaps so
    /// the segments plus seams fill the track without overflow.
    private func sliceWidth(_ slice: StackedBarSlice, in totalWidth: CGFloat) -> CGFloat {
        let gaps = CGFloat(max(0, slices.count - 1)) * Self.seam
        let usable = max(0, totalWidth - gaps)
        return usable * CGFloat(slice.fraction)
    }

    private static let height: CGFloat = 16
    private static let seam: CGFloat = 2
}

// MARK: - StackedBarLegendRow
//
// One legend entry: a color swatch keyed to its slice, the label, and the
// segment's percentage share. A semantic slice also carries its status icon so
// the alert survives grayscale. The percentage is neutral text, never the
// swatch color.

private struct StackedBarLegendRow: View {
    @Environment(\.theme) private var theme
    let slice: StackedBarSlice
    let total: Double

    var body: some View {
        HStack(spacing: AIDashSpace.s8) {
            // A round swatch (not a RoundedRectangle) — renderer bodies may not
            // carry a literal cornerRadius per §Card Chrome; a Circle needs none.
            Circle()
                .fill(slice.color)
                .frame(width: Self.swatch, height: Self.swatch)
                .accessibilityHidden(true)
            if let icon = slice.tone?.iconName {
                Image(systemName: icon)
                    .font(StackedBarCardView.recipe.secondary)
                    .foregroundStyle(slice.color)
                    .accessibilityHidden(true)
            }
            Text(slice.label)
                .font(StackedBarCardView.recipe.secondary)
                .foregroundStyle(theme.neutrals.text1)
                .lineLimit(1)
            Spacer(minLength: AIDashSpace.s8)
            Text(percentText)
                .font(StackedBarCardView.recipe.secondary)
                .foregroundStyle(theme.neutrals.text2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var percent: Double {
        total > 0 ? slice.value / total * 100 : 0
    }

    private var percentText: String {
        let p = percent
        if p == p.rounded() { return String(format: "%.0f%%", p) }
        return String(format: "%.1f%%", p)
    }

    private var accessibilityLabel: String {
        var parts = [slice.label, percentText]
        if let tone = slice.tone { parts.append(tone.rawValue) }
        return parts.joined(separator: ", ")
    }

    private static let swatch: CGFloat = 10
}

#Preview("stackedBar — session quality (semantic)") {
    StackedBarCardView(
        payload: StackedBarPayload(
            segments: [
                .init(label: "end_turn", value: 70, semantic: "success"),
                .init(label: "tool_use", value: 25),
                .init(label: "max_tokens", value: 5, semantic: "warning"),
            ],
            title: "会话质量"
        ),
        size: .medium,
        style: .neutral
    )
    .frame(width: 320)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
}

#Preview("stackedBar — model tiers (categorical)") {
    StackedBarCardView(
        payload: StackedBarPayload(
            segments: [
                .init(label: "opus-4.6-1m", value: 73.5),
                .init(label: "opus-4.7", value: 18),
                .init(label: "gpt-5.4", value: 8.5),
            ],
            title: "模型分层"
        ),
        size: .medium,
        style: .neutral
    )
    .frame(width: 320)
    .padding()
    .designTheme(seed: .lime, neutral: .slate)
}
