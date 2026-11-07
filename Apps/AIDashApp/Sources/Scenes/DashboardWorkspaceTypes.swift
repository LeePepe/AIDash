#if os(macOS)
import Foundation
import AIDashCore

public enum DashboardL10n {
    public static func tr(_ key: String, _ defaultValue: String) -> String {
        let resolved = Bundle.main.localizedString(forKey: key, value: defaultValue, table: nil)
        if resolved.isEmpty || resolved == key || resolved.hasPrefix("dashboard.") || resolved.hasPrefix("menubar.") {
            return defaultValue
        }
        return resolved
    }

    public static func format(_ key: String, _ defaultFormat: String, _ args: CVarArg...) -> String {
        let formatString = tr(key, defaultFormat)
        return String(format: formatString, arguments: args)
    }
}

public enum DashboardTokenFormatter {
    public static func compact(_ value: UInt64) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000.0)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return value.formatted(.number)
    }
}

public enum DashboardWorkspaceSection: String, CaseIterable, Sendable, Equatable, Identifiable {
    case overview
    case agentEfficiency
    case actionItems
    case systemAndCosts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview:
            return DashboardL10n.tr("dashboard.section.overview", "Overview")
        case .agentEfficiency:
            return DashboardL10n.tr("dashboard.section.agent_efficiency", "Agent Efficiency")
        case .actionItems:
            return DashboardL10n.tr("dashboard.section.action_items", "Actionable Items")
        case .systemAndCosts:
            return DashboardL10n.tr("dashboard.section.system_costs", "System & CLI Costs")
        }
    }

    public var symbolName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .agentEfficiency: return "waveform.path.ecg"
        case .actionItems: return "checklist"
        case .systemAndCosts: return "creditcard.and.123"
        }
    }
}

public enum DashboardCLIFilter: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case all = "All"
    case claude = "Claude Code"
    case codex = "Codex CLI"
    case copilot = "Copilot CLI"
    case kimi = "Kimi CLI"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .all: return DashboardL10n.tr("dashboard.cli.all", "All")
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .copilot: return "Copilot"
        case .kimi: return "Kimi"
        }
    }
}

public enum DashboardSemanticHealth: String, Codable, Sendable, Equatable {
    case healthy
    case warning
    case critical
    case neutral

    public var symbolName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .neutral: return "minus.circle"
        }
    }

    public var label: String {
        switch self {
        case .healthy: return DashboardL10n.tr("dashboard.health.healthy", "Healthy")
        case .warning: return DashboardL10n.tr("dashboard.health.warning", "Warning")
        case .critical: return DashboardL10n.tr("dashboard.health.critical", "Exceeded")
        case .neutral: return DashboardL10n.tr("dashboard.health.neutral", "Idle")
        }
    }
}

public enum DashboardDeltaDirection: String, Codable, Sendable, Equatable {
    case up
    case down
    case flat

    public var symbolName: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "minus"
        }
    }
}

public enum ModularCardKind: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case kpiSummary = "kpi_summary"
    case trendChart = "trend_chart"
    case cliCostQuota = "cli_cost_quota"
    case actionItems = "action_items"
    case rankingTable = "ranking_table"

    public var id: String { rawValue }
}

public struct KPIMetricItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let formattedValue: String
    public let unit: String?
    public let deltaText: String
    public let direction: DashboardDeltaDirection
    public let health: DashboardSemanticHealth
    public let symbolName: String

    public init(
        id: String,
        label: String,
        formattedValue: String,
        unit: String? = nil,
        deltaText: String,
        direction: DashboardDeltaDirection = .flat,
        health: DashboardSemanticHealth = .healthy,
        symbolName: String = "chart.bar.fill"
    ) {
        self.id = id
        self.label = label
        self.formattedValue = formattedValue
        self.unit = unit
        self.deltaText = deltaText
        self.direction = direction
        self.health = health
        self.symbolName = symbolName
    }
}

public struct TrendDataPoint: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let bucketLabel: String
    public let category: String
    public let cliFilter: DashboardCLIFilter
    public let invocations: Int
    public let successRate: Double
    public let costUSD: Double
    public let totalTokens: UInt64

    public init(
        id: String,
        bucketLabel: String,
        category: String,
        cliFilter: DashboardCLIFilter,
        invocations: Int,
        successRate: Double,
        costUSD: Double,
        totalTokens: UInt64 = 0
    ) {
        self.id = id
        self.bucketLabel = bucketLabel
        self.category = category
        self.cliFilter = cliFilter
        self.invocations = invocations
        self.successRate = successRate
        self.costUSD = costUSD
        self.totalTokens = totalTokens
    }
}

