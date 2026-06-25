import SwiftUI
import SwiftData
import AIDashCore

public struct BriefingView: View {
    @Query private var todaysBriefings: [BriefingModel]
    @Query private var latestPublished: [BriefingModel]

    public init() {
        let today = Self.localTodayString()
        _todaysBriefings = Query(
            filter: #Predicate<BriefingModel> { $0.date == today && $0.publishedAt != nil },
            sort: [SortDescriptor(\BriefingModel.generatedAt, order: .reverse)]
        )
        // Fallback: latest published briefing whose date is on or before the user's
        // local today. This prevents future-dated published briefings from leaking
        // in when today has no briefing yet.
        var fallbackDescriptor = FetchDescriptor<BriefingModel>(
            predicate: #Predicate<BriefingModel> {
                $0.publishedAt != nil && $0.date <= today
            },
            sortBy: [SortDescriptor(\BriefingModel.date, order: .reverse)]
        )
        fallbackDescriptor.fetchLimit = 1
        _latestPublished = Query(fallbackDescriptor)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let briefing = todaysBriefings.first {
                    header(for: briefing, isFallback: false)
                    containers(for: briefing)
                } else if let fallback = latestPublished.first {
                    header(for: fallback, isFallback: true)
                    containers(for: fallback)
                } else {
                    emptyState
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func header(for briefing: BriefingModel, isFallback: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isFallback {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(
                        "briefing.fallback.banner \(briefing.date)",
                        tableName: "Localizable",
                        bundle: .module,
                        comment: "Banner shown above the latest published briefing when no briefing exists for today. Parameter: the date string of the briefing being shown."
                    )
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
            Text(briefing.date)
                .font(.largeTitle.bold())
            if let publishedAt = briefing.publishedAt {
                Text(
                    "briefing.published.relative \(publishedAt.formatted(.relative(presentation: .named)))",
                    tableName: "Localizable",
                    bundle: .module,
                    comment: "Caption showing how long ago the briefing was published. Parameter: a localized relative time string like 'yesterday'."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func containers(for briefing: BriefingModel) -> some View {
        let sorted = briefing.containers.sorted(by: { $0.order < $1.order })
        if sorted.isEmpty {
            emptyContainersState
        } else {
            ForEach(sorted) { container in
                containerStub(container)
            }
        }
    }

    /// Minimal in-place container renderer used until T091 (ContainerView)
    /// merges. This deliberately stays as a compact title/subtitle stub so
    /// T090 does not depend on a not-yet-shipped sibling task. It is private
    /// to this file so it cannot accidentally become public surface.
    @ViewBuilder
    private func containerStub(_ container: ContainerModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(container.title)
                .font(.headline)
            if let subtitle = container.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var emptyContainersState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(
                "briefing.empty_containers.title",
                tableName: "Localizable",
                bundle: .module,
                comment: "Shown when a published briefing exists but has no containers."
            )
            .font(.headline)
            Text(
                "briefing.empty_containers.subtitle",
                tableName: "Localizable",
                bundle: .module,
                comment: "Subtitle explaining that the briefing was published without any content sections."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(
                "briefing.empty.title",
                tableName: "Localizable",
                bundle: .module,
                comment: "Title shown when no briefings have been published yet."
            )
            .font(.title2)
            Text(
                "briefing.empty.subtitle",
                tableName: "Localizable",
                bundle: .module,
                comment: "Subtitle directing the user to use the aidash CLI to publish their first briefing."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    /// The user's local calendar day formatted as `yyyy-MM-dd`.
    /// Uses the current locale's calendar and time zone so the boundary between
    /// "today" and "tomorrow" matches what the user sees on their device clock,
    /// not the UTC day boundary.
    private static func localTodayString() -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
