import SwiftUI
import SwiftData
import AIDashCore
import DesignKit

public enum BriefingViewState {
    case populated(date: String, containers: [ContainerModel], isFallback: Bool, publishedAt: Date?)
    case loading
    case empty
    case error
}

public struct BriefingView: View {
    @Environment(\.theme) private var theme
    @Query private var todaysBriefings: [BriefingModel]
    @Query private var latestPublished: [BriefingModel]
    private var explicitState: BriefingViewState?

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
        explicitState = nil
    }

    init(state: BriefingViewState) {
        self.init()
        explicitState = state
    }

    public var body: some View {
        #if os(iOS)
        // iOS wraps the shared scroll surface in a NavigationStack so the
        // system navigation bar owns the top safe area and the content no
        // longer drifts into the status bar. macOS keeps its titlebar
        // overlay via the existing safeAreaInset — chrome untouched.
        NavigationStack {
            renderBody
                .navigationTitle(
                    Text(
                        "briefing.navigation.title",
                        tableName: "Localizable",
                        bundle: .module,
                        comment: "Inline navigation-bar title shown at the top of the BriefingView screen on iOS/iPadOS."
                    )
                )
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        renderBody
        #endif
    }

    @ViewBuilder
    private var renderBody: some View {
        if explicitState != nil {
            pageContent
        } else {
            scrollBody
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        VStack(alignment: .leading, spacing: AIDashSpacing.containerVertical) {
            switch resolvedState {
            case let .populated(date, containers, isFallback, publishedAt):
                masthead(date: date, isFallback: isFallback, publishedAt: publishedAt,
                         containerCount: containers.count, cardCount: containers.reduce(0) { $0 + $1.cards.count })
                if containers.isEmpty {
                    emptyContainersState
                } else {
                    ForEach(containers.sorted { $0.order < $1.order }) {
                        ContainerView(container: $0)
                    }
                }
            case .loading:
                stateMasthead
                loadingState
            case .empty:
                stateMasthead
                emptyState
            case .error:
                stateMasthead
                errorState
            }
        }
    }

    @ViewBuilder
    private var scrollBody: some View {
        ScrollView {
            pageContent
            .padding(.horizontal, Self.pageHorizontalPadding)
            .padding(.vertical, AIDashSpacing.pageVertical)
            .frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        // Keep the large date header clear of the traffic-light / titlebar
        // overlay. Without this the first line collides with the window
        // controls on a full-height content window.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 28)
        }
        #endif
        .background(theme.neutrals.bg)
    }

    private var stateMasthead: some View {
        masthead(date: Self.localTodayString(), isFallback: false, publishedAt: nil,
                 containerCount: 0, cardCount: 0)
    }

    @ViewBuilder
    private func masthead(date: String, isFallback: Bool, publishedAt: Date?,
                          containerCount: Int, cardCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            mastheadStatusLine(isFallback: isFallback, publishedAt: publishedAt,
                               containerCount: containerCount, cardCount: cardCount)

            if isFallback {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(theme.warning)
                        .frame(width: AIDashChrome.stripeWidth)
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(theme.warning)
                    Text(
                        String(
                            localized: "briefing.fallback.banner %@",
                            defaultValue: "No new briefing today — showing latest (\(date))",
                            bundle: .module,
                            comment: "Banner shown above the latest published briefing when no briefing exists for today."
                        )
                    )
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.neutrals.text2)
                .padding(AIDashSpace.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: AIDashSpace.s8))
                .overlay {
                    RoundedRectangle(cornerRadius: AIDashSpace.s8)
                        .stroke(theme.neutrals.border, lineWidth: AIDashChrome.hairlineWidth)
                }
                .accessibilityElement(children: .combine)
            }

            Text(date)
                .font(AIDashTypography.masthead)
                .foregroundStyle(theme.neutrals.text1)

            // Hairline rule under the masthead, cockpit console style.
            Rectangle()
                .fill(theme.neutrals.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func mastheadStatusLine(isFallback: Bool, publishedAt: Date?,
                                    containerCount: Int, cardCount: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                mastheadIdentity
                Spacer()
                publishedStatus(isFallback: isFallback, publishedAt: publishedAt)
                telemetryPill(containerCount: containerCount, cardCount: cardCount)
            }
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                mastheadIdentity
                HStack(spacing: AIDashSpace.s8) {
                    publishedStatus(isFallback: isFallback, publishedAt: publishedAt)
                    telemetryPill(containerCount: containerCount, cardCount: cardCount)
                }
            }
        }
    }

    private var mastheadIdentity: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "AIDASH")
                .font(AIDashTypography.mastheadStatus)
                .tracking(2)
                .foregroundStyle(theme.primary.primary)
            Text(verbatim: "// DAILY BRIEFING")
                .font(AIDashTypography.mastheadStatus)
                .tracking(1.4)
                .foregroundStyle(theme.neutrals.text3)
        }
    }

    @ViewBuilder
    private func publishedStatus(isFallback: Bool, publishedAt: Date?) -> some View {
        if !isFallback, let publishedAt {
            HStack(spacing: AIDashSpace.s4) {
                StatusPill(Self.liveLabel, tone: .success)
                Text(
                    String(
                        localized: "briefing.published.relative %@",
                        defaultValue: "Published \(publishedAt.formatted(.relative(presentation: .named)))",
                        bundle: .module,
                        comment: "Caption showing how long ago the briefing was published."
                    )
                )
                .font(AIDashTypography.mastheadStatus)
                .foregroundStyle(theme.neutrals.text2)
            }
        } else {
            StatusPill(Self.cachedLabel, tone: .warning)
        }
    }

    private func telemetryPill(containerCount: Int, cardCount: Int) -> some View {
        let format = String(
            localized: "briefing.telemetry.pill",
            defaultValue: "%1$02d SEC · %2$02d CARDS",
            bundle: .module,
            comment: "Compact telemetry readout showing container and card counts."
        )
        return Text(String(format: format, containerCount, cardCount))
            .font(AIDashTypography.mastheadStatus)
            .foregroundStyle(theme.neutrals.text2)
            .padding(.horizontal, AIDashSpace.s8)
            .padding(.vertical, AIDashSpace.s4)
            .background(theme.neutrals.inner, in: Capsule())
            .accessibilityLabel(
                Text(
                    "briefing.telemetry.accessibility \(containerCount) \(cardCount)",
                    tableName: "Localizable",
                    bundle: .module,
                    comment: "Accessibility label for briefing container and card counts."
                )
            )
    }

    private var resolvedState: BriefingViewState {
        if let explicitState {
            return explicitState
        }
        if let briefing = todaysBriefings.first {
            return .populated(date: briefing.date, containers: briefing.containers,
                              isFallback: false, publishedAt: briefing.publishedAt)
        }
        if let fallback = latestPublished.first {
            return .populated(date: fallback.date, containers: fallback.containers,
                              isFallback: true, publishedAt: fallback.publishedAt)
        }
        return .empty
    }

    private var emptyContainersState: some View {
        diagnosticCard(icon: "square.dashed", titleKey: "briefing.empty_containers.title",
                       detailKey: "briefing.empty_containers.subtitle", tone: .neutral)
    }

    private var emptyState: some View {
        diagnosticCard(icon: "tray", titleKey: "briefing.empty.title",
                       detailKey: "briefing.empty.subtitle", tone: .neutral)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s16) {
            RoundedRectangle(cornerRadius: AIDashSpace.s4)
                .fill(theme.neutrals.inner)
                .frame(height: AIDashSpace.s12)
            HStack(spacing: AIDashSpace.s16) {
                skeletonCard
                skeletonCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: AIDashSpace.s16) {
                skeletonCard
                skeletonCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.neutrals.border)
                .frame(height: AIDashChrome.hairlineWidth)
                .offset(y: AIDashSpace.s16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("briefing.loading", tableName: "Localizable", bundle: .module,
                 comment: "Accessibility label for the briefing loading state.")
        )
    }

    private var skeletonCard: some View {
        RoundedRectangle(cornerRadius: AIDashSize.cornerRadius(.medium))
            .fill(theme.neutrals.card)
            .frame(maxWidth: .infinity, minHeight: AIDashSize.minHeight(.medium))
            .overlay {
                RoundedRectangle(cornerRadius: AIDashSize.cornerRadius(.medium))
                    .stroke(theme.neutrals.border, lineWidth: AIDashChrome.hairlineWidth)
            }
    }

    private var errorState: some View {
        diagnosticCard(icon: "exclamationmark.triangle", titleKey: "briefing.error.title",
                       detailKey: "briefing.error.subtitle", tone: .danger)
    }

    private func diagnosticCard(icon: String, titleKey: String, detailKey: String,
                                tone: PillTone) -> some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s12) {
            StatusPill(titleKey == "briefing.error.title" ? Self.errorLabel : Self.emptyLabel, tone: tone)
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(icon == "exclamationmark.triangle" ? theme.danger : theme.neutrals.text2)
                .accessibilityHidden(true)
            Text(localizedStateText(for: titleKey))
                .font(.title3.weight(.semibold))
            Text(localizedStateText(for: detailKey))
                .font(.callout)
                .foregroundStyle(theme.neutrals.text2)
        }
        .padding(AIDashSpace.s20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: AIDashSpace.s12))
        .overlay {
            RoundedRectangle(cornerRadius: AIDashSpace.s12)
                .stroke(theme.neutrals.border, lineWidth: AIDashChrome.hairlineWidth)
        }
    }

    private func localizedStateText(for key: String) -> String {
        switch key {
        case "briefing.empty.title":
            return String(localized: "briefing.empty.title", defaultValue: "No briefings yet",
                          bundle: .module, comment: "Briefing empty-state title.")
        case "briefing.empty.subtitle":
            return String(localized: "briefing.empty.subtitle",
                          defaultValue: "Use the aidash CLI to publish your first one.",
                          bundle: .module, comment: "Briefing empty-state detail.")
        case "briefing.empty_containers.title":
            return String(localized: "briefing.empty_containers.title",
                          defaultValue: "No sections in this briefing",
                          bundle: .module, comment: "Empty-container state title.")
        case "briefing.empty_containers.subtitle":
            return String(localized: "briefing.empty_containers.subtitle",
                          defaultValue: "This briefing was published without any sections.",
                          bundle: .module, comment: "Empty-container state detail.")
        case "briefing.error.title":
            return String(localized: "briefing.error.title", defaultValue: "Briefing unavailable",
                          bundle: .module, comment: "Briefing error-state title.")
        case "briefing.error.subtitle":
            return String(localized: "briefing.error.subtitle",
                          defaultValue: "The briefing could not be loaded. Try again after the host is available.",
                          bundle: .module, comment: "Briefing error-state detail.")
        default:
            return key
        }
    }

    private static let liveLabel = String(
        localized: "briefing.status.live", defaultValue: "LIVE", bundle: .module,
        comment: "Freshness status shown for a current briefing."
    )
    private static let cachedLabel = String(
        localized: "briefing.status.cached", defaultValue: "CACHED", bundle: .module,
        comment: "Freshness status shown for a fallback briefing."
    )
    private static let errorLabel = String(
        localized: "briefing.status.error", defaultValue: "ERROR", bundle: .module,
        comment: "Status label shown for the briefing error state."
    )
    private static let emptyLabel = String(
        localized: "briefing.status.empty", defaultValue: "EMPTY", bundle: .module,
        comment: "Status label shown for the briefing empty state."
    )

    // MARK: - Page chrome tokens
    //
    // Sourced from .specify/memory/constitution.md §Page Chrome and
    // §Spacing & Color Tokens. The page background is `theme.neutrals.bg`,
    // one luminance tier BELOW the card surface, so cards visually float
    // without needing a shadow.

    /// Horizontal padding for the page. Mac gets 24pt; iOS / iPad get
    /// 20pt. Honoring the platform compile-time channel keeps the
    /// constant deterministic at unit-test time.
    static var pageHorizontalPadding: CGFloat {
        #if os(macOS)
        return AIDashSpacing.pageHorizontalMac
        #else
        return AIDashSpacing.pageHorizontalCompact
        #endif
    }

    /// The user's local calendar day formatted as POSIX `yyyy-MM-dd`.
    ///
    /// Uses a Gregorian calendar pinned to the user's current time zone so the
    /// boundary between "today" and "tomorrow" matches the user's device clock,
    /// while the year/month/day values stay in the POSIX/Gregorian system that
    /// Core uses to store and validate `BriefingModel.date`. `Calendar.current`
    /// is intentionally avoided because users on Buddhist/Japanese/Hebrew/etc.
    /// calendar settings would otherwise produce non-Gregorian year values
    /// (e.g. `2569-06-25`) that would never match the stored date strings.
    private static func localTodayString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
