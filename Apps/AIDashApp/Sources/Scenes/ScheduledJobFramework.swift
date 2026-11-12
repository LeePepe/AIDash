#if os(macOS)
import Foundation
import AIDashCore

public enum ScheduledPulsePageTab: String, CaseIterable, Sendable, Equatable, Identifiable {
    case overview
    case needActions

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .overview: return DashboardL10n.tr("dashboard.scheduled_pulse.tab.overview", "总览")
        case .needActions: return DashboardL10n.tr("dashboard.scheduled_pulse.tab.need_actions", "需要处理")
        }
    }
}

public enum ScheduledJobLastResult: String, Codable, Sendable, Equatable {
    case succeeded
    case failed
    case skipped
    case coalesced
    case running
}

public enum ScheduledJobSemanticState: String, Sendable, Equatable, CaseIterable {
    case healthy
    case running
    case partial
    case coalesced
    case failed
    case noState

    public var isProblem: Bool {
        switch self {
        case .partial, .failed: return true
        case .healthy, .running, .coalesced, .noState: return false
        }
    }

    public var semanticHealth: DashboardSemanticHealth {
        switch self {
        case .healthy: return .healthy
        case .partial: return .warning
        case .failed: return .critical
        case .running, .coalesced, .noState: return .neutral
        }
    }

    public var symbolName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .running: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .partial: return "exclamationmark.triangle.fill"
        case .coalesced: return "minus.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .noState: return "questionmark.circle"
        }
    }

    public func displayText(exitCode: Int32? = nil) -> String {
        switch self {
        case .healthy: return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.healthy", "正常")
        case .running: return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.running", "运行中")
        case .partial:
            return exitCode.map { DashboardL10n.format("dashboard.scheduled_pulse.semantic.partial", "已产出 · exit %lld", $0) } ?? DashboardL10n.tr("dashboard.scheduled_pulse.semantic.partial_unknown", "已产出 · exit warning")
        case .coalesced: return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.coalesced", "已合并跳过")
        case .failed: return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.failed", "失败")
        case .noState: return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.no_state", "尚无状态产出")
        }
    }
}

public struct ScheduledJobStageReceipt: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let status: String?
    public let exitCode: Int?
    public let durationSec: Double?
    public let sourceAsOf: String?

    public init(id: String, title: String, status: String? = nil, exitCode: Int? = nil, durationSec: Double? = nil, sourceAsOf: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.exitCode = exitCode
        self.durationSec = durationSec
        self.sourceAsOf = sourceAsOf
    }

    public var semanticState: ScheduledStageState {
        switch status?.lowercased() {
        case "running", "in_progress": return .running
        case "warning", "partial", "degraded": return .warning
        case "failed", "failure", "error": return .failed
        case "passed", "succeeded", "success", "ok": return .passed
        case nil:
            guard let exitCode else { return .unknown }
            return exitCode == 0 ? .passed : .failed
        default: return .unknown
        }
    }
    public var isSuccess: Bool { semanticState == .passed }
    public var isKnown: Bool { semanticState != .unknown }
}

public enum ScheduledStageState: String, Sendable, Equatable {
    case running, warning, failed, passed, unknown
    public var title: String {
        switch self {
        case .running: return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.running", "运行中")
        case .warning: return DashboardL10n.tr("dashboard.scheduled_pulse.stage.warning", "警告")
        case .failed: return DashboardL10n.tr("dashboard.scheduled_pulse.semantic.failed", "失败")
        case .passed: return DashboardL10n.tr("dashboard.scheduled_pulse.stage.passed", "通过")
        case .unknown: return DashboardL10n.tr("dashboard.scheduled_pulse.stage.unknown", "未知")
        }
    }
}

public struct ScheduledJobState: Codable, Sendable, Equatable {
    public let id: ScheduledPulseJobID
    public let updatedAt: Date?
    public let lastResult: ScheduledJobLastResult?
    public let lastRunAt: Date?
    public let summary: String?
    public let overviewMd: String?
    public let stages: [ScheduledJobStageReceipt]
    public let sourceAsOf: String?

