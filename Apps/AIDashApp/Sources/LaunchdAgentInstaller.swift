#if os(macOS)
import Foundation
import os

private let logger = Logger(subsystem: "com.tianpli.aidash", category: "LaunchdAgentInstaller")

/// Manages the LaunchAgent plist so AIDash starts at login.
/// Writes a minimal plist to ~/Library/LaunchAgents/ if not already present.
/// TODO(T110): Full LaunchAgent update, version check, and uninstall logic.
@MainActor
final class LaunchdAgentInstaller {
    static let shared = LaunchdAgentInstaller()

    private static let agentLabel = "com.tianpli.aidash.agent"
    private static let plistFilename = "com.tianpli.aidash.agent.plist"

    private init() {}

    func registerIfNeeded() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDir.appendingPathComponent(Self.plistFilename)

        guard !FileManager.default.fileExists(atPath: plistURL.path) else {
            logger.info("LaunchAgent plist already exists at \(plistURL.path, privacy: .public).")
            return
        }

        guard let appPath = Bundle.main.executablePath else {
            logger.error("Cannot determine app executable path for LaunchAgent registration.")
            return
        }

        let plist: [String: Any] = [
            "Label": Self.agentLabel,
            "ProgramArguments": [appPath],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
        ]

        do {
            // Ensure ~/Library/LaunchAgents/ exists
            try FileManager.default.createDirectory(
                at: launchAgentsDir,
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)
            logger.info("LaunchAgent plist written to \(plistURL.path, privacy: .public).")
        } catch {
            logger.error("Failed to write LaunchAgent plist: \(error, privacy: .public).")
        }
    }
}
#endif
