import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI
import DesignKit

enum AIDashTelemetrySettingsPlacement {
    static func isAvailable(headless: Bool, hasCoordinator: Bool) -> Bool {
        !headless && hasCoordinator
    }
}
enum AIDashWindowGeometry {
    static let macMinWidth: CGFloat = 720
    static let macMinHeight: CGFloat = 480

    static func requiresDesktopMinFrame(isMacOS: Bool) -> Bool {
        isMacOS
    }
}
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
            .designTheme(seed: .lime, neutral: .slate)
            #if os(macOS)
            .frame(
                minWidth: AIDashWindowGeometry.macMinWidth,
                minHeight: AIDashWindowGeometry.macMinHeight
            )
            .windowDismissBehavior(.disabled)
            .toolbar {
                ToolbarItem {
                    telemetrySettingsMenu
                }
            }
            #else
            .overlay(alignment: .topTrailing) {
                telemetrySettingsMenu
                    .padding()
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1024, height: 720)
        .windowResizability(.contentMinSize)
        #endif
    }

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
        #if !os(macOS)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        #endif
    }
}

private struct BriefingSceneStateView: View {
    enum Kind {
        case loading
        case failed(String)
    }

    let kind: Kind
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AIDashSpacing.containerVertical) {
                HStack(alignment: .firstTextBaseline) {
                    Text("AIDash")
                        .font(AIDashTypography.masthead)
                        .foregroundStyle(theme.neutrals.text1)
                    Spacer()
                    Text(statusLabel)
                        .font(AIDashTypography.mastheadStatus)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, AIDashSpace.s8)
                        .padding(.vertical, AIDashSpace.s4)
                        .background(theme.neutrals.inner, in: Capsule())
                }
                Rectangle()
                    .fill(theme.neutrals.border)
                    .frame(height: AIDashChrome.hairlineWidth)
                VStack(alignment: .leading, spacing: AIDashSpace.s12) {
                    Image(systemName: iconName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(statusColor)
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.neutrals.text1)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(theme.neutrals.text2)
                    if case let .failed(reason) = kind {
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(theme.neutrals.text2)
                            .textSelection(.enabled)
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
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.vertical, AIDashSpacing.pageVertical)
            .frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(theme.neutrals.bg)
    }

    private var statusLabel: String {
        switch kind {
        case .loading:
            return String(localized: "briefing.scene.loading.status", defaultValue: "SYNCING", bundle: .main)
        case .failed:
            return String(localized: "briefing.scene.error.status", defaultValue: "ERROR", bundle: .main)
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

    private var iconName: String {
        switch kind {
        case .loading: return "arrow.triangle.2.circlepath"
        case .failed: return "icloud.slash"
        }
    }

    private var statusColor: Color {
        switch kind {
        case .loading: return theme.primary.primary
        case .failed: return theme.danger
        }
    }

    private var pageHorizontalPadding: CGFloat {
        #if os(macOS)
        return AIDashSpacing.pageHorizontalMac
        #else
        return AIDashSpacing.pageHorizontalCompact
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