    public init(
        id: ScheduledPulseJobID,
        updatedAt: Date? = nil,
        lastResult: ScheduledJobLastResult? = nil,
        lastRunAt: Date? = nil,
        summary: String? = nil,
        overviewMd: String? = nil,
        stages: [ScheduledJobStageReceipt] = [],
        sourceAsOf: String? = nil
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.lastResult = lastResult
        self.lastRunAt = lastRunAt
        self.summary = summary
        self.overviewMd = overviewMd
        self.stages = stages
        self.sourceAsOf = sourceAsOf
    }

    private enum CodingKeys: String, CodingKey { case id, jobID, updatedAt, lastResult, lastRunAt, summary, overviewMd, stages, sourceAsOf }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(ScheduledPulseJobID.self, forKey: .id)
            ?? c.decode(ScheduledPulseJobID.self, forKey: .jobID)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        if let raw = try c.decodeIfPresent(String.self, forKey: .lastResult) {
            switch raw.lowercased() {
            case "succeeded", "success", "ok": lastResult = .succeeded
            case "failed", "failure", "error": lastResult = .failed
            case "skipped": lastResult = .skipped
            case "coalesced": lastResult = .coalesced
            case "running", "in_progress": lastResult = .running
            default: lastResult = nil
            }
        } else {
            lastResult = nil
        }
        lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? c.decodeIfPresent(String.self, forKey: .overviewMd)
        overviewMd = try c.decodeIfPresent(String.self, forKey: .overviewMd)
        stages = try c.decodeIfPresent([ScheduledJobStageReceipt].self, forKey: .stages) ?? []
        sourceAsOf = try c.decodeIfPresent(String.self, forKey: .sourceAsOf)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(lastResult, forKey: .lastResult)
        try c.encodeIfPresent(lastRunAt, forKey: .lastRunAt)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(overviewMd, forKey: .overviewMd)
        try c.encode(stages, forKey: .stages)
        try c.encodeIfPresent(sourceAsOf, forKey: .sourceAsOf)
    }

    public var isSuccess: Bool { lastResult == .succeeded }
    public var isProblem: Bool { lastResult == .failed }
    public var hasOverviewContent: Bool {
        !(overviewMd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

public enum ScheduledJobActionControlKind: String, Codable, Sendable, Equatable {
    case confirm
    case singleSelect
    case multiSelect
    case textInput
}

public struct ScheduledJobActionControl: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ScheduledJobActionControlKind
    public let title: String
    public let options: [String]
    public let maxLength: Int?

    public init(
        id: String,
        kind: ScheduledJobActionControlKind,
        title: String,
        options: [String] = [],
        maxLength: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.options = options
        self.maxLength = kind == .textInput ? min(max(maxLength ?? 80, 0), 80) : nil
    }

    public var effectiveMaxLength: Int { min(maxLength ?? 80, 80) }
}

public struct ScheduledJobAction: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let jobID: ScheduledPulseJobID
    public let createdAt: Date?
    public let title: String
    public let descriptionMd: String
    public let controls: [ScheduledJobActionControl]
    public let revision: String?

    public init(
        id: String,
        jobID: ScheduledPulseJobID,
        createdAt: Date? = nil,
        title: String,
        descriptionMd: String,
        controls: [ScheduledJobActionControl],
        revision: String? = nil
    ) {
        self.id = id
        self.jobID = jobID
        self.createdAt = createdAt
        self.title = title
        self.descriptionMd = descriptionMd
        self.controls = controls
        self.revision = revision
    }

    public var acknowledgementKey: String {
        Self.receiptKey(jobID: jobID.rawValue, actionID: id, revision: revision)
    }

    public static func receiptKey(jobID: String, actionID: String, revision: String?) -> String {
        let base = "\(jobID):\(actionID)"
        return revision.map { "\(base)|revision=\($0)" } ?? base
    }

    public static func receiptKey(itemRef: String?, cardID: String) -> String? {
        guard let itemRef, let separator = itemRef.firstIndex(of: "|") else { return nil }
        let head = String(itemRef[..<separator])
        let responses = try? JSONDecoder().decode([JobActionsResponse].self, from: Data(itemRef[itemRef.index(after: separator)...].utf8))
        let revision = responses?.first { $0.controlID == "revision" }?.value
        let jobID = String(cardID.dropFirst("scheduled-pulse/".count))
        let base = head.contains(":") ? head : "\(jobID):\(head)"
        return revision.map { "\(base)|revision=\($0)" } ?? base
    }

    /// Returns whether this action has a receipt for its current producer revision.
    public func isAcknowledged(in acknowledgedIDs: Set<String>) -> Bool {
        acknowledgedIDs.contains(acknowledgementKey)
    }

    public func resolvedResponses(
        values: [String: String],
        selectedValues: [String: Set<String>]
    ) -> [ScheduledJobActionResponse] {
        controls.map { control in
            switch control.kind {
            case .multiSelect:
                let resolvedValue = selectedValues[control.id]?.sorted().joined(separator: ",")
                    ?? values[control.id]
                    ?? "确认"
                return ScheduledJobActionResponse(controlID: control.id, value: resolvedValue, maxLength: nil)
            case .singleSelect:
                let resolvedValue = values[control.id] ?? control.options.first ?? "确认"
                return ScheduledJobActionResponse(controlID: control.id, value: resolvedValue, maxLength: nil)
            case .confirm:
                let resolvedValue = values[control.id] ?? "确认"
                return ScheduledJobActionResponse(controlID: control.id, value: resolvedValue, maxLength: nil)
            case .textInput:
                let resolvedValue = values[control.id] ?? "确认"
                return ScheduledJobActionResponse(
                    controlID: control.id,
                    value: resolvedValue,
                    maxLength: control.effectiveMaxLength
                )
            }
        }
    }
}

