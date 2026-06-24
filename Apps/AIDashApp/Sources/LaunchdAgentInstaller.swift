#if os(macOS)
import Foundation

/// Manages the LaunchAgent plist so AIDash starts at login.
/// TODO(T110): Full LaunchAgent installation and update logic.
@MainActor
final class LaunchdAgentInstaller {
    static let shared = LaunchdAgentInstaller()

    private init() {}

    func registerIfNeeded() {
        // TODO(T110): Install/update LaunchAgent plist if not already registered
    }
}
#endif
