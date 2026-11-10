import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

enum AIDashTelemetrySettingsPlacement {
    static func isAvailable(headless: Bool, hasCoordinator: Bool) -> Bool {
        !headless && hasCoordinator
    }
}
enum AIDashWindowGeometry {
    static let macMinWidth: CGFloat = 880
    static let macMinHeight: CGFloat = 580

    static func requiresDesktopMinFrame(isMacOS: Bool) -> Bool {
        isMacOS
    }
}
/// The main briefing window scene. Hosts AIDashMacWorkspaceView on macOS when
/// the container is ready, or shows a native state view on loading/failure.
public struct BriefingWindowScene: Scene {
    let state: CloudKitContainer.InitState
    let headless: Bool
    let telemetryCoordinator: AIDashTelemetryCoordinator?

    init(
        state: CloudKitContainer.InitState,
        headless: Bool = false,
        telemetryCoordinator: AIDashTelemetryCoordinator? = nil
    ) {
        self.state = state
        self.headless = headless
        self.telemetryCoordinator = telemetryCoordinator
    }

    public var body: some Scene {
        WindowGroup {
            Group {
                if headless {
                    EmptyView()
                } else {
                    switch state {
                    case .loading:
                        BriefingSceneStateView(kind: .loading)
                    case .ready(let container):
                        StarFeedbackScope(
                            container: container,
                            telemetryCoordinator: telemetryCoordinator
                        )
                            .modelContainer(container)
                            .onAppear {
                                telemetryCoordinator?.readySceneAppeared()
                            }
                    case .failed(let reason):
                        BriefingSceneStateView(kind: .failed(reason))
                    }
                }
            }
            #if os(macOS)
            .frame(
                minWidth: AIDashWindowGeometry.macMinWidth,
                minHeight: AIDashWindowGeometry.macMinHeight
            )
            .windowDismissBehavior(.disabled)
            #else
            .overlay(alignment: .topTrailing) {
                telemetrySettingsMenu
                    .padding()
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        #endif
    }

    #if !os(macOS)
    @ViewBuilder
    private var telemetrySettingsMenu: some View {
        if AIDashTelemetrySettingsPlacement.isAvailable(
            headless: headless,
            hasCoordinator: telemetryCoordinator != nil
        ), let telemetryCoordinator {
            Menu {
                AIDashTelemetrySettingsView(coordinator: telemetryCoordinator)
            } label: {
                telemetrySettingsLabel
            }
        }
    }

    private var telemetrySettingsLabel: some View {
        Label(
            String(
                localized: "telemetry.settings.title",
                defaultValue: "Usage data",
                bundle: .main
            ),
            systemImage: "gearshape"
        )
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
    #endif
}

private struct BriefingSceneStateView: View {
    enum Kind {
        case loading
        case failed(String)
    }

    let kind: Kind

    var body: some View {
        Group {
            switch kind {
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(reason):
                ContentUnavailableView {
                    Label(title, systemImage: "icloud.slash")
                } description: {
                    Text("\(detail)\n\(reason)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var title: String {
        switch kind {
        case .loading:
            return String(localized: "briefing.scene.loading.title", defaultValue: "Loading briefing", bundle: .main)
        case .failed:
            return String(localized: "briefing.scene.error.title", defaultValue: "Briefing unavailable", bundle: .main)
        }
    }

    private var detail: String {
        switch kind {
        case .loading:
            return String(localized: "briefing.scene.loading.subtitle", defaultValue: "Preparing today’s briefing.", bundle: .main)
        case .failed:
            return String(localized: "briefing.scene.error.subtitle", defaultValue: "Check iCloud and try opening the briefing again.", bundle: .main)
        }
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
    let telemetryCoordinator: AIDashTelemetryCoordinator?

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
    @Query private var scheduledActionEvents: [UserEventModel]

    init(
        container: ModelContainer,
        telemetryCoordinator: AIDashTelemetryCoordinator? = nil
    ) {
        self.container = container
        self.telemetryCoordinator = telemetryCoordinator
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
        let scheduledActionRaw = UserEventAction.acknowledgeJobAction.rawValue
        _scheduledActionEvents = Query(filter: #Predicate {
            $0.actionRaw == scheduledActionRaw
        })
    }

    var body: some View {
        let writer = UserEventWriter(container: container)
        // Intent closures come from the shared `StarFeedbackActions` factory so
        // the spec 005 §6 wiring test exercises the exact same code path (see
        // StarFeedbackActions.swift). The filled/checked state sets are derived
        // here from `@Query` and injected alongside.
        Group {
            #if os(macOS)
            AIDashMacWorkspaceView(
                scheduledActionWriter: { action, responses in
                    writer.acknowledgeScheduledJobAction(action: action, responses: responses)
                },
                acknowledgedScheduledActionIDs: Set(scheduledActionEvents.compactMap { event in
                    guard let head = event.itemRef?.split(separator: "|", maxSplits: 1).first.map(String.init) else {
                        return nil
                    }
                    if head.contains(":") {
                        return head
                    }
                    let prefix = "scheduled-pulse/"
                    if event.cardId.hasPrefix(prefix) {
                        let jobRaw = String(event.cardId.dropFirst(prefix.count))
                        if !jobRaw.isEmpty {
                            return "\(jobRaw):\(head)"
                        }
                    }
                    return head
                })
            )
            #else
            BriefingView()
            #endif
        }
        .starFeedbackActions(StarFeedbackActions(writer: writer))
        .environment(\.starredItemRefs, Set(starEvents.compactMap(\.itemRef)))
        .environment(\.starredCardIds, Set(cardStarEvents.map(\.cardId)))
        .environment(\.doneItemRefs, UserEventWriter.doneRefs(from: doneEvents))
    }
}
