import SwiftUI
import AIDashCore
import DesignKit

/// Spec 005 (D1/D4/D5): a whole-card star toggle attached at the `CardRouter`
/// level so every card type gets it "for free" (sectionHeader excepted — it
/// has no chrome to attach to). Visually mirrors `StarItemButton`
/// (`TrendingCardView.swift`): filled/outline SF Symbol tinted with the brand
/// primary, a snappy replace animation on tap. Only emits an intent through
/// the injected `onStarCard` environment closure; when nothing is injected
/// (previews, snapshots) it degrades to a visual no-op.
///
/// Per D1 this is the "whole card" star (`itemRef == nil`), distinct from and
/// coexisting with any per-item star a card type may also render (e.g. the
/// trending radar's `StarItemButton`).
struct WholeCardStarButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.onStarCard) private var onStarCard
    @Environment(\.onHideCard) private var onHideCard
    let cardId: String
    let cardType: CardType
    let isStarred: Bool
    let isHidden: Bool

    /// Optimistic fill: the persisted star event only flows back through
    /// `starredCardIds` on the next SwiftData refresh, so the tap flips the
    /// glyph immediately (spec 005 US1: filled within 100ms).
    @State private var tappedStar = false

    private var filled: Bool { isStarred || tappedStar }

    init(cardId: String, cardType: CardType, isStarred: Bool, isHidden: Bool = false) {
        self.cardId = cardId
        self.cardType = cardType
        self.isStarred = isStarred
        self.isHidden = isHidden
    }

    var body: some View {
        HStack(spacing: AIDashSpace.s4) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { tappedStar = true }
                onStarCard?(cardId, cardType.rawValue)
            } label: {
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(filled ? theme.primary.primary : theme.neutrals.text3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: AIDashSpacing.starButtonHitTarget,
                           minHeight: AIDashSpacing.starButtonHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(filled ? Self.starredLabel : Self.starLabel)

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    onHideCard?(cardId, cardType, !isHidden)
                }
            } label: {
                Image(systemName: isHidden ? "eye" : "eye.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.neutrals.text3)
                    .frame(minWidth: AIDashSpacing.starButtonHitTarget,
                           minHeight: AIDashSpacing.starButtonHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isHidden ? Self.showLabel : Self.hideLabel)
        }
        .accessibilityElement(children: .contain)
    }

    private static let hideLabel = String(
        localized: "card_router.hide_card.label",
        defaultValue: "Hide this card",
        bundle: .module,
        comment: "VoiceOver label for the whole-card hide button."
    )

    private static let showLabel = String(
        localized: "card_router.show_card.label",
        defaultValue: "Show this card",
        bundle: .module,
        comment: "VoiceOver label for the whole-card show button."
    )

    private static let starLabel = String(
        localized: "card_router.star_card.label",
        defaultValue: "Star this card",
        bundle: .module,
        comment: "VoiceOver label for the whole-card star button on a card that is not yet starred."
    )

    private static let starredLabel = String(
        localized: "card_router.star_card.label.starred",
        defaultValue: "Card starred",
        bundle: .module,
        comment: "VoiceOver label for the whole-card star button on a card that is already starred."
    )
}

#Preview("Outline — not starred") {
    WholeCardStarButton(cardId: "card-1", cardType: .metric, isStarred: false)
        .padding()
}

#Preview("Filled — starred") {
    WholeCardStarButton(cardId: "card-1", cardType: .metric, isStarred: true)
        .padding()
}
