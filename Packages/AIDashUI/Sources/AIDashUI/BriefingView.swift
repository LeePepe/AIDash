import SwiftUI
import SwiftData
import AIDashCore
import DesignKit

// swiftlint:disable file_length

public enum BriefingViewState {
    case populated(date: String, containers: [ContainerModel], isFallback: Bool, publishedAt: Date?)
    case loading
    case empty
    case error
    case staleError(date: String, containers: [ContainerModel], publishedAt: Date?)
}

private enum BriefingViewCopy {
    static let liveLabel = String(localized: "briefing.status.live", defaultValue: "LIVE", bundle: .module)
    static let cachedLabel = String(localized: "briefing.status.cached", defaultValue: "CACHED", bundle: .module)
    static let errorLabel = String(localized: "briefing.status.error", defaultValue: "ERROR", bundle: .module)
    static let emptyLabel = String(localized: "briefing.status.empty", defaultValue: "EMPTY", bundle: .module)
    static let previousDateLabel = String(localized: "briefing.date.previous", defaultValue: "Previous briefing date", bundle: .module)
    static let nextDateLabel = String(localized: "briefing.date.next", defaultValue: "Next briefing date", bundle: .module)
}

public struct BriefingView: View { // swiftlint:disable:this type_body_length
    @Environment(\.theme) private var theme
    @Environment(\.hiddenCardIds) private var hiddenCardIds
    @Environment(\.onHideCard) private var onHideCard
    @Query private var todaysBriefings: [BriefingModel]
    @Query private var latestPublished: [BriefingModel]
    @Query private var publishedBriefings: [BriefingModel]
    private var explicitState: BriefingViewState?
    private var archiveDates: [String]
    private var onRetry: (() -> Void)?
    @State private var selectedArchiveDate: String?
    @State private var locallyHiddenCardIds: Set<String> = []
    @State private var selectedContainerID: String?

