#if os(macOS)
import Foundation

public enum ScheduledPulseJobID: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case myPRSupervisor = "my-pr-supervisor"
    case prAutoReview = "pr-auto-review"
    case aidataDigest = "aidata-digest"
    case dailyLearning = "daily-learning"
    case linearBotBridge = "linear-bot-bridge"

    public var id: String { rawValue }
}

public enum ScheduledJobCadence: Sendable, Equatable {
    case daily(hour: Int, minute: Int, timeZoneIdentifier: String)
    case interval(seconds: Int)
    case reserved

    public var displayText: String {
        switch self {
        case let .daily(hour, minute, _):
            return DashboardL10n.format(
                "dashboard.scheduled_pulse.cadence.daily_format",
                "Daily %02d:%02d",
                hour,
                minute
            )
        case let .interval(seconds):
            let minutes = max(1, seconds / 60)
            return DashboardL10n.format(
                "dashboard.scheduled_pulse.cadence.interval_format",
                "Every %lld min",
                minutes
            )
        case .reserved:
            return DashboardL10n.tr("dashboard.scheduled_pulse.cadence.reserved", "Later")
        }
    }

    public var isReserved: Bool {
        if case .reserved = self { return true }
        return false
    }
}

public struct ScheduledJobDefinition: Sendable, Equatable, Identifiable {
    public let id: ScheduledPulseJobID
    public let displayName: String
    public let program: String?
    public let cadence: ScheduledJobCadence
    public let isLive: Bool

    public init(
        id: ScheduledPulseJobID,
        displayName: String,
        program: String?,
        cadence: ScheduledJobCadence,
        isLive: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.program = program
        self.cadence = cadence
        self.isLive = isLive
    }

    public var launchAgentLabel: String {
        "com.tianpli.aidash.job.\(id.rawValue)"
    }

    public var sourceText: String {
        DashboardL10n.tr("dashboard.scheduled_pulse.source.aidash", "AIDash-owned")
    }

    public func programPath(homeURL: URL) -> String? {
        guard isLive else { return nil }
        switch id {
        case .prAutoReview:
            return homeURL.appendingPathComponent("Development/handoff/pr-auto-review/precheck.py").path
        case .myPRSupervisor:
            return homeURL.appendingPathComponent("Development/handoff/my-pr-supervisor/precheck.py").path
        case .aidataDigest:
            return homeURL.appendingPathComponent("Development/AIDash/aidata/scripts/aidata_digest_run.sh").path
        case .dailyLearning:
            return homeURL.appendingPathComponent("Development/AIDash/aidata/scripts/daily_learning_run.sh").path
        case .linearBotBridge:
            return homeURL.appendingPathComponent("Development/AIDash/aidata/scripts/linear_bot_bridge_run.sh").path
        }
    }

    public var interpreterPath: String? {
        guard isLive else { return nil }
        switch id {
        case .aidataDigest, .dailyLearning, .linearBotBridge:
            return "/bin/bash"
        case .myPRSupervisor, .prAutoReview:
            return "/usr/bin/python3"
        }
    }

    public func entrypointPath(homeURL: URL) -> String? {
        guard isLive else { return nil }
        return homeURL.appendingPathComponent("Development/AIDash/scripts/scheduled-job-entrypoint.sh").path
    }

    public var commandHint: String? {
        guard isLive else { return nil }
        return "launchctl print gui/$(id -u)/\(launchAgentLabel)"
    }
}

