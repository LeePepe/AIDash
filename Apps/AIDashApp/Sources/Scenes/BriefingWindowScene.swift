import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI
import DesignKit

/// The main briefing window scene. Hosts BriefingView when the
/// CloudKit container is ready, or shows an error state on failure.
public struct BriefingWindowScene: Scene {
    let state: CloudKitContainer.InitState

    public init(state: CloudKitContainer.InitState) {
        self.state = state
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
                switch state {
                case .ready(let container):
                    BriefingView()
                        .designTheme(seed: .lime, neutral: .slate)
                        .modelContainer(container)
                case .failed(let reason):
                    ICloudUnavailableView(reason: reason)
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