    public init() {
        let today = Self.localTodayString()
        _todaysBriefings = Query(
            filter: #Predicate<BriefingModel> { $0.date == today && $0.publishedAt != nil },
            sort: [SortDescriptor(\BriefingModel.generatedAt, order: .reverse)]
        )
        var fallbackDescriptor = FetchDescriptor<BriefingModel>(
            predicate: #Predicate<BriefingModel> {
                $0.publishedAt != nil && $0.date <= today
            },
            sortBy: [SortDescriptor(\BriefingModel.date, order: .reverse)]
        )
        fallbackDescriptor.fetchLimit = 1
        _latestPublished = Query(fallbackDescriptor)
        _publishedBriefings = Query(
            filter: #Predicate<BriefingModel> {
                $0.publishedAt != nil && $0.date <= today
            },
            sort: [SortDescriptor(\BriefingModel.date, order: .forward)]
        )
        explicitState = nil
        archiveDates = []
        onRetry = nil
    }

    init(state: BriefingViewState, archiveDates: [String] = [], onRetry: (() -> Void)? = nil) {
        self.init()
        explicitState = state
        self.archiveDates = archiveDates
        self.onRetry = onRetry
    }

    public var body: some View {
        #if os(iOS)
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
        Group {
            if explicitState != nil {
                pageContent()
            } else {
                scrollBody
            }
        }
        .environment(\.hiddenCardIds, hiddenCardIds.union(locallyHiddenCardIds))
        .environment(\.onHideCard, hideCard)
    }
    @ViewBuilder
    private func pageContent(proxy: ScrollViewProxy? = nil) -> some View {
        VStack(alignment: .leading, spacing: AIDashSpacing.containerVertical) {
            switch resolvedState {
            case let .populated(date, containers, isFallback, publishedAt):
                let visibleContainers = filteredContainers(containers)
                masthead(date: date, isFallback: isFallback, publishedAt: publishedAt)
                sectionJumpRail(containers: containers, proxy: proxy)
                if visibleContainers.isEmpty {
                    emptyContainersState
                } else {
                    ForEach(visibleContainers.sorted { $0.order < $1.order }) {
                        ContainerView(container: $0)
                            .id($0.id)
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
            case let .staleError(date, containers, publishedAt):
                let visibleContainers = filteredContainers(containers)
                masthead(date: date, isFallback: true, publishedAt: publishedAt)
                staleErrorBanner
                ForEach(visibleContainers.sorted { $0.order < $1.order }) {
                    ContainerView(container: $0)
                        .id($0.id)
                }
            }
        }
    }
    @ViewBuilder
    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                pageContent(proxy: proxy)
                    .padding(.horizontal, Self.pageHorizontalPadding)
                    .padding(.vertical, AIDashSpacing.pageVertical)
                    .frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            #if os(macOS)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 28)
            }
            #endif
            .background(theme.neutrals.bg)
        }
    }

    private var stateMasthead: some View {
        masthead(date: Self.localTodayString(), isFallback: false, publishedAt: nil)
    }
    @ViewBuilder
    private func masthead(date: String, isFallback: Bool, publishedAt: Date?) -> some View {
        let effectiveDate = displayedDate(fallback: date)
        VStack(alignment: .leading, spacing: 10) {
            mastheadStatusLine(date: effectiveDate, isFallback: isFallback, publishedAt: publishedAt)

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
                            defaultValue: "No new briefing today — showing latest (\(effectiveDate))",
                            bundle: .module,
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

            Text(effectiveDate)
                .font(AIDashTypography.masthead)
                .foregroundStyle(theme.neutrals.text1)

            hiddenRecoveryPill

            Rectangle()
                .fill(theme.neutrals.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var hiddenRecoveryPill: some View {
        let hiddenCount = activeHiddenCardCount
        if hiddenCount > 0 {
            Button {
                for card in activeCards where effectiveHiddenCardIds.contains(card.id) {
                    hideCard(cardId: card.id, cardType: card.type, hidden: false)
                }
            } label: {
                Text(
                    "\(hiddenCount) " + String(
                        localized: "briefing.hidden.show",
                        defaultValue: "HIDDEN · SHOW",
                        bundle: .module,
                    )
                )
                .font(AIDashTypography.mastheadStatus)
                .monospacedDigit()
                .padding(.horizontal, AIDashSpace.s8)
                .frame(minHeight: AIDashSpacing.controlHitTarget)
                .background(theme.neutrals.inner, in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    "briefing.hidden.accessibility \(hiddenCount)",
                    tableName: "Localizable",
                    bundle: .module,
                )
            )
        }
    }

    @ViewBuilder
    private func mastheadStatusLine(date: String, isFallback: Bool, publishedAt: Date?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                mastheadIdentity
                Spacer()
                publishedStatus(isFallback: isFallback, publishedAt: publishedAt)
                dateSwitcher(date: date)
            }
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                mastheadIdentity
                HStack(spacing: AIDashSpace.s8) {
                    publishedStatus(isFallback: isFallback, publishedAt: publishedAt)
                    dateSwitcher(date: date)
                }
            }
            VStack(alignment: .leading, spacing: AIDashSpace.s8) {
                mastheadIdentity
                HStack(spacing: AIDashSpace.s8) {
                    publishedStatus(isFallback: isFallback, publishedAt: publishedAt)
                }
                dateSwitcher(date: date)
            }
        }
    }

    @ViewBuilder
    private func dateSwitcher(date: String) -> some View {
        let dates = availableDates
        let index = dates.firstIndex(of: date) ?? dates.startIndex
        HStack(spacing: AIDashSpace.s4) {
            if dates.count >= 2 {
                Button {
                    guard index > dates.startIndex else { return }
                    selectedArchiveDate = dates[dates.index(before: index)]
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: AIDashSpacing.controlHitTarget,
                               minHeight: AIDashSpacing.controlHitTarget)
                }
                .buttonStyle(.plain)
                .disabled(index <= dates.startIndex)
                .accessibilityLabel(BriefingViewCopy.previousDateLabel)
            }

            Text(date)
                .font(AIDashTypography.mastheadStatus)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)

            if dates.count >= 2 {
                Button {
                    guard index < dates.index(before: dates.endIndex) else { return }
                    selectedArchiveDate = dates[dates.index(after: index)]
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: AIDashSpacing.controlHitTarget,
                               minHeight: AIDashSpacing.controlHitTarget)
                }
                .buttonStyle(.plain)
                .disabled(index >= dates.index(before: dates.endIndex))
                .accessibilityLabel(BriefingViewCopy.nextDateLabel)
            }

        }
        .foregroundStyle(theme.neutrals.text2)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func sectionJumpRail(containers: [ContainerModel], proxy: ScrollViewProxy?) -> some View {
        if containers.count > 2 {
            ScrollView(.horizontal, showsIndicators: false) {
                sectionJumpRailContent(containers: containers, proxy: proxy)
            }
        }
    }

    private func sectionJumpRailContent(containers: [ContainerModel], proxy: ScrollViewProxy?) -> some View {
        HStack(spacing: AIDashSpace.s8) {
            Button {
                selectedContainerID = nil
            } label: {
                Text(String(localized: "briefing.section_jump.all", defaultValue: "All", bundle: .module))
                    .font(AIDashTypography.mastheadStatus)
                    .foregroundStyle(theme.neutrals.text1)
                    .padding(.horizontal, AIDashSpace.s8)
                    .frame(minHeight: AIDashSpacing.controlHitTarget)
                    .background(theme.neutrals.inner, in: Capsule())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(containers.sorted { $0.order < $1.order }) { container in
                Button {
                    if selectedContainerID == container.id {
                        selectedContainerID = nil
                    } else {
                        selectedContainerID = container.id
                    }
                    if let proxy, selectedContainerID == container.id {
                        withAnimation(.snappy(duration: 0.2)) {
                            proxy.scrollTo(container.id, anchor: .top)
                        }
                    }
                } label: {
                    HStack(spacing: AIDashSpace.s4) {
                        Text(String(format: "%02d", container.order + 1))
                            .font(AIDashTypography.mastheadStatus)
                            .foregroundStyle(theme.neutrals.text3)
                            .monospacedDigit()
                        Text(container.title)
                            .font(AIDashTypography.mastheadStatus)
                            .foregroundStyle(theme.neutrals.text1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, AIDashSpace.s8)
                    .frame(minHeight: AIDashSpacing.controlHitTarget)
                    .background(theme.neutrals.inner, in: Capsule())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        String(
                            localized: "briefing.section_jump.label %@",
                            defaultValue: "Jump to \(container.title)",
                            bundle: .module,
                        )
                    )
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
    private func filteredContainers(_ containers: [ContainerModel]) -> [ContainerModel] {
        guard let selectedContainerID else { return containers }
        guard containers.contains(where: { $0.id == selectedContainerID }) else { return containers }
        return containers.filter { $0.id == selectedContainerID }
    }
    private var availableDates: [String] {
        let storedDates = publishedBriefings.map(\.date)
        let explicitDate: String? = {
            guard case let .populated(date, _, _, _) = explicitState else { return nil }
            return date
        }()
        return Set(storedDates + archiveDates + [explicitDate].compactMap { $0 })
            .sorted()
    }
    private func displayedDate(fallback: String) -> String {
        selectedArchiveDate ?? fallback
    }
    private func hideCard(cardId: String, cardType: CardType, hidden: Bool) {
        if hidden {
            locallyHiddenCardIds.insert(cardId)
        } else {
            locallyHiddenCardIds.remove(cardId)
        }
        onHideCard?(cardId, cardType, hidden)
    }

    private var effectiveHiddenCardIds: Set<String> {
        hiddenCardIds.union(locallyHiddenCardIds)
    }

    private var activeCards: [CardModel] {
        switch resolvedState {
        case let .populated(_, containers, _, _),
             let .staleError(_, containers, _):
            return containers.flatMap(\.cards)
        default:
            return []
        }
    }

    private var activeHiddenCardCount: Int {
        activeCards.reduce(into: 0) { count, card in
            if effectiveHiddenCardIds.contains(card.id) {
                count += 1
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
        Group {
            if !isFallback, publishedAt != nil {
                StatusPill(BriefingViewCopy.liveLabel, tone: .success)
            } else {
                StatusPill(BriefingViewCopy.cachedLabel, tone: .warning)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var resolvedState: BriefingViewState {
        if let explicitState {
            return explicitState
        }
        if let selectedArchiveDate,
           let archived = publishedBriefings.first(where: { $0.date == selectedArchiveDate }) {
            return .populated(date: archived.date, containers: archived.containers,
                              isFallback: archived.date != Self.localTodayString(),
                              publishedAt: archived.publishedAt)
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
                 )
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

    private var staleErrorBanner: some View {
        HStack(spacing: AIDashSpace.s8) {
            StatusPill(BriefingViewCopy.errorLabel, tone: .danger)
            Text(localizedStateText(for: "briefing.error.subtitle"))
                .font(.callout)
                .foregroundStyle(theme.neutrals.text2)
                .lineLimit(2)
            Spacer(minLength: AIDashSpace.s8)
            retryButton
        }
        .padding(AIDashSpace.s12)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: AIDashSpace.s8))
        .overlay {
            RoundedRectangle(cornerRadius: AIDashSpace.s8)
                .stroke(theme.neutrals.border, lineWidth: AIDashChrome.hairlineWidth)
        }
    }

    private var retryButton: some View {
        Button {
            onRetry?()
        } label: {
            Text(String(localized: "briefing.error.retry", defaultValue: "Retry", bundle: .module))
                .font(AIDashTypography.mastheadStatus)
                .frame(minWidth: AIDashSpacing.controlHitTarget,
                       minHeight: AIDashSpacing.controlHitTarget)
        }
        .buttonStyle(.borderedProminent)
        .disabled(onRetry == nil)
        .accessibilityLabel(Text("briefing.error.retry", tableName: "Localizable", bundle: .module))
    }

    private func diagnosticCard(icon: String, titleKey: String, detailKey: String,
                                tone: PillTone) -> some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s12) {
            StatusPill(titleKey == "briefing.error.title" ? BriefingViewCopy.errorLabel : BriefingViewCopy.emptyLabel, tone: tone)
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(icon == "exclamationmark.triangle" ? theme.danger : theme.neutrals.text2)
                .accessibilityHidden(true)
            Text(localizedStateText(for: titleKey))
                .font(.title3.weight(.semibold))
            Text(localizedStateText(for: detailKey))
                .font(.callout)
                .foregroundStyle(theme.neutrals.text2)
            if tone == .danger {
                retryButton
            }
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
            return String(localized: "briefing.empty.title", defaultValue: "No briefings yet", bundle: .module)
        case "briefing.empty.subtitle":
            return String(localized: "briefing.empty.subtitle", defaultValue: "Use the aidash CLI to publish your first one.", bundle: .module)
        case "briefing.empty_containers.title":
            return String(localized: "briefing.empty_containers.title", defaultValue: "No sections in this briefing", bundle: .module)
        case "briefing.empty_containers.subtitle":
            return String(localized: "briefing.empty_containers.subtitle", defaultValue: "This briefing was published without any sections.", bundle: .module)
        case "briefing.error.title":
            return String(localized: "briefing.error.title", defaultValue: "Briefing unavailable", bundle: .module)
        case "briefing.error.subtitle":
            return String(localized: "briefing.error.subtitle", defaultValue: "The briefing could not be loaded. Try again after the host is available.", bundle: .module)
        default:
            return key
        }
    }

    static var pageHorizontalPadding: CGFloat {
        #if os(macOS)
        return AIDashSpacing.pageHorizontalMac
        #else
        return AIDashSpacing.pageHorizontalCompact
        #endif
    }

    static func isTodayBadge(date: String, isFallback: Bool, today: String) -> Bool {
        !isFallback && date == today
    }

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