public enum ScheduledPulseRegistry {
    public static func jobs(
        homeURL: URL = HerdrSocketClient.currentUserHomeDirectoryURL(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [ScheduledJobDefinition] {
        let myPR = homeURL.appendingPathComponent("Development/handoff/my-pr-supervisor/precheck.py").path
        let autoReview = homeURL.appendingPathComponent("Development/handoff/pr-auto-review/precheck.py").path
        let digest = homeURL.appendingPathComponent("Development/AIDash/aidata/scripts/aidata_digest_run.sh").path
        let dailyLearning = homeURL.appendingPathComponent("Development/AIDash/aidata/scripts/daily_learning_run.sh").path
        let linearBotBridge = homeURL.appendingPathComponent("Development/AIDash/aidata/scripts/linear_bot_bridge_run.sh").path
        return [
            ScheduledJobDefinition(id: .myPRSupervisor, displayName: DashboardL10n.tr("dashboard.scheduled_pulse.job.my_pr_supervisor", "我的 PR"), program: "~/Development/handoff/my-pr-supervisor/precheck.py", cadence: .interval(seconds: 300), isLive: fileExists(myPR)),
            ScheduledJobDefinition(id: .prAutoReview, displayName: DashboardL10n.tr("dashboard.scheduled_pulse.job.pr_auto_review", "特定人 PR"), program: "~/Development/handoff/pr-auto-review/precheck.py", cadence: .interval(seconds: 300), isLive: fileExists(autoReview)),
            ScheduledJobDefinition(id: .aidataDigest, displayName: DashboardL10n.tr("dashboard.scheduled_pulse.job.aidata_digest", "每日简报"), program: "aidata/scripts/aidata_digest_run.sh", cadence: .daily(hour: 4, minute: 0, timeZoneIdentifier: "Asia/Shanghai"), isLive: fileExists(digest)),
            ScheduledJobDefinition(id: .dailyLearning, displayName: DashboardL10n.tr("dashboard.scheduled_pulse.job.daily_learning", "每日学习推荐"), program: "aidata/scripts/daily_learning_run.sh", cadence: .daily(hour: 4, minute: 15, timeZoneIdentifier: "Asia/Shanghai"), isLive: fileExists(dailyLearning)),
            ScheduledJobDefinition(id: .linearBotBridge, displayName: DashboardL10n.tr("dashboard.scheduled_pulse.job.linear_bot_bridge", "Linear @bot 桥接"), program: "aidata/scripts/linear_bot_bridge_run.sh", cadence: .interval(seconds: 60), isLive: fileExists(linearBotBridge))
        ]
    }

    public static var jobs: [ScheduledJobDefinition] { jobs() }
    public static var liveJobs: [ScheduledJobDefinition] { jobs.filter(\.isLive) }
    public static var reservedJobs: [ScheduledJobDefinition] { jobs.filter { !$0.isLive } }
    public static func job(for id: ScheduledPulseJobID) -> ScheduledJobDefinition? { jobs.first { $0.id == id } }
}

public enum ScheduledPulseHealth: String, Sendable, Equatable, CaseIterable {
    case healthy
    case warning
    case critical
    case expectedOnButIdle
    case reserved

    public var isUnhealthy: Bool {
        switch self {
        case .warning, .critical, .expectedOnButIdle: return true
        case .healthy, .reserved: return false
        }
    }

    public var semanticHealth: DashboardSemanticHealth {
        switch self {
        case .healthy: return .healthy
        case .warning, .expectedOnButIdle: return .warning
        case .critical: return .critical
        case .reserved: return .neutral
        }
    }

    public var label: String {
        switch self {
        case .healthy:
            return DashboardL10n.tr("dashboard.scheduled_pulse.health.healthy", "Healthy")
        case .warning:
            return DashboardL10n.tr("dashboard.scheduled_pulse.health.warning", "Warning")
        case .critical:
            return DashboardL10n.tr("dashboard.scheduled_pulse.health.critical", "Critical")
        case .expectedOnButIdle:
            return DashboardL10n.tr("dashboard.scheduled_pulse.health.expected_idle", "Expected on · idle")
        case .reserved:
            return DashboardL10n.tr("dashboard.scheduled_pulse.health.reserved", "稍后")
        }
    }

    public var exceptionSubtitle: String {
        switch self {
        case .critical: return DashboardL10n.tr("dashboard.scheduled_pulse.exception.failed", "Failed")
        case .warning: return DashboardL10n.tr("dashboard.scheduled_pulse.exception.timeout", "Timeout")
        case .expectedOnButIdle: return DashboardL10n.tr("dashboard.scheduled_pulse.exception.expected_off", "Expected on but idle")
        case .healthy, .reserved: return label
        }
    }
}

public struct ScheduledJobStatus: Sendable, Equatable, Identifiable {
    public let definition: ScheduledJobDefinition
    public let health: ScheduledPulseHealth
    public let isLoaded: Bool
    public let runningPID: Int32?
    public let lastExitCode: Int32?
    public let lastRun: Date?
    public let lastTick: Date?
    public let lastError: String?

    public init(
        definition: ScheduledJobDefinition,
        health: ScheduledPulseHealth,
        isLoaded: Bool = false,
        runningPID: Int32? = nil,
        lastExitCode: Int32? = nil,
        lastRun: Date? = nil,
        lastTick: Date? = nil,
        lastError: String? = nil
    ) {
        self.definition = definition
        self.health = health
        self.isLoaded = isLoaded
        self.runningPID = runningPID
        self.lastExitCode = lastExitCode
        self.lastRun = lastRun
        self.lastTick = lastTick
        self.lastError = lastError
    }

    public var id: ScheduledPulseJobID { definition.id }
    public var isUnhealthy: Bool { definition.isLive && health.isUnhealthy }
    public var statusLabel: String { health.label }
    public var cadenceText: String { definition.cadence.displayText }
    public var resultText: String {
        if let lastError, !lastError.isEmpty { return lastError }
        return health == .reserved
            ? DashboardL10n.tr("dashboard.scheduled_pulse.result.not_implemented", "Not implemented")
            : (health == .healthy
                ? DashboardL10n.tr("dashboard.scheduled_pulse.result.ok", "OK")
                : health.exceptionSubtitle)
    }
}

public struct ScheduledPulseSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let jobs: [ScheduledJobStatus]

    public init(capturedAt: Date, jobs: [ScheduledJobStatus]) {
        self.capturedAt = capturedAt
        self.jobs = jobs
    }

    public static func defaultSnapshot(now: Date = Date()) -> ScheduledPulseSnapshot {
        ScheduledPulseSnapshot(
            capturedAt: now,
            jobs: ScheduledPulseRegistry.jobs.map { definition in
                ScheduledJobStatus(
                    definition: definition,
                    health: definition.isLive ? .healthy : .reserved,
                    lastTick: nil
                )
            }
        )
    }
}

public enum ScheduledPulseKPIMetric: String, CaseIterable, Sendable, Equatable, Identifiable {
    case enabled
    case unhealthy
    case lastTick

