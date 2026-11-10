#if os(macOS)
import Darwin
import Foundation

@MainActor
public final class ScheduledPulseLaunchdInstaller {
    public static let shared = ScheduledPulseLaunchdInstaller()

    public enum RegistrationOutcome: Equatable, Sendable {
        case registered
        case failed(jobID: ScheduledPulseJobID, reason: String)

        public var isHealthy: Bool {
            if case .registered = self { return true }
            return false
        }
    }

    public enum Plan: Equatable, Sendable {
        case upToDate
        case install
        case skipReserved
    }

    public typealias PlistURLProvider = @MainActor (ScheduledJobDefinition) -> URL
    public typealias InstalledPlistReader = @MainActor (URL) -> Data?
    public typealias DirectoryCreator = @MainActor (URL) throws -> Void
    public typealias PlistWriter = @MainActor (URL, Data) throws -> Void
    public typealias Launchctl = @MainActor (_ args: [String]) -> LaunchdAgentInstaller.LaunchctlResult

    public static let productionLaunchctl: Launchctl = { args in
        LaunchdAgentInstaller.runLaunchctl(args)
    }

    private let registry: [ScheduledJobDefinition]
    private let plistURL: PlistURLProvider
    private let installedPlist: InstalledPlistReader
    private let createDirectory: DirectoryCreator
    private let writePlist: PlistWriter
    private let launchctl: Launchctl

    public init(
        registry: [ScheduledJobDefinition] = ScheduledPulseRegistry.jobs,
        plistURL: @escaping PlistURLProvider = { definition in
            ScheduledPulseLaunchdInstaller.defaultPlistURL(for: definition)
        },
        installedPlist: @escaping InstalledPlistReader = { url in
            try? Data(contentsOf: url)
        },
        createDirectory: @escaping DirectoryCreator = { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        },
        writePlist: @escaping PlistWriter = { url, data in
            try data.write(to: url, options: .atomic)
        },
        launchctl: @escaping Launchctl = ScheduledPulseLaunchdInstaller.productionLaunchctl
    ) {
        self.registry = registry
        self.plistURL = plistURL
        self.installedPlist = installedPlist
        self.createDirectory = createDirectory
        self.writePlist = writePlist
        self.launchctl = launchctl
    }

    public static func plan(installed: Data?, expected: Data?, isLive: Bool) -> Plan {
        guard isLive else { return .skipReserved }
        return installed == expected ? .upToDate : .install
    }

    @discardableResult
    public func registerLiveJobs() -> [RegistrationOutcome] {
        registry.compactMap { definition in
            guard definition.isLive else { return nil }
            return register(definition)
        }
    }

    public static func plistData(for definition: ScheduledJobDefinition) -> Data? {
        guard definition.isLive, let program = definition.program else { return nil }
        let label = xmlEscaped(definition.launchAgentLabel)
        let escapedProgram = xmlEscaped(program)
        let cadenceXML: String
        switch definition.cadence {
        case let .daily(hour, minute, timeZoneIdentifier):
            cadenceXML = """
            <key>StartCalendarInterval</key>
            <dict>
            <key>Hour</key><integer>\(hour)</integer>
            <key>Minute</key><integer>\(minute)</integer>
            <key>TimeZone</key><string>\(xmlEscaped(timeZoneIdentifier))</string>
            </dict>
            """
        case let .interval(seconds):
            cadenceXML = "<key>StartInterval</key><integer>\(seconds)</integer>"
        case .reserved:
            return nil
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>Label</key><string>\(label)</string>
        <key>ProcessType</key><string>Interactive</string>
        <key>Program</key><string>\(escapedProgram)</string>
        \(cadenceXML)
        </dict>
        </plist>
        """
        return Data(xml.utf8)
    }

    public static func defaultLaunchAgentsDirectoryURL(homeURL: URL? = nil) -> URL {
        let home = homeURL ?? currentUserHomeDirectoryURL()
        return home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    public static func defaultPlistURL(for definition: ScheduledJobDefinition, homeURL: URL? = nil) -> URL {
        defaultLaunchAgentsDirectoryURL(homeURL: homeURL)
            .appendingPathComponent("\(definition.launchAgentLabel).plist")
    }

    private func register(_ definition: ScheduledJobDefinition) -> RegistrationOutcome {
        guard let data = Self.plistData(for: definition) else {
            return .failed(jobID: definition.id, reason: "missing live job plist definition")
        }
        let url = plistURL(definition)
        let current = installedPlist(url)
        switch Self.plan(installed: current, expected: data, isLive: definition.isLive) {
        case .skipReserved:
            return .registered
        case .upToDate:
            return .registered
        case .install:
            do {
                try createDirectory(url.deletingLastPathComponent())
                try writePlist(url, data)
            } catch {
                return .failed(jobID: definition.id, reason: "write plist: \(error.localizedDescription)")
            }

            let domain = "gui/\(getuid())"
            let result = launchctl(["bootstrap", domain, url.path])
            guard result.succeeded else {
                return .failed(jobID: definition.id, reason: result.diagnosticSummary)
            }
            return .registered
        }
    }

    private static func currentUserHomeDirectoryURL() -> URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
           let pw = getpwuid(getuid()),
           let homePtr = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePtr), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
#endif
