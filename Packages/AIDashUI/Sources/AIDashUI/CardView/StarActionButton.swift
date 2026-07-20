import SwiftUI

// MARK: - StarActionButton
//
// The trailing star affordance on Trending items (T003).
//
// * Reads the current already-starred set + the intent callback from the
//   environment; installs no local state. Toggling the star is the App
//   layer's job — this button only emits intent.
// * Reads `currentCardId` from the environment (published by `CardRouter`)
//   so pure payload views don't need the CardModel in their initializer.
// * Renders filled vs outline directly from `starredItemRefs.contains(itemRef)`
//   so re-rendering after an external store update is automatic.
// * Uses `theme.primary.primary` as tint — matches the repo Link color, so
//   the star reads as part of the same interactive tint family.
// * Guarantees a ≥ 44×44pt hit target per AC (`Self.hitTarget`), even
//   though the visible glyph is smaller.
//
// This lives beside StarActionEnvironment.swift because they share one
// contract; splitting the file would just fragment the vocabulary.
struct StarActionButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.starredItemRefs) private var starredItemRefs
    @Environment(\.onStarItem) private var onStarItem
    @Environment(\.currentCardId) private var currentCardId

    /// Stable identifier for the item inside the card (for Trending: `item.url`).
    let itemRef: String
    /// Human-readable name used in the accessibility label
    /// ("Star X" / "Unstar X"). Passing it explicitly keeps this view free
    /// of any payload-specific knowledge.
    let itemTitle: String

    private var isStarred: Bool { starredItemRefs.contains(itemRef) }

    var body: some View {
        Button {
            // Emit intent: flip the state. Store side is the App layer's job.
            onStarItem(currentCardId ?? "", itemRef, !isStarred)
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.system(size: Self.glyphSize, weight: .semibold))
                .foregroundStyle(theme.primary.primary)
                .frame(width: Self.hitTarget, height: Self.hitTarget)
                // Subtle press animation — "click 轻动画" per spec.
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())   // full 44×44 tap area, not just the glyph
        .accessibilityLabel(Self.accessibilityLabel(isStarred: isStarred,
                                                    title: itemTitle))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Sizing tokens
    //
    // The glyph reads at ~18pt while keeping a comfortable 44pt hit target;
    // both are pinned to constants (no magic numbers scattered in layout).
    // 44pt is the platform minimum touch target per HIG and the AC.
    static let hitTarget: CGFloat = 44
    static let glyphSize: CGFloat = 18

    // MARK: - Localized strings

    static func accessibilityLabel(isStarred: Bool, title: String) -> String {
        let format = isStarred ? Self.unstarLabelFormat : Self.starLabelFormat
        return String(format: format, title)
    }

    private static let starLabelFormat = String(
        localized: "star_action.button.star",
        defaultValue: "Star %@",
        bundle: .module,
        comment: "VoiceOver label for the trending-item star button when the item is NOT yet starred. %@ is the item title (e.g. a repo name)."
    )

    private static let unstarLabelFormat = String(
        localized: "star_action.button.unstar",
        defaultValue: "Unstar %@",
        bundle: .module,
        comment: "VoiceOver label for the trending-item star button when the item IS already starred. %@ is the item title (e.g. a repo name)."
    )
}
