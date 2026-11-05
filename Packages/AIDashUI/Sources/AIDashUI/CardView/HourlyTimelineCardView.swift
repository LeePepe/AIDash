import SwiftUI
import AIDashCore
import DesignKit

public struct HourlyTimelineCardView: View {
    let payload: HourlyTimelinePayload
    let size: CardSize
    let style: CardStyle
    static let recipe = AIDashTypography.detail(for: .hourlyTimeline)

    public init(payload: HourlyTimelinePayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: AIDashSpace.s12) {
            CardTypeBadge(type: .hourlyTimeline)
            VStack(alignment: .leading, spacing: 10) {
                header
                Text(payload.overview)
                    .font(Self.recipe.secondary)
                    .foregroundStyle(Self.recipe.secondaryColor)
                    .lineSpacing(Self.recipe.secondaryLineSpacing)
                content
            }
            .frame(maxWidth: 720, alignment: .leading)
            Spacer(minLength: 0)
        }
        .cardChrome(size: size, style: style)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(payload.title)
                .font(Self.recipe.primary)
            if let subtitle = payload.subtitle {
                Text(subtitle)
                    .font(Self.recipe.secondary)
                    .foregroundStyle(Self.recipe.secondaryColor)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .small:
            Text(activeSummary)
                .font(Self.recipe.secondary)
                .foregroundStyle(Self.recipe.secondaryColor)
        case .medium:
            buckets(Array(activeBuckets.prefix(3)))
        case .wide:
            VStack(alignment: .leading, spacing: 6) {
                buckets(activeBuckets)
                if emptyCount > 0 {
                    Text("\(emptyCount) empty hours")
                        .font(Self.recipe.secondary)
                        .foregroundStyle(Self.recipe.secondaryColor)
                }
            }
        case .hero:
            VStack(alignment: .leading, spacing: 8) {
                buckets(activeBuckets)
                ForEach(payload.citations) { citation in
                    Text(citation.label)
                        .font(Self.recipe.secondary)
                        .foregroundStyle(Self.recipe.secondaryColor)
                }
                if let nextSteps = payload.nextSteps {
                    ForEach(nextSteps, id: \.self) { Text($0).font(Self.recipe.secondary) }
                }
            }
        }
    }

    private func buckets(_ values: [HourlyTimelinePayload.HourBucket]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(values) { bucket in HourlyBucketRow(bucket: bucket) }
        }
    }

    private var activeBuckets: [HourlyTimelinePayload.HourBucket] {
        payload.hours.filter { $0.summary.trimmingCharacters(in: .whitespacesAndNewlines) != HourlyTimelinePayload.emptyBucketSummary }
    }

    private var emptyCount: Int { payload.hours.count - activeBuckets.count }
    private var activeSummary: String { "\(activeBuckets.count) active hours" }
}

private struct HourlyBucketRow: View {
    let bucket: HourlyTimelinePayload.HourBucket
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(format: "H%02d", bucket.hour))
                .font(HourlyTimelineCardView.recipe.secondary)
                .foregroundStyle(.secondary)
            Text(bucket.summary)
                .font(HourlyTimelineCardView.recipe.primary)
                .lineLimit(2)
        }
    }
}
