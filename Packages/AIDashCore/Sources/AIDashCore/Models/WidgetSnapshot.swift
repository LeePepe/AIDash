import Foundation

public struct WidgetBriefingSnapshot: Codable, Sendable, Equatable {
    public struct ActionItem: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let priority: String
        public let category: String?
        public let waitingOn: String?

        public init(
            id: String,
            title: String,
            priority: String = "",
            category: String? = nil,
            waitingOn: String? = nil
        ) {
            self.id = id
            self.title = title
            self.priority = priority
            self.category = category
            self.waitingOn = waitingOn
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, priority, category, waitingOn, waiting_on
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? ""
            category = try container.decodeIfPresent(String.self, forKey: .category)
            waitingOn = try container.decodeIfPresent(String.self, forKeys: [.waitingOn, .waiting_on])
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(priority, forKey: .priority)
            try container.encodeIfPresent(category, forKey: .category)
            try container.encodeIfPresent(waitingOn, forKey: .waitingOn)
        }
    }

    public struct TimeBreakdown: Codable, Sendable, Equatable {
        public let leadTimeMinutesP50: Double
        public let agentMinutes: Double
        public let modelMinutes: Double
        public let ciMinutes: Double
        public let waitMinutes: Double

        public init(
            leadTimeMinutesP50: Double = 0,
            agentMinutes: Double = 0,
            modelMinutes: Double = 0,
            ciMinutes: Double = 0,
            waitMinutes: Double = 0
        ) {
            self.leadTimeMinutesP50 = leadTimeMinutesP50
            self.agentMinutes = agentMinutes
            self.modelMinutes = modelMinutes
            self.ciMinutes = ciMinutes
            self.waitMinutes = waitMinutes
        }

        private enum CodingKeys: String, CodingKey {
            case leadTimeMinutesP50, lead_time_minutes_p50
            case agentMinutes, agent_minutes
            case modelMinutes, model_minutes
            case ciMinutes, ci_minutes
            case waitMinutes, wait_minutes
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            leadTimeMinutesP50 = try container.decodeIfPresent(Double.self, forKeys: [.leadTimeMinutesP50, .lead_time_minutes_p50]) ?? 0
            agentMinutes = try container.decodeIfPresent(Double.self, forKeys: [.agentMinutes, .agent_minutes]) ?? 0
            modelMinutes = try container.decodeIfPresent(Double.self, forKeys: [.modelMinutes, .model_minutes]) ?? 0
            ciMinutes = try container.decodeIfPresent(Double.self, forKeys: [.ciMinutes, .ci_minutes]) ?? 0
            waitMinutes = try container.decodeIfPresent(Double.self, forKeys: [.waitMinutes, .wait_minutes]) ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(leadTimeMinutesP50, forKey: .leadTimeMinutesP50)
            try container.encode(agentMinutes, forKey: .agentMinutes)
            try container.encode(modelMinutes, forKey: .modelMinutes)
            try container.encode(ciMinutes, forKey: .ciMinutes)
            try container.encode(waitMinutes, forKey: .waitMinutes)
        }
    }

    public struct QuotaItem: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let provider: String
        public let remainingPercent: Int

        public init(id: String, provider: String, remainingPercent: Int) {
            self.id = id
            self.provider = provider
            self.remainingPercent = remainingPercent
        }
    }

    public let date: String
    public let needsPersonCount: Int
    public let topActions: [ActionItem]
    public let completedGoalsCount: Int
    public let ciPassRate: Double?
    public let gttNonBlockedRate: Double?
    public let dailySpendUSD: Double?
    public let costPerCompletedTask: Double?
    public let cacheHitPct: Double?
    public let ftrPercent: Double?
    public let timeBreakdown: TimeBreakdown?
    public let quotas: [QuotaItem]

    public init(
        date: String = "",
        needsPersonCount: Int = 0,
        topActions: [ActionItem] = [],
        completedGoalsCount: Int = 0,
        ciPassRate: Double? = nil,
        gttNonBlockedRate: Double? = nil,
        dailySpendUSD: Double? = nil,
        costPerCompletedTask: Double? = nil,
        cacheHitPct: Double? = nil,
        ftrPercent: Double? = nil,
        timeBreakdown: TimeBreakdown? = nil,
        quotas: [QuotaItem] = []
    ) {
        self.date = date
        self.needsPersonCount = needsPersonCount
        self.topActions = topActions
        self.completedGoalsCount = completedGoalsCount
        self.ciPassRate = ciPassRate
        self.gttNonBlockedRate = gttNonBlockedRate
        self.dailySpendUSD = dailySpendUSD
        self.costPerCompletedTask = costPerCompletedTask
        self.cacheHitPct = cacheHitPct
        self.ftrPercent = ftrPercent
        self.timeBreakdown = timeBreakdown
        self.quotas = quotas
    }

    private enum CodingKeys: String, CodingKey {
        case date, needsPersonCount, needs_person_count, topActions, top_actions
        case completedGoalsCount, completed_goals_count
        case ciPassRate, ci_pass_rate, gttNonBlockedRate, gtt_non_blocked_rate
        case dailySpendUSD, daily_spend_usd, costPerCompletedTask, cost_per_completed_task
        case cacheHitPct, cache_hit_pct, ftrPercent, ftr_percent
        case timeBreakdown, time_breakdown, quotas
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKeys: [.date]) ?? ""
        needsPersonCount = try container.decodeIfPresent(Int.self, forKeys: [.needsPersonCount, .needs_person_count]) ?? 0
        completedGoalsCount = try container.decodeIfPresent(Int.self, forKeys: [.completedGoalsCount, .completed_goals_count]) ?? 0
        ciPassRate = try container.decodeIfPresent(Double.self, forKeys: [.ciPassRate, .ci_pass_rate])
        gttNonBlockedRate = try container.decodeIfPresent(Double.self, forKeys: [.gttNonBlockedRate, .gtt_non_blocked_rate])
        dailySpendUSD = try container.decodeIfPresent(Double.self, forKeys: [.dailySpendUSD, .daily_spend_usd])
        costPerCompletedTask = try container.decodeIfPresent(Double.self, forKeys: [.costPerCompletedTask, .cost_per_completed_task])
        cacheHitPct = try container.decodeIfPresent(Double.self, forKeys: [.cacheHitPct, .cache_hit_pct])
        ftrPercent = try container.decodeIfPresent(Double.self, forKeys: [.ftrPercent, .ftr_percent])
        timeBreakdown = try container.decodeIfPresent(TimeBreakdown.self, forKeys: [.timeBreakdown, .time_breakdown])
        quotas = try container.decodeIfPresent([QuotaItem].self, forKeys: [.quotas]) ?? []

        if let actions = try? container.decode([ActionItem].self, forKey: .topActions) {
            topActions = actions
        } else if let actions = try? container.decode([ActionItem].self, forKey: .top_actions) {
            topActions = actions
        } else if let titles = try? container.decode([String].self, forKey: .topActions) {
            topActions = titles.enumerated().map { ActionItem(id: "action-\($0.offset)", title: $0.element) }
        } else if let titles = try? container.decode([String].self, forKey: .top_actions) {
            topActions = titles.enumerated().map { ActionItem(id: "action-\($0.offset)", title: $0.element) }
        } else {
            topActions = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(needsPersonCount, forKey: .needsPersonCount)
        try container.encode(topActions, forKey: .topActions)
        try container.encode(completedGoalsCount, forKey: .completedGoalsCount)
        try container.encodeIfPresent(ciPassRate, forKey: .ciPassRate)
        try container.encodeIfPresent(gttNonBlockedRate, forKey: .gttNonBlockedRate)
        try container.encodeIfPresent(dailySpendUSD, forKey: .dailySpendUSD)
        try container.encodeIfPresent(costPerCompletedTask, forKey: .costPerCompletedTask)
        try container.encodeIfPresent(cacheHitPct, forKey: .cacheHitPct)
        try container.encodeIfPresent(ftrPercent, forKey: .ftrPercent)
        try container.encodeIfPresent(timeBreakdown, forKey: .timeBreakdown)
        try container.encode(quotas, forKey: .quotas)
    }
}

