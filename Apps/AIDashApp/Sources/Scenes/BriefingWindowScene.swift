import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI
import DesignKit

/// The main briefing window scene. Hosts BriefingView when the
/// CloudKit container is ready, or shows an error state on failure.
///
/// `headless` (macOS agent mode): the window content is empty so the
/// launchd-spawned XPC agent presents no UI. Kept as ONE Scene type (rather
/// than branching to `Settings` in the App body) because SwiftUI's SceneBuilder
/// won't return two different Scene types from `App.body` cleanly; varying the
/// window *content* is the well-supported pattern.
public struct BriefingWindowScene: Scene {
    let state: CloudKitContainer.InitState
    let headless: Bool

    public init(state: CloudKitContainer.InitState, headless: Bool = false) {
        self.state = state
        self.headless = headless
    }

    public var body: some Scene {
        WindowGroup {
            // The min-size modifier is applied at a stable position outside the
            // state switch. A state-dependent `.frame(minWidth:minHeight:)`
            // combined with `.windowResizability(.contentMinSize)` made the
            // window's min size flip between branches during the initial layout
            // pass, which triggered SwiftUI's NSHostingView to call
            // `-layoutSubtreeIfNeeded` while it was already laying out — the
            // `_NSDetectedLayoutRecursion` warning Apple has marked as a future
            // hard crash.
            Group {
                if headless {
                    EmptyView()
                } else {
                    switch state {
                    case .loading:
                        ProgressView()
                            .controlSize(.large)
                    case .ready(let container):
                        StarFeedbackScope(container: container)
                            .designTheme(seed: .lime, neutral: .slate)
                            .modelContainer(container)
                    case .failed(let reason):
                        ICloudUnavailableView(reason: reason)
                    }
                }
            }
            .frame(minWidth: 720, minHeight: 480)
            #if os(macOS)
            .windowDismissBehavior(.disabled)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1024, height: 720)
        .windowResizability(.contentMinSize)
        #endif
    }
}

/// App-side bridge for the spec 002 star feedback loop, extended in spec 005
/// D3 for whole-card star + TODO done toggle. The UI layer emits intents via
/// injected environment closures (never touching SwiftData directly, per
/// constitution §II D4); this scope injects the real append-only writer plus
/// the persisted state each intent's button needs to render filled/checked,
/// so the UI degrades to "everything unstarred/unchecked" if a query ever
/// comes back empty rather than crashing.
private struct StarFeedbackScope: View {
    let container: ModelContainer

    /// Every persisted star event that targets a specific item. Filled state
    /// is inferred from emitted events (spec 002 D2: append-only, no unstar
    /// in v1), so this doubles as the cross-restart / cross-device memory of
    /// what the user starred (US2).
    @Query private var starEvents: [UserEventModel]

    /// Every persisted whole-card star event (spec 005 D1: `itemRef == nil`).
    /// Kept as a separate query from `starEvents` (itemRef != nil) since the
    /// two star axes are independent — a card being starred says nothing
    /// about whether any of its items are starred, and vice versa.
    @Query private var cardStarEvents: [UserEventModel]

    /// Every persisted done/undone event, scoped down to the current
    /// `doneItemRefs` set via `UserEventWriter.doneRefs(from:)`'s
    /// latest-wins reducer (spec 003 §8, spec 005 D3).
    @Query private var doneEvents: [UserEventModel]

    init(container: ModelContainer) {
        self.container = container
        let starRaw = UserEventAction.star.rawValue
        _starEvents = Query(filter: #Predicate {
            $0.actionRaw == starRaw && $0.itemRef != nil
        })
        _cardStarEvents = Query(filter: #Predicate {
            $0.actionRaw == starRaw && $0.itemRef == nil
        })
        let doneRaw = UserEventAction.done.rawValue
        let undoneRaw = UserEventAction.undone.rawValue
        _doneEvents = Query(filter: #Predicate {
            $0.actionRaw == doneRaw || $0.actionRaw == undoneRaw
        })
    }

    var body: some View {
        let writer = UserEventWriter(container: container)
        // Intent closures come from the shared `StarFeedbackActions` factory so
        // the spec 005 §6 wiring test exercises the exact same code path (see
        // StarFeedbackActions.swift). The filled/checked state sets are derived
        // here from `@Query` and injected alongside.
        BriefingView()
            .starFeedbackActions(StarFeedbackActions(writer: writer))
            .environment(\.starredItemRefs, Set(starEvents.compactMap(\.itemRef)))
            .environment(\.starredCardIds, Set(cardStarEvents.map(\.cardId)))
            .environment(\.doneItemRefs, UserEventWriter.doneRefs(from: doneEvents))
    }
}

/// Placeholder until T133 ships the real error scene.
struct ICloudUnavailableView: View {
    let reason: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(String(
                localized: "briefing.storage_unavailable.title",
                defaultValue: "iCloud unavailable",
                bundle: .main,
                comment: "Title shown in the BriefingWindowScene fallback when CloudKit container init fails."
            ))
                .font(.title2.bold())
            Text(reason)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(48)
    }
}