public struct ScheduledJobActionResponse: Codable, Sendable, Equatable {
    public let controlID: String
    public let value: String

    public init(
        controlID: String,
        value: String,
        maxLength: Int? = 80
    ) {
        self.controlID = controlID
        if let maxLength {
            self.value = String(value.prefix(min(max(maxLength, 0), 80)))
        } else {
            self.value = value
        }
    }
}

public struct ScheduledJobFrameworkEntry: Sendable, Equatable, Identifiable {
    public let definition: ScheduledJobDefinition
    public let state: ScheduledJobState?
    public let launchdStatus: ScheduledJobStatus?
    public let actions: [ScheduledJobAction]

    public init(
        definition: ScheduledJobDefinition,
        state: ScheduledJobState?,
        actions: [ScheduledJobAction] = [],
        launchdStatus: ScheduledJobStatus? = nil
    ) {
        self.definition = definition
        self.state = state
        self.actions = actions
        self.launchdStatus = launchdStatus
    }

    public var id: ScheduledPulseJobID { definition.id }
    public var semanticState: ScheduledJobSemanticState {
        ScheduledJobFrameworkLogic.semanticState(state: state, launchdStatus: launchdStatus)
    }
    public var isSuccess: Bool { semanticState == .healthy }
    public var isProblem: Bool { semanticState.isProblem }
    public var lastRunAt: Date? { state?.lastRunAt ?? launchdStatus?.lastRun }
    public var lastTick: Date? { launchdStatus?.lastTick ?? launchdStatus?.lastRun }
    public var launchdExitCode: Int32? { launchdStatus?.lastExitCode }
    public var statusText: String { semanticState.displayText(exitCode: launchdExitCode) }
}

public struct ScheduledJobFrameworkSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let entries: [ScheduledJobFrameworkEntry]

    public init(capturedAt: Date, entries: [ScheduledJobFrameworkEntry]) {
        self.capturedAt = capturedAt
        self.entries = entries
    }

    public var unacknowledgedActions: [ScheduledJobAction] {
        entries.flatMap(\.actions)
    }

    public var overviewEntries: [ScheduledJobFrameworkEntry] {
        entries
            .sorted { lhs, rhs in
                if lhs.isProblem != rhs.isProblem { return lhs.isProblem }
                switch (lhs.lastRunAt, rhs.lastRunAt) {
                case let (left?, right?) where left != right: return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.definition.displayName < rhs.definition.displayName
                }
            }
    }

    public var allHaveNoState: Bool { entries.allSatisfy { $0.state == nil } }
}

public struct ScheduledJobOverviewSection: Sendable, Equatable, Identifiable {
    public let heading: String
    public let bullets: [String]

    public init(heading: String, bullets: [String]) {
        self.heading = heading
        self.bullets = bullets
    }

    public var id: String { heading }
    public var isPriority: Bool {
        let normalized = heading.lowercased()
        return normalized.contains("awaiting pop actions")
            || normalized.contains("awaiting owner decisions")
            || normalized.contains("actionable v2 feed")
    }
    public var isWatchedPRs: Bool { heading.lowercased().contains("watched pr") }
}

