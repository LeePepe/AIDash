import SwiftUI
import AIDashCore

@MainActor
public struct ContainerView: View {
    let container: ContainerModel

    public init(container: ContainerModel) {
        self.container = container
    }

    /// Cards sorted by id for stable ordering (until a sort key is added to data-model).
    var sortedCards: [CardModel] {
        container.cards.sorted { $0.id < $1.id }
    }

    /// How many cards this container actually renders. The sole input to the
    /// chrome decision (MY-1306) — never `CardType`, never `CardSize`.
    var effectiveCardCount: Int {
        sortedCards.count
    }

    /// The chrome the cards below should draw, derived from this container's
    /// own card count: a lone card goes chrome-less (the title already carries
    /// the grouping), two or more keep a damped frame.
    var chromeMode: CardChromeMode {
        AIDashContainerChrome.chromeMode(effectiveCardCount: effectiveCardCount)
    }

    public var body: some View {
        // No container-level panel, background, or rounded chrome.
        // The container is just typography + spacing — see
        // .specify/memory/constitution.md §Container Chrome.
        //
        // A bare container tightens the header gap (no card padding is left to
        // absorb it) and publishes `.bare` so its lone card drops its frame.
        VStack(alignment: .leading, spacing: headerSpacing) {
            header
            layoutContent
        }
        .environment(\.cardChromeMode, chromeMode)
    }

    /// 12pt when the cards carry their own frames, 10pt when the content sits
    /// directly under the title with nothing between them.
    private var headerSpacing: CGFloat {
        switch chromeMode {
        case .bare:   return AIDashSpacing.containerHeaderToBareContent
        case .framed: return AIDashSpacing.containerHeaderToFirstCard
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(container.title)
                .font(AIDashTypography.section)
                .tracking(AIDashTypography.sectionTracking)
                .foregroundStyle(AIDashTypography.sectionColor)
                .textCase(.uppercase)
                .containerStyleBar(titleBarStyle)
            if let subtitle = container.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AIDashTypography.section)
                    .tracking(AIDashTypography.sectionTracking)
                    .foregroundStyle(AIDashTypography.sectionColor)
            }
        }
    }

    /// The style the title-side bar carries. In `.bare` mode the lone card has
    /// no stripe left to draw, so its `style` moves up here — no signal is
    /// lost. In `.framed` mode each card keeps its own stripe, so the title
    /// stays unadorned (`nil`) rather than duplicating one card's style.
    private var titleBarStyle: CardStyle? {
        guard chromeMode == .bare else { return nil }
        return sortedCards.first?.style
    }

    @ViewBuilder
    private var layoutContent: some View {
        let cards = sortedCards
        switch container.layout {
        case .auto:
            AutoLayout(cards: cards, style: container.style)
        case .list:
            ListLayout(cards: cards, style: container.style)
        case .grid:
            GridLayout(cards: cards, style: container.style)
        case .hero:
            HeroLayout(cards: cards, style: container.style)
        }
    }
}
