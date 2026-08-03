import SwiftUI
import AIDashCore
import DesignKit

/// Routes a `CardModel` to the corresponding type-specific card view by decoding
/// its `payloadJSON` via `CardType.decode` (preserving `.iso8601` date handling).
/// On decode failure, renders a generic fallback placeholder (FR-032).
public struct CardRouter: View {
    let card: CardModel
    /// The geometry size to render at — normally the content-derived *effective*
    /// size resolved by the grid (a downgrade of `card.size` when the payload is
    /// too thin to justify the authored size). Defaults to `card.size` so a
    /// router used in isolation renders at the authored geometry.
    let effectiveSize: CardSize
    @Environment(\.theme) private var theme
    @Environment(\.starredCardIds) private var starredCardIds

    public init(card: CardModel, effectiveSize: CardSize? = nil) {
        self.card = card
        self.effectiveSize = effectiveSize ?? card.size
    }

    public var body: some View {
        // Passthrough: each routed card owns its chrome via `.cardChrome`.
        // The router MUST NOT add a second background/border (doing so
        // double-wrapped the card with a mismatched corner radius).
        // `currentCardId` lets payload-driven views (spec 002 star button)
        // attribute per-item events to this card without seeing the model.
        //
        // The star overlay is attached here (not inside `cardContent`) so it
        // covers the fallback placeholder too — a card whose payload failed to
        // decode still has a `card.type`/`card.id` and is just as starrable
        // (spec 005 D1: "every card type except sectionHeader").
        cardContent
            .overlay(alignment: .topTrailing) { starCardOverlay }
            .environment(\.currentCardId, card.id)
    }

    @ViewBuilder
    private var cardContent: some View {
        if let payload = try? card.type.decode(card.payloadJSON) {
            routedView(for: payload)
        } else {
            fallbackView
        }
    }

    // Spec 005 D1/D4/D5: every card type except sectionHeader (which has no
    // chrome to anchor to, and is a typography-only divider per its own
    // header comment) gets a whole-card star button in its top-trailing
    // corner. It floats over the routed view's own chrome/padding rather than
    // participating in card layout, so it can never alter a card's
    // size/style/chrome dimensions (constitution §VI: star is a content
    // signal, not a size/style axis).
    @ViewBuilder
    private var starCardOverlay: some View {
        if card.type != .sectionHeader {
            WholeCardStarButton(
                cardId: card.id,
                cardType: card.type,
                isStarred: starredCardIds.contains(card.id)
            )
            .padding(.trailing, AIDashSpace.s8)
            .padding(.top, AIDashSpace.s8)
        }
    }

    @ViewBuilder
    private func routedView(for payload: any CardPayloadProtocol) -> some View {
        switch payload {
        case let p as MetricPayload:
            MetricCardView(payload: p, size: effectiveSize, style: card.style)
        case let p as InsightPayload:
            InsightCardView(payload: p, size: effectiveSize, style: card.style)
        case let p as AgentSummaryPayload:
            AgentSummaryCardView(payload: p, size: effectiveSize, style: card.style)
        case let p as TodoListPayload:
            TodoListCardView(payload: p, size: effectiveSize, style: card.style)
        case let p as TrendingPayload:
            TrendingCardView(payload: p, size: effectiveSize, style: card.style)
        case let p as DigestPayload:
            DigestCardView(payload: p, size: effectiveSize, style: card.style)
        case let p as SectionHeaderPayload:
            SectionHeaderCardView(payload: p, size: effectiveSize, style: card.style)
        case let p as BarListPayload:
            BarListCardView(payload: p, size: effectiveSize, style: card.style)
        case let p as StackedBarPayload:
            StackedBarCardView(payload: p, size: effectiveSize, style: card.style)
        default:
            fallbackView
        }
    }

    private var fallbackView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            Text(Self.fallbackTitle)
                .font(.headline)
            Text(String(format: Self.fallbackDetailFormat, card.type.rawValue))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome(size: card.size, style: card.style)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Localized strings
    //
    // Per constitution §F.1, user-visible literals are accessed via
    // `String(localized:)` and registered in `Resources/Localizable.xcstrings`
    // so translators can localize them without touching source.

    private static let fallbackTitle = String(
        localized: "card_router.fallback.title",
        defaultValue: "Card unavailable",
        bundle: .module,
        comment: "Headline shown in the CardRouter fallback placeholder when a card payload cannot be decoded."
    )

    private static let fallbackDetailFormat = String(
        localized: "card_router.fallback.detail",
        defaultValue: "Could not decode %@ payload.",
        bundle: .module,
        comment: "Caption shown in the CardRouter fallback placeholder. %@ is the card type raw value (e.g. metric, insight)."
    )
}
