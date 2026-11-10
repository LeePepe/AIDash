#if os(macOS)
import Foundation

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
}

public struct ScheduledJobState: Codable, Sendable, Equatable {
    public let id: ScheduledPulseJobID
    public let updatedAt: Date?
    public let lastResult: ScheduledJobLastResult?
    public let lastRunAt: Date?
    public let summary: String?
    public let overviewMd: String?

    public init(
        id: ScheduledPulseJobID,
        updatedAt: Date? = nil,
        lastResult: ScheduledJobLastResult? = nil,
        lastRunAt: Date? = nil,
        summary: String? = nil,
        overviewMd: String? = nil
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.lastResult = lastResult
        self.lastRunAt = lastRunAt
        self.summary = summary
        self.overviewMd = overviewMd
    }

    public var isSuccess: Bool { lastResult == .succeeded }
    public var isProblem: Bool { !isSuccess }
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

    public init(
        id: String,
        jobID: ScheduledPulseJobID,
        createdAt: Date? = nil,
        title: String,
        descriptionMd: String,
        controls: [ScheduledJobActionControl]
    ) {
        self.id = id
        self.jobID = jobID
        self.createdAt = createdAt
        self.title = title
        self.descriptionMd = descriptionMd
        self.controls = controls
    }

    public var acknowledgementKey: String {
        "\(jobID.rawValue):\(id)"
    }

    public func isAcknowledged(in acknowledgedIDs: Set<String>) -> Bool {
        acknowledgedIDs.contains(acknowledgementKey)
    }

    public func resolvedResponses(
        values: [String: String],
        selectedValues: [String: Set<String>]
    ) -> [ScheduledJobActionResponse] {
        controls.map { control in
            let resolvedValue: String
            switch control.kind {
            case .multiSelect:
                resolvedValue = selectedValues[control.id]?.sorted().joined(separator: ",")
                    ?? values[control.id]
                    ?? "确认"
            case .singleSelect:
                resolvedValue = values[control.id] ?? control.options.first ?? "确认"
            case .confirm, .textInput:
                resolvedValue = values[control.id] ?? "确认"
            }
            return ScheduledJobActionResponse(controlID: control.id, value: resolvedValue)
        }
    }
}

public struct ScheduledJobActionResponse: Codable, Sendable, Equatable {
    public let controlID: String
    public let value: String

    public init(controlID: String, value: String) {
        self.controlID = controlID
        self.value = String(value.prefix(80))
    }
}

public struct ScheduledJobFrameworkEntry: Sendable, Equatable, Identifiable {
    public let definition: ScheduledJobDefinition
    public let state: ScheduledJobState?
    public let actions: [ScheduledJobAction]

    public init(definition: ScheduledJobDefinition, state: ScheduledJobState?, actions: [ScheduledJobAction] = []) {
        self.definition = definition
        self.state = state
        self.actions = actions
    }

    public var id: ScheduledPulseJobID { definition.id }
    public var isSuccess: Bool { state?.isSuccess == true }
    public var isProblem: Bool { !isSuccess }
    public var lastRunAt: Date? { state?.lastRunAt }
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
            .filter { $0.state?.hasOverviewContent == true }
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

public enum ScheduledJobFrameworkLogic {
    public static func successStripText(for snapshot: ScheduledJobFrameworkSnapshot) -> String {
        snapshot.entries.map { entry in
            "\(entry.definition.displayName) \(entry.isSuccess ? "✓" : "✗")"
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