public struct CLICostQuotaEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let cliFilter: DashboardCLIFilter
    public let displayName: String
    public let modelTag: String
    public let todayCostUSD: Double
    public let periodCostUSD: Double
    public let quotaLimitUSD: Double
    public let activeTokens: UInt64
    public let cacheTokens: UInt64
    public let interactionCount: UInt64
    public let isAvailable: Bool
    public let quotaUsedOverride: Double?
    public let quotaLabel: String?
    public let periodTotalTokens: UInt64

    public init(
        id: String,
        cliFilter: DashboardCLIFilter,
        displayName: String,
        modelTag: String,
        todayCostUSD: Double,
        periodCostUSD: Double,
        quotaLimitUSD: Double,
        activeTokens: UInt64,
        cacheTokens: UInt64,
        interactionCount: UInt64,
        isAvailable: Bool = true,
        quotaUsedOverride: Double? = nil,
        quotaLabel: String? = nil,
        periodTotalTokens: UInt64? = nil
    ) {
        self.id = id
        self.cliFilter = cliFilter
        self.displayName = displayName
        self.modelTag = modelTag
        self.todayCostUSD = todayCostUSD
        self.periodCostUSD = periodCostUSD
        self.quotaLimitUSD = quotaLimitUSD
        self.activeTokens = activeTokens
        self.cacheTokens = cacheTokens
        self.interactionCount = interactionCount
        self.isAvailable = isAvailable
        self.quotaUsedOverride = quotaUsedOverride
        self.quotaLabel = quotaLabel
        self.periodTotalTokens = periodTotalTokens ?? ((activeTokens + cacheTokens) * 7)
    }

    public var totalTokens: UInt64 {
        activeTokens + cacheTokens
    }

    public var usedFraction: Double {
        if let quotaUsedOverride {
            return min(max(quotaUsedOverride, 0), 1)
        }
        guard quotaLimitUSD > 0 else { return 0 }
        return min(max(todayCostUSD / quotaLimitUSD, 0), 1)
    }

    public var health: DashboardSemanticHealth {
        guard isAvailable else { return .neutral }
        if usedFraction >= 0.90 { return .critical }
        if usedFraction >= 0.75 { return .warning }
        return .healthy
    }
}

public enum DashboardActionPriority: Int, CaseIterable, Codable, Sendable, Equatable, Comparable {
    case p0 = 0
    case p1 = 1
    case p2 = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .p0: return "P0"
        case .p1: return "P1"
        case .p2: return "P2"
        }
    }

    public var health: DashboardSemanticHealth {
        switch self {
        case .p0: return .critical
        case .p1: return .warning
        case .p2: return .neutral
        }
    }
}

public enum DashboardActionFilter: String, CaseIterable, Sendable, Equatable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"
    case highPriorityOnly = "P0 / P1"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .all: return DashboardL10n.tr("dashboard.action_filter.all", "All")
        case .pending: return DashboardL10n.tr("dashboard.action_filter.pending", "Pending")
        case .completed: return DashboardL10n.tr("dashboard.action_filter.completed", "Completed")
        case .highPriorityOnly: return "P0 / P1"
        }
    }
}

public enum DashboardActionSort: String, CaseIterable, Sendable, Equatable, Identifiable {
    case priority = "Priority"
    case source = "Source"
    case title = "Title"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .priority: return DashboardL10n.tr("dashboard.action_sort.priority", "Priority")
        case .source: return DashboardL10n.tr("dashboard.action_sort.source", "Source")
        case .title: return DashboardL10n.tr("dashboard.action_sort.title", "Title")
        }
    }
}

public struct DashboardActionItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let sourceTag: String
    public let cliFilter: DashboardCLIFilter
    public let priority: DashboardActionPriority
    public var isCompleted: Bool
    public let command: String?
    public let externalURLString: String?
    public let backingCardId: String?
    public let backingItemRef: String?

    public init(
        id: String,
        title: String,
        summary: String,
        sourceTag: String,
        cliFilter: DashboardCLIFilter = .all,
        priority: DashboardActionPriority = .p1,
        isCompleted: Bool = false,
        command: String? = nil,
        externalURLString: String? = nil,
        backingCardId: String? = nil,
        backingItemRef: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sourceTag = sourceTag
        self.cliFilter = cliFilter
        self.priority = priority
        self.isCompleted = isCompleted
        self.command = command
        self.externalURLString = externalURLString
        self.backingCardId = backingCardId
        self.backingItemRef = backingItemRef
    }
}

public struct AgentRankingRow: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let agentName: String
    public let cliFilter: DashboardCLIFilter
    public let providerName: String
    public let runs: Int
    public let totalTokens: UInt64
    public let successRate: Double
    public let avgDurationSeconds: Double
    public let costUSD: Double
    public let detailSummary: String
    public let recentIssue: String?

    public init(
        id: String,
        agentName: String,
        cliFilter: DashboardCLIFilter,
        providerName: String,
        runs: Int,
        totalTokens: UInt64,
        successRate: Double,
        avgDurationSeconds: Double,
        costUSD: Double,
        detailSummary: String,
        recentIssue: String? = nil
    ) {
        self.id = id
        self.agentName = agentName
        self.cliFilter = cliFilter
        self.providerName = providerName
        self.runs = runs
        self.totalTokens = totalTokens
        self.successRate = successRate
        self.avgDurationSeconds = avgDurationSeconds
        self.costUSD = costUSD
        self.detailSummary = detailSummary
        self.recentIssue = recentIssue
    }

    public var health: DashboardSemanticHealth {
        if successRate >= 0.95 { return .healthy }
        if successRate >= 0.85 { return .warning }
        return .critical
    }
}

public struct ModularDashboardDescriptor: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ModularCardKind
    public let title: String
    public let subtitle: String
    public let symbolName: String

    public init(id: String, kind: ModularCardKind, title: String, subtitle: String, symbolName: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
    }
}
#endif
