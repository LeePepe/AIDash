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

    public init(state: BriefingViewState) {
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
            scrollBody
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
        scrollBody
        #endif
    }

    @ViewBuilder
    private var scrollBody: some View {
        ScrollView {
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
                    loadingState
                case .empty:
                    emptyState
                case .error:
                    errorState
                }
            }
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

    @ViewBuilder
    private func masthead(date: String, isFallback: Bool, publishedAt: Date?,
                          containerCount: Int, cardCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            mastheadStatusLine(publishedAt: publishedAt, containerCount: containerCount, cardCount: cardCount)

            if isFallback {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(theme.warning)
                        .frame(width: AIDashChrome.stripeWidth)
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(theme.warning)
                    Text(
                        "briefing.fallback.banner \(date)",
                        tableName: "Localizable",
                        bundle: .module,
                        comment: "Banner shown above the latest published briefing when no briefing exists for today. Parameter: the date string of the briefing being shown."
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
    private func mastheadStatusLine(publishedAt: Date?, containerCount: Int, cardCount: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                mastheadIdentity
                Spacer()
                publishedStatus(publishedAt: publishedAt)
                telemetryPill(containerCount: containerCount, cardCount: cardCount)
            }
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                mastheadIdentity
                HStack(spacing: AIDashSpace.s8) {
                    publishedStatus(publishedAt: publishedAt)
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
    private func publishedStatus(publishedAt: Date?) -> some View {
        if let publishedAt {
            HStack(spacing: AIDashSpace.s4) {
                StatusPill(Self.liveLabel, tone: .success)
                Text(
                    "briefing.published.relative \(publishedAt.formatted(.relative(presentation: .named)))",
                    tableName: "Localizable",
                    bundle: .module,
                    comment: "Caption showing how long ago the briefing was published. Parameter: a localized relative time string like 'yesterday'."
                )
                .font(AIDashTypography.mastheadStatus)
                .foregroundStyle(theme.neutrals.text2)
            }
        } else {
            StatusPill(Self.cachedLabel, tone: .warning)
        }
    }

    private func telemetryPill(containerCount: Int, cardCount: Int) -> some View {
        Text(String(format: "%02d SEC · %02d CARDS", containerCount, cardCount))
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
                .redacted(reason: .placeholder)
            RoundedRectangle(cornerRadius: AIDashSpace.s8)
                .fill(theme.neutrals.card)
                .frame(maxWidth: .infinity, minHeight: AIDashSize.minHeight(.wide))
                .overlay {
                    ProgressView()
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("briefing.loading", tableName: "Localizable", bundle: .module,
                 comment: "Accessibility label for the briefing loading state.")
        )
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
            Text(verbatim: NSLocalizedString(titleKey, tableName: "Localizable",
                                              bundle: .module, value: titleKey, comment: ""))
                .font(.title3.weight(.semibold))
            Text(verbatim: NSLocalizedString(detailKey, tableName: "Localizable",
                                              bundle: .module, value: detailKey, comment: ""))
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
