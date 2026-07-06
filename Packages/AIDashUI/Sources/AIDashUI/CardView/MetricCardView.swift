import SwiftUI
import AIDashCore
import DesignKit

public struct MetricCardView: View {
    let payload: MetricPayload
    let size: CardSize
    let style: CardStyle
    @Environment(\.theme) private var theme

    public init(payload: MetricPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardTypeBadge(type: .metric)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style)
    }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .small:
            if let item = payload.items.first {
                metricCell(item)
            }
        case .medium:
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(payload.items.prefix(2).enumerated()), id: \.offset) { _, item in
                    metricCell(item)
                }
            }
        case .wide:
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: max(1, min(payload.items.count, 4))
                ),
                spacing: 12
            ) {
                ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
                    metricCell(item)
                }
            }
        case .hero:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
                    metricCell(item)
                }
            }
        }
    }

    // MARK: - Components

    private func metricCell(_ item: MetricPayload.Item) -> some View {
        let recipe = AIDashTypography.detail(for: .metric)
        return VStack(alignment: .leading, spacing: 2) {
            metricValue(item, recipe: recipe)
            Text(item.label)
                .font(recipe.secondary)
                .foregroundStyle(recipe.secondaryColor)
        }
    }

    private func metricValue(
        _ item: MetricPayload.Item,
        recipe: AIDashTypography.DetailRecipe
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(formattedValue(item.value))
                .font(recipe.primary)

            if let unit = item.unit {
                Text(unit)
                    .font(recipe.secondary)
                    .foregroundStyle(recipe.secondaryColor)
            }

            if let trend = item.trend {
                trendArrow(trend, recipe: recipe)
            }
        }
    }

    private func trendArrow(
        _ trend: MetricPayload.Item.Trend,
        recipe: AIDashTypography.DetailRecipe
    ) -> some View {
        Image(systemName: trendIconName(trend))
            .font(recipe.secondary)
            .foregroundStyle(trendColor(trend))
    }

    // MARK: - Helpers

    func formattedValue(_ value: Double) -> String {
        if value == value.rounded() && value < 1_000_000 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    func trendIconName(_ trend: MetricPayload.Item.Trend) -> String {
        switch trend {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "arrow.right"
        }
    }

    func trendColor(_ trend: MetricPayload.Item.Trend) -> Color {
        switch trend {
        case .up: return theme.success
        case .down: return theme.danger
        case .flat: return .secondary
        }
    }
}

// MARK: - Previews

#Preview("Small") {
    MetricCardView(
        payload: MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
        ]),
        size: .small,
        style: .success
    )
    .frame(width: 220, height: 140)
    .padding()
}

#Preview("Medium") {
    MetricCardView(
        payload: MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
            .init(label: "Build time", value: 124, unit: "s", trend: .down),
        ]),
        size: .medium,
        style: .neutral
    )
    .frame(width: 420, height: 160)
    .padding()
}

#Preview("Wide") {
    MetricCardView(
        payload: MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
            .init(label: "Build time", value: 124, unit: "s", trend: .down),
            .init(label: "Test coverage", value: 87.5, unit: "%", trend: .flat),
            .init(label: "Active issues", value: 12),
        ]),
        size: .wide,
        style: .accent
    )
    .frame(width: 640, height: 180)
    .padding()
}

#Preview("Hero") {
    MetricCardView(
        payload: MetricPayload(items: [
            .init(label: "Test coverage", value: 87.5, unit: "%", trend: .flat),
            .init(label: "PRs merged", value: 3, trend: .up),
            .init(label: "Build time", value: 124, unit: "s", trend: .down),
            .init(label: "Active issues", value: 12),
        ]),
        size: .hero,
        style: .warning
    )
    .frame(width: 640, height: 320)
    .padding()
}