public enum ScheduledJobTimeFormatting {
    public static func relativeText(from date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        let value: String
        if seconds < 60 {
            value = DashboardL10n.tr("dashboard.scheduled_pulse.time.now", "now")
        } else if seconds < 3_600 {
            value = DashboardL10n.format("dashboard.scheduled_pulse.time.minutes_ago", "%lldm ago", Int64(seconds / 60))
        } else if seconds < 86_400 {
            value = DashboardL10n.format("dashboard.scheduled_pulse.time.hours_ago", "%lldh ago", Int64(seconds / 3_600))
        } else {
            value = DashboardL10n.format("dashboard.scheduled_pulse.time.days_ago", "%lldd ago", Int64(seconds / 86_400))
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(value) · \(formatter.string(from: date))"
    }
}

public enum ScheduledJobFrameworkLogic {
    public static func semanticState(
        state: ScheduledJobState?,
        launchdStatus: ScheduledJobStatus?
    ) -> ScheduledJobSemanticState {
        let stages = state?.stages ?? []
        if state?.lastResult == .running || stages.contains(where: { $0.semanticState == .running }) { return .running }
        if state?.lastResult == .failed || stages.contains(where: { $0.semanticState == .failed }) { return .failed }
        if stages.contains(where: { $0.semanticState == .warning }) { return .partial }
        if state?.lastResult == .coalesced || state?.lastResult == .skipped {
            return .coalesced
        }
        if state?.lastResult == .succeeded {
            if let launchdStatus, let code = launchdStatus.lastExitCode, code != 0 { return .partial }
            guard stages.count == 5, stages.allSatisfy(\.isSuccess) else { return .noState }
            return .healthy
        }
        if let launchdStatus, launchdStatus.health == .critical || (launchdStatus.lastExitCode ?? 0) != 0 {
            return .failed
        }
        return .noState
    }

    public static func parseOverview(_ markdown: String?) -> [ScheduledJobOverviewSection] {
        guard let markdown else { return [] }
        var sections: [ScheduledJobOverviewSection] = []
        var heading: String?
        var bullets: [String] = []
        func flush() {
            guard let heading, !heading.isEmpty else { return }
            sections.append(ScheduledJobOverviewSection(heading: heading, bullets: bullets))
        }
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("## ") {
                flush()
                heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                bullets = []
            } else if line.hasPrefix("- ") {
                bullets.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        flush()
        return sections
    }

    public static func prioritizedBullets(
        for section: ScheduledJobOverviewSection
    ) -> (visible: [String], collapsed: [String]) {
        guard section.isWatchedPRs || section.bullets.count > 8 else {
            return (section.bullets, [])
        }
        let priority = section.bullets.filter { bullet in
            let normalized = bullet.uppercased()
            return normalized.contains("FAILURE") || normalized.contains("PENDING")
        }
        let remainder = section.bullets.filter { !priority.contains($0) }
        return (priority, remainder)
    }

    public static func successStripText(for snapshot: ScheduledJobFrameworkSnapshot) -> String {
        snapshot.entries.map { entry in
            "\(entry.definition.displayName) \(entry.statusText)"
        }.joined(separator: " · ")
    }

    public static func unacknowledgedActions(
        from snapshot: ScheduledJobFrameworkSnapshot,
        acknowledgedIDs: Set<String>
    ) -> [ScheduledJobAction] {
        snapshot.unacknowledgedActions.filter { !$0.isAcknowledged(in: acknowledgedIDs) }
    }

    public static func response(
        control: ScheduledJobActionControl,
        value: String
    ) -> ScheduledJobActionResponse {
        ScheduledJobActionResponse(controlID: control.id, value: value)
    }
}

public enum ScheduledJobFireResult: Sendable, Equatable {
    case started
    case coalesced
}

public actor ScheduledJobRunCoordinator {
    private var running: Set<ScheduledPulseJobID> = []

    public init() {}

    public func fire(
        id: ScheduledPulseJobID,
        operation: @escaping @Sendable () async -> Void
    ) async -> ScheduledJobFireResult {
        guard running.insert(id).inserted else { return .coalesced }
        await operation()
        running.remove(id)
        return .started
    }
}
#endif
