#if os(macOS)
import Foundation
import AIDashCore

public enum DashboardWorkspaceSection: String, CaseIterable, Sendable, Equatable, Identifiable {
    case overview
    case agentEfficiency
    case actionItems
    case systemAndCosts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .agentEfficiency: return "Agent Efficiency"
        case .actionItems: return "Actionable Items"
        case .systemAndCosts: return "System & CLI Costs"
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
        case .all: return "All"
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
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .critical: return "Exceeded"
        case .neutral: return "Idle"
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

    public init(
        id: String,
        bucketLabel: String,
        category: String,
        cliFilter: DashboardCLIFilter,
        invocations: Int,
        successRate: Double,
        costUSD: Double
    ) {
        self.id = id
        self.bucketLabel = bucketLabel
        self.category = category
        self.cliFilter = cliFilter
        self.invocations = invocations
        self.successRate = successRate
        self.costUSD = costUSD
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
        isAvailable: Bool = true
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
    }

    public var usedFraction: Double {
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
}

public enum DashboardActionSort: String, CaseIterable, Sendable, Equatable, Identifiable {
    case priority = "Priority"
    case source = "Source"
    case title = "Title"

    public var id: String { rawValue }
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