    public var id: String { rawValue }
}

public enum ScheduledPulseSchedulerFilter: String, CaseIterable, Sendable, Equatable, Identifiable {
    case all
    case live
    case reserved

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .all: return DashboardL10n.tr("dashboard.scheduled_pulse.filter.scheduler_all", "All")
        case .live: return DashboardL10n.tr("dashboard.scheduled_pulse.filter.scheduler_live", "Live")
        case .reserved: return DashboardL10n.tr("dashboard.scheduled_pulse.filter.scheduler_reserved", "Reserved")
        }
    }
}

public enum ScheduledPulseHealthFilter: String, CaseIterable, Sendable, Equatable, Identifiable {
    case all
    case healthy
    case unhealthy

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .all: return DashboardL10n.tr("dashboard.scheduled_pulse.filter.health_all", "All")
        case .healthy: return DashboardL10n.tr("dashboard.scheduled_pulse.filter.health_healthy", "Healthy")
        case .unhealthy: return DashboardL10n.tr("dashboard.scheduled_pulse.filter.health_unhealthy", "Unhealthy")
        }
    }
}

public enum ScheduledPulseLogic {
    public static func defaultHealthFilter(for snapshot: ScheduledPulseSnapshot) -> ScheduledPulseHealthFilter {
        snapshot.jobs.contains(where: \.isUnhealthy) ? .unhealthy : .all
    }

    public static func filteredJobs(
        from snapshot: ScheduledPulseSnapshot,
        scheduler: ScheduledPulseSchedulerFilter,
        health: ScheduledPulseHealthFilter
    ) -> [ScheduledJobStatus] {
        snapshot.jobs
            .filter { status in
                let schedulerMatches: Bool
                switch scheduler {
                case .all:
                    schedulerMatches = true
                case .live:
                    schedulerMatches = status.definition.isLive
                case .reserved:
                    schedulerMatches = !status.definition.isLive
                }
                guard schedulerMatches else { return false }

                if !status.definition.isLive && scheduler != .live {
                    return true
                }
                switch health {
                case .all: return true
                case .healthy: return status.health == .healthy
                case .unhealthy: return status.isUnhealthy
                }
            }
            .sorted { lhs, rhs in
                let leftRank = healthRank(lhs.health)
                let rightRank = healthRank(rhs.health)
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.definition.displayName.localizedCaseInsensitiveCompare(rhs.definition.displayName) == .orderedAscending
            }
    }

    public static func exceptions(from snapshot: ScheduledPulseSnapshot) -> [ScheduledJobStatus] {
        snapshot.jobs
            .filter { $0.definition.isLive && $0.isUnhealthy }
            .sorted { lhs, rhs in
                let leftRank = healthRank(lhs.health)
                let rightRank = healthRank(rhs.health)
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.definition.displayName.localizedCaseInsensitiveCompare(rhs.definition.displayName) == .orderedAscending
            }
            .prefix(3)
            .map { $0 }
    }

    private static func healthRank(_ health: ScheduledPulseHealth) -> Int {
        switch health {
        case .critical: return 0
        case .warning: return 1
        case .expectedOnButIdle: return 2
        case .healthy: return 3
        case .reserved: return 4
        }
    }
}
#endif
