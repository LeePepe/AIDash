import SwiftUI

/// Intent emitted when the user taps a per-item star button (spec 002, star
/// feedback loop). Carries the hosting card's id plus the item's stable
/// identifier (for the radar, the repo URL). `@MainActor` because taps are
/// handled on the main actor and the App-layer writer is `@MainActor`;
/// `@Sendable` so the value can live in a (concurrency-safe) environment key.
public typealias StarItemAction = @MainActor @Sendable (_ cardId: String, _ itemRef: String) -> Void

/// Intent emitted when the user taps the whole-card star button (spec 005
/// D1/D4). Carries the card's id plus its `CardType.rawValue`, since the
/// App-layer writer needs the type to mint `UserEvent.starCard`.
public typealias StarCardAction = @MainActor @Sendable (_ cardId: String, _ cardType: String) -> Void

/// Intent emitted when the user toggles a TodoList item's completion circle
/// (spec 005 D3/D4, fixing the done UI->writer wiring gap from spec 003).
/// Carries the hosting card's id, the item's stable ref (`stableItemRef`),
/// and the target state (`true` = mark done, `false` = mark undone).
public typealias ToggleDoneAction = @MainActor @Sendable (_ cardId: String, _ itemRef: String, _ done: Bool) -> Void

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

private struct OnStarCardKey: EnvironmentKey {
    static let defaultValue: StarCardAction? = nil
}

private struct StarredCardIdsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

private struct OnToggleDoneKey: EnvironmentKey {
    static let defaultValue: ToggleDoneAction? = nil
}

private struct DoneItemRefsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
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

    /// App-injected handler for whole-card star taps (spec 005 D4). `nil` =
    /// no writer (preview/test) — the whole-card star button then does
    /// nothing when tapped.
    public var onStarCard: StarCardAction? {
        get { self[OnStarCardKey.self] }
        set { self[OnStarCardKey.self] = newValue }
    }

    /// Card ids with a persisted whole-card star event (`action==star &&
    /// itemRef==nil`). Drives the whole-card star button's filled/outline
    /// state, symmetric to `starredItemRefs`.
    public var starredCardIds: Set<String> {
        get { self[StarredCardIdsKey.self] }
        set { self[StarredCardIdsKey.self] = newValue }
    }

    /// App-injected handler for a TodoList item's done-toggle tap (spec 005
    /// D3/D4). `nil` = no writer (preview/test) — the completion circle then
    /// does nothing when tapped.
    public var onToggleDone: ToggleDoneAction? {
        get { self[OnToggleDoneKey.self] }
        set { self[OnToggleDoneKey.self] = newValue }
    }

    /// Item refs currently in the "done" state (latest-wins, spec 003 §8).
    /// Drives the TodoList completion circle's checked/unchecked glyph,
    /// symmetric to `starredItemRefs`.
    public var doneItemRefs: Set<String> {
        get { self[DoneItemRefsKey.self] }
        set { self[DoneItemRefsKey.self] = newValue }
    }
}
