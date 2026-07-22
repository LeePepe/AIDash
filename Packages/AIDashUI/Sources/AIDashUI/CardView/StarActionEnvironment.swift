import SwiftUI

/// Intent emitted when the user taps a per-item star button (spec 002, star
/// feedback loop). Carries the hosting card's id plus the item's stable
/// identifier (for the radar, the repo URL). `@MainActor` because taps are
/// handled on the main actor and the App-layer writer is `@MainActor`;
/// `@Sendable` so the value can live in a (concurrency-safe) environment key.
public typealias StarItemAction = @MainActor @Sendable (_ cardId: String, _ itemRef: String) -> Void

// Spec 002 D4: the UI layer stays pure — it renders the star state and emits
// the intent through these environment values, never touching SwiftData /
// CloudKit. The App layer injects the real append-only writer; when nothing
// is injected (previews, snapshots, tests) the defaults below degrade the
// star button to a visual no-op that cannot crash.

private struct OnStarItemKey: EnvironmentKey {
    static let defaultValue: StarItemAction? = nil
}

private struct StarredItemRefsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

private struct CurrentCardIdKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    /// App-injected handler for star taps. `nil` = no writer (preview/test) —
    /// star buttons then do nothing when tapped.
    public var onStarItem: StarItemAction? {
        get { self[OnStarItemKey.self] }
        set { self[OnStarItemKey.self] = newValue }
    }

    /// Item refs with a persisted star event. Drives the filled/outline star
    /// glyph (spec 002 D2: filled state is inferred from emitted events, not
    /// from a mutable flag).
    public var starredItemRefs: Set<String> {
        get { self[StarredItemRefsKey.self] }
        set { self[StarredItemRefsKey.self] = newValue }
    }

    /// The id of the card currently being rendered. Set by `CardRouter` so a
    /// payload-driven card view (which never sees its `CardModel`) can still
    /// attribute per-item events to the right card.
    public var currentCardId: String {
        get { self[CurrentCardIdKey.self] }
        set { self[CurrentCardIdKey.self] = newValue }
    }
}
