import SwiftUI

// MARK: - Star action environment
//
// The Trending card lets the user star a radar item (T003, spec 002 D3).
// Per the AIDashUI red_lines the view layer must remain side-effect-free —
// it can only *emit intent*. So the star affordance reads two things from
// the SwiftUI environment:
//
//   * `starredItemRefs`  — the current already-starred set, so the button
//                          can render filled vs outline without touching
//                          any store.
//   * `onStarItem`       — the intent callback the App layer installs to
//                          persist the toggle. Defaults to a no-op so
//                          previews / snapshots / isolated renders never
//                          crash and gracefully degrade to a pure visual.
//
// `currentCardId` is injected by `CardRouter` around each routed card so
// pure payload views (which receive only their payload, not the CardModel)
// can still tell the callback which card the item belongs to, without
// forcing us to thread the id through every renderer's initializer.

/// Callback shape for a "user wants to (un)star this item" intent.
///
/// - Parameters:
///   - cardId: The originating card's id (from the CardModel), or `""`
///     when the view is rendered outside a `CardRouter` (previews / tests).
///   - itemRef: A stable identifier for the item within the card. For
///     Trending items this is `item.url` (the radar entry's stable key).
///   - desiredStarred: The target state — `true` to star, `false` to unstar.
public typealias OnStarItem = @MainActor (_ cardId: String,
                                          _ itemRef: String,
                                          _ desiredStarred: Bool) -> Void

private struct OnStarItemKey: EnvironmentKey {
    // No-op default: rendering without an App-installed handler must not
    // crash and must not silently mutate anything.
    static let defaultValue: OnStarItem = { _, _, _ in }
}

private struct StarredItemRefsKey: EnvironmentKey {
    // Empty default: nothing is starred until the App layer says so.
    static let defaultValue: Set<String> = []
}

private struct CurrentCardIdKey: EnvironmentKey {
    // Nil default: outside a CardRouter (isolated preview / snapshot), the
    // renderer falls back to `""` when calling `onStarItem`, so a stray tap
    // still resolves to a well-formed (but ignored) intent.
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    /// The App-installed intent handler for starring / unstarring an item.
    /// Defaults to a no-op so views render without side effects.
    var onStarItem: OnStarItem {
        get { self[OnStarItemKey.self] }
        set { self[OnStarItemKey.self] = newValue }
    }

    /// The current set of already-starred item references. Views read this
    /// to decide filled vs outline; they never mutate it.
    var starredItemRefs: Set<String> {
        get { self[StarredItemRefsKey.self] }
        set { self[StarredItemRefsKey.self] = newValue }
    }

    /// The id of the card currently being rendered by `CardRouter`.
    /// Payload views read it so they can forward it to `onStarItem`
    /// without needing the full `CardModel` in their initializer.
    var currentCardId: String? {
        get { self[CurrentCardIdKey.self] }
        set { self[CurrentCardIdKey.self] = newValue }
    }
}

public extension View {
    /// Install the star affordance's environment on a subtree.
    ///
    /// Use from the App layer to wire the persistence side of the intent:
    ///
    /// ```swift
    /// BriefingView(...)
    ///     .starActionEnvironment(
    ///         starred: store.starredRefs,
    ///         onStar: { cardId, ref, desired in store.setStarred(cardId, ref, desired) }
    ///     )
    /// ```
    ///
    /// Both parameters have safe defaults so partial adoption is fine.
    func starActionEnvironment(
        starred: Set<String> = [],
        onStar: @escaping OnStarItem = { _, _, _ in }
    ) -> some View {
        self
            .environment(\.starredItemRefs, starred)
            .environment(\.onStarItem, onStar)
    }
}