public struct WidgetSystemSnapshot: Codable, Sendable, Equatable {
    public let chipSummary: String
    public let cpuUsage: Double
    public let gpuUsage: Double
    public let vramSummary: String
    public let memoryUsage: Double
    public let memorySummary: String
    public let topCPUProcess: String?
    public let topMemoryProcess: String?
    public let powerThermalSummary: String
    public let magpieUp: Bool
    public let ravenUp: Bool
    public let falconUp: Bool
    public let ttftSummary: String?

    public init(
        chipSummary: String = "",
        cpuUsage: Double = 0,
        gpuUsage: Double = 0,
        vramSummary: String = "",
        memoryUsage: Double = 0,
        memorySummary: String = "",
        topCPUProcess: String? = nil,
        topMemoryProcess: String? = nil,
        powerThermalSummary: String = "",
        magpieUp: Bool = false,
        ravenUp: Bool = false,
        falconUp: Bool = false,
        ttftSummary: String? = nil
    ) {
        self.chipSummary = chipSummary
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.vramSummary = vramSummary
        self.memoryUsage = memoryUsage
        self.memorySummary = memorySummary
        self.topCPUProcess = topCPUProcess
        self.topMemoryProcess = topMemoryProcess
        self.powerThermalSummary = powerThermalSummary
        self.magpieUp = magpieUp
        self.ravenUp = ravenUp
        self.falconUp = falconUp
        self.ttftSummary = ttftSummary
    }
}

public enum WidgetSnapshotStore {
    public static func loadBriefingSnapshot(from fileURL: URL) throws -> WidgetBriefingSnapshot {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(WidgetBriefingSnapshot.self, from: data)
    }

    public static func saveBriefingSnapshot(
        _ snapshot: WidgetBriefingSnapshot,
        to fileURL: URL
    ) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private extension KeyedDecodingContainer {
    func decodeIfPresent<T: Decodable>(
        _ type: T.Type,
        forKeys keys: [Key]
    ) throws -> T? {
        for key in keys {
            if let value = try decodeIfPresent(type, forKey: key) {
                return value
            }
        }
        return nil
    }
}
