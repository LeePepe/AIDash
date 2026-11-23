#if os(macOS)
// swiftlint:disable file_length
import Darwin
import Foundation
import SQLite3
import AIDashCore

public struct AgentRoleEfficiencyRow: Codable, Sendable, Equatable, Identifiable {
    public let roleKey: String
    public let roleLabel: String
    public let roleLabelEn: String?
    public let runsCount: Int
    public let goalsCount: Int
    public let tasksCount: Int
    public let r1Count: Int
    public let r2Count: Int
    public let r3PlusCount: Int
    public let r1PassRate: Double?
    public let medianDurationSec: Double?
    public let p90DurationSec: Double?
    public let estimatedTokens: UInt64
    public let tokenSharePct: Double

    public var id: String { roleKey }

    enum CodingKeys: String, CodingKey {
        case roleKey = "role_key"
        case roleLabel = "role_label"
        case roleLabelEn = "role_label_en"
        case runsCount = "runs_count"
        case goalsCount = "goals_count"
        case tasksCount = "tasks_count"
        case r1Count = "r1_count"
        case r2Count = "r2_count"
        case r3PlusCount = "r3_plus_count"
        case r1PassRate = "r1_pass_rate"
        case medianDurationSec = "median_duration_sec"
        case p90DurationSec = "p90_duration_sec"
        case estimatedTokens = "estimated_tokens"
        case tokenSharePct = "token_share_pct"
    }

    public init(
        roleKey: String,
        roleLabel: String,
        roleLabelEn: String? = nil,
        runsCount: Int = 0,
        goalsCount: Int = 0,
        tasksCount: Int = 0,
        r1Count: Int = 0,
        r2Count: Int = 0,
        r3PlusCount: Int = 0,
        r1PassRate: Double? = nil,
        medianDurationSec: Double? = nil,
        p90DurationSec: Double? = nil,
        estimatedTokens: UInt64 = 0,
        tokenSharePct: Double = 0
    ) {
        self.roleKey = roleKey
        self.roleLabel = roleLabel
        self.roleLabelEn = roleLabelEn
        self.runsCount = runsCount
        self.goalsCount = goalsCount
        self.tasksCount = tasksCount
        self.r1Count = r1Count
        self.r2Count = r2Count
        self.r3PlusCount = r3PlusCount
        self.r1PassRate = r1PassRate
        self.medianDurationSec = medianDurationSec
        self.p90DurationSec = p90DurationSec
        self.estimatedTokens = estimatedTokens
        self.tokenSharePct = tokenSharePct
    }
}

public struct AgentDailyEfficiencyPoint: Codable, Sendable, Equatable, Identifiable {
    public let day: String
    public let goalsCompleted: Int
    public let tasksCompleted: Int
    public let r1Count: Int
    public let r2Count: Int
    public let r3PlusCount: Int
    public let r1PassRate: Double?
    public let medianDurationSec: Double?
    public let p90DurationSec: Double?
    public let blockedEvents: Int
    public let steeringTokens: UInt64
    public let codingTokens: UInt64
    public let totalTokens: UInt64

    public var id: String { day }

    public var shortDayLabel: String {
        day.count >= 10 ? String(day.suffix(5)) : day
    }

    enum CodingKeys: String, CodingKey {
        case day
        case cstDay = "cst_day"
        case goalsCompleted = "goals_completed"
        case tasksCompleted = "tasks_completed"
        case r1Count = "r1_count"
        case r2Count = "r2_count"
        case r3PlusCount = "r3_plus_count"
        case r1PassRate = "r1_pass_rate"
        case medianDurationSec = "median_duration_sec"
        case p90DurationSec = "p90_duration_sec"
        case blockedEvents = "blocked_events"
        case steeringTokens = "steering_tokens"
        case codingTokens = "coding_tokens"
        case totalTokens = "total_tokens"
    }

    public init(
        day: String,
        goalsCompleted: Int = 0,
        tasksCompleted: Int = 0,
        r1Count: Int = 0,
        r2Count: Int = 0,
        r3PlusCount: Int = 0,
        r1PassRate: Double? = nil,
        medianDurationSec: Double? = nil,
        p90DurationSec: Double? = nil,
        blockedEvents: Int = 0,
        steeringTokens: UInt64 = 0,
        codingTokens: UInt64 = 0,
        totalTokens: UInt64 = 0
    ) {
        self.day = day
        self.goalsCompleted = goalsCompleted
        self.tasksCompleted = tasksCompleted
        self.r1Count = r1Count
        self.r2Count = r2Count
        self.r3PlusCount = r3PlusCount
        self.r1PassRate = r1PassRate
        self.medianDurationSec = medianDurationSec
        self.p90DurationSec = p90DurationSec
        self.blockedEvents = blockedEvents
        self.steeringTokens = steeringTokens
        self.codingTokens = codingTokens
        self.totalTokens = totalTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let resolvedDay = (try? container.decode(String.self, forKey: .day))
            ?? (try? container.decode(String.self, forKey: .cstDay))
            ?? ""
        self.day = resolvedDay
        self.goalsCompleted = (try? container.decode(Int.self, forKey: .goalsCompleted)) ?? 0
        self.tasksCompleted = (try? container.decode(Int.self, forKey: .tasksCompleted)) ?? 0
        self.r1Count = (try? container.decode(Int.self, forKey: .r1Count)) ?? 0
        self.r2Count = (try? container.decode(Int.self, forKey: .r2Count)) ?? 0
        self.r3PlusCount = (try? container.decode(Int.self, forKey: .r3PlusCount)) ?? 0
        self.r1PassRate = try? container.decodeIfPresent(Double.self, forKey: .r1PassRate)
        self.medianDurationSec = try? container.decodeIfPresent(Double.self, forKey: .medianDurationSec)
        self.p90DurationSec = try? container.decodeIfPresent(Double.self, forKey: .p90DurationSec)
        self.blockedEvents = (try? container.decode(Int.self, forKey: .blockedEvents)) ?? 0
        self.steeringTokens = (try? container.decode(UInt64.self, forKey: .steeringTokens)) ?? 0
        self.codingTokens = (try? container.decode(UInt64.self, forKey: .codingTokens)) ?? 0
        self.totalTokens = (try? container.decode(UInt64.self, forKey: .totalTokens)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(goalsCompleted, forKey: .goalsCompleted)
        try container.encode(tasksCompleted, forKey: .tasksCompleted)
        try container.encode(r1Count, forKey: .r1Count)
        try container.encode(r2Count, forKey: .r2Count)
        try container.encode(r3PlusCount, forKey: .r3PlusCount)
        try container.encodeIfPresent(r1PassRate, forKey: .r1PassRate)
        try container.encodeIfPresent(medianDurationSec, forKey: .medianDurationSec)
        try container.encodeIfPresent(p90DurationSec, forKey: .p90DurationSec)
        try container.encode(blockedEvents, forKey: .blockedEvents)
        try container.encode(steeringTokens, forKey: .steeringTokens)
        try container.encode(codingTokens, forKey: .codingTokens)
        try container.encode(totalTokens, forKey: .totalTokens)
    }
}

public struct AgentRoundDistributionSummary: Codable, Sendable, Equatable {
    public let r1Count: Int
    public let r2Count: Int
    public let r3PlusCount: Int
    public let evaluatedTasks: Int
    public let r1PassRate: Double?
    public let medianDurationSec: Double?
    public let p90DurationSec: Double?
    public let steeringTokenShare: Double?
    public let ttftP90Sec: Double?
    public let cacheHitRate: Double?

    enum CodingKeys: String, CodingKey {
        case r1Count = "r1_count"
        case r2Count = "r2_count"
        case r3PlusCount = "r3_plus_count"
        case evaluatedTasks = "evaluated_tasks"
        case r1PassRate = "r1_pass_rate"
        case medianDurationSec = "median_duration_sec"
        case p90DurationSec = "p90_duration_sec"
        case steeringTokenShare = "steering_token_share"
        case ttftP90Sec = "ttft_p90_sec"
        case cacheHitRate = "cache_hit_rate"
    }

    public init(
        r1Count: Int = 0,
        r2Count: Int = 0,
        r3PlusCount: Int = 0,
        evaluatedTasks: Int = 0,
        r1PassRate: Double? = nil,
        medianDurationSec: Double? = nil,
        p90DurationSec: Double? = nil,
        steeringTokenShare: Double? = nil,
        ttftP90Sec: Double? = nil,
        cacheHitRate: Double? = nil
    ) {
        self.r1Count = r1Count
        self.r2Count = r2Count
        self.r3PlusCount = r3PlusCount
        self.evaluatedTasks = evaluatedTasks
        self.r1PassRate = r1PassRate
        self.medianDurationSec = medianDurationSec
        self.p90DurationSec = p90DurationSec
        self.steeringTokenShare = steeringTokenShare
        self.ttftP90Sec = ttftP90Sec
        self.cacheHitRate = cacheHitRate
    }
}

public struct AgentEfficiencyWorkbenchSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let windowCST: String
    public let windowStart: String?
    public let windowEnd: String?
    public let sourceAsOf: String?
    public let sampleSize: Int
    public let coverageStatus: String
    public let roles: [AgentRoleEfficiencyRow]
    public let roundSummary: AgentRoundDistributionSummary
    public let dailySeries: [AgentDailyEfficiencyPoint]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case windowCST = "window_cst"
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case sourceAsOf = "source_as_of"
        case sampleSize = "sample_size"
        case coverageStatus = "coverage_status"
        case roles
        case roleBreakdown = "role_breakdown"
        case roundSummary = "round_summary"
        case roundDistribution = "round_distribution"
        case dailySeries = "daily_series"
        case dailyTrend = "daily_trend"
    }

    public init(
        schemaVersion: Int = 1,
        windowCST: String = "14d",
        windowStart: String? = nil,
        windowEnd: String? = nil,
        sourceAsOf: String? = nil,
        sampleSize: Int = 0,
        coverageStatus: String = "unknown",
        roles: [AgentRoleEfficiencyRow] = [],
        roundSummary: AgentRoundDistributionSummary = AgentRoundDistributionSummary(),
        dailySeries: [AgentDailyEfficiencyPoint] = []
    ) {
        self.schemaVersion = schemaVersion
        self.windowCST = windowCST
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.sourceAsOf = sourceAsOf
        self.sampleSize = sampleSize
        self.coverageStatus = coverageStatus
        self.roles = roles
        self.roundSummary = roundSummary
        self.dailySeries = dailySeries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
        self.windowCST = (try? container.decode(String.self, forKey: .windowCST)) ?? "14d"
        self.windowStart = try? container.decodeIfPresent(String.self, forKey: .windowStart)
        self.windowEnd = try? container.decodeIfPresent(String.self, forKey: .windowEnd)
        self.sourceAsOf = try? container.decodeIfPresent(String.self, forKey: .sourceAsOf)
        self.sampleSize = (try? container.decode(Int.self, forKey: .sampleSize)) ?? 0
        self.coverageStatus = (try? container.decode(String.self, forKey: .coverageStatus)) ?? "unknown"
        self.roles = (try? container.decode([AgentRoleEfficiencyRow].self, forKey: .roles))
            ?? (try? container.decode([AgentRoleEfficiencyRow].self, forKey: .roleBreakdown))
            ?? []
        self.roundSummary = (try? container.decode(AgentRoundDistributionSummary.self, forKey: .roundSummary))
            ?? (try? container.decode(AgentRoundDistributionSummary.self, forKey: .roundDistribution))
            ?? AgentRoundDistributionSummary()
        self.dailySeries = (try? container.decode([AgentDailyEfficiencyPoint].self, forKey: .dailySeries))
            ?? (try? container.decode([AgentDailyEfficiencyPoint].self, forKey: .dailyTrend))
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(windowCST, forKey: .windowCST)
        try container.encodeIfPresent(windowStart, forKey: .windowStart)
        try container.encodeIfPresent(windowEnd, forKey: .windowEnd)
        try container.encodeIfPresent(sourceAsOf, forKey: .sourceAsOf)
        try container.encode(sampleSize, forKey: .sampleSize)
        try container.encode(coverageStatus, forKey: .coverageStatus)
        try container.encode(roles, forKey: .roles)
        try container.encode(roundSummary, forKey: .roundSummary)
        try container.encode(dailySeries, forKey: .dailySeries)
    }
}

public struct RealQuotaSnapshot: Sendable, Equatable {
    public let claudeSevenDayUsedFraction: Double?
    public let claudeFiveHourUsedFraction: Double?
    public let cursorWeeklyUsedFraction: Double?
    public let grokSevenDayUsedFraction: Double?
    public let kimiSevenDayUsedFraction: Double?
    public let kimiFiveHourUsedFraction: Double?
    public let claudeResetText: String?
    public let cursorResetText: String?
    public let grokResetText: String?
    public let kimiResetText: String?
    public let claudeReadAtDate: Date?
    public let grokReadAtDate: Date?

    public init(
        claudeSevenDayUsedFraction: Double? = nil,
        claudeFiveHourUsedFraction: Double? = nil,
        cursorWeeklyUsedFraction: Double? = nil,
        grokSevenDayUsedFraction: Double? = nil,
        kimiSevenDayUsedFraction: Double? = nil,
        kimiFiveHourUsedFraction: Double? = nil,
        claudeResetText: String? = nil,
        cursorResetText: String? = nil,
        grokResetText: String? = nil,
        kimiResetText: String? = nil,
        claudeReadAtDate: Date? = nil,
        grokReadAtDate: Date? = nil
    ) {
        self.claudeSevenDayUsedFraction = claudeSevenDayUsedFraction
        self.claudeFiveHourUsedFraction = claudeFiveHourUsedFraction
        self.cursorWeeklyUsedFraction = cursorWeeklyUsedFraction
        self.grokSevenDayUsedFraction = grokSevenDayUsedFraction
        self.kimiSevenDayUsedFraction = kimiSevenDayUsedFraction
        self.kimiFiveHourUsedFraction = kimiFiveHourUsedFraction
        self.claudeResetText = claudeResetText
        self.cursorResetText = cursorResetText
        self.grokResetText = grokResetText
        self.kimiResetText = kimiResetText
        self.claudeReadAtDate = claudeReadAtDate
        self.grokReadAtDate = grokReadAtDate
    }
}

@MainActor
// swiftlint:disable:next type_body_length
public enum LiveDashboardTelemetryReader {
    public typealias TopicMapDataReader = (URL) -> Data?
    public typealias HerdrCommandRunner = ([String]) -> String?

    private struct TopicMapEnvelope: Decodable {
        struct Group: Decodable {
            let group: String
            let topics: [Topic]
        }
        struct Topic: Decodable {
            let topicID: String
            let title: String
            let group: String?
            let targetRepo: String
            let cwd: String
            let keywords: [String]
            let aliases: [String]

            // swiftlint:disable:next nesting
            enum CodingKeys: String, CodingKey {
                case topicID = "topic_id"
                case title, group
                case targetRepo = "target_repo"
                case cwd, keywords, aliases
            }
        }
        let groups: [Group]
    }

    public struct HerdrWorkspaceRecord: Codable, Sendable, Equatable {
        public let workspaceID: String
        public let label: String
        public let activeTabID: String?
        public let paneCount: Int

        public init(workspaceID: String, label: String, activeTabID: String? = nil, paneCount: Int = 1) {
            self.workspaceID = workspaceID
            self.label = label
            self.activeTabID = activeTabID
            self.paneCount = paneCount
        }
    }

    public struct HerdrAgentRecord: Codable, Sendable, Equatable {
        public let workspaceID: String
        public let paneID: String
        public let cwd: String?
        public let foregroundCwd: String?
        public let terminalTitle: String?
        public let name: String?

        public init(workspaceID: String, paneID: String, cwd: String? = nil, foregroundCwd: String? = nil, terminalTitle: String? = nil, name: String? = nil) {
            self.workspaceID = workspaceID
            self.paneID = paneID
            self.cwd = cwd
            self.foregroundCwd = foregroundCwd
            self.terminalTitle = terminalTitle
            self.name = name
        }
    }

    public struct HerdrM2SessionSnapshot: Codable, Sendable, Equatable {
        public let workspaces: [HerdrWorkspaceRecord]
        public let agents: [HerdrAgentRecord]

        public init(workspaces: [HerdrWorkspaceRecord] = [], agents: [HerdrAgentRecord] = []) {
            self.workspaces = workspaces
            self.agents = agents
        }

        @MainActor
        public func bindings(for topics: [DashboardTopic]) -> [String: DashboardM2SessionBinding] {
            var result: [String: DashboardM2SessionBinding] = [:]
            for topic in topics {
                let binding = LiveDashboardTelemetryReader.bind(topic: topic, workspaces: workspaces, agents: agents)
                result[topic.id] = binding
            }
            return result
        }
    }

    public static var isLiveEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            && ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil
    }

    public static func loadTopicCatalog(
        homeURL: URL? = nil,
        dataReader: TopicMapDataReader? = nil
    ) -> [DashboardTopic] {
        let read = dataReader ?? { try? Data(contentsOf: $0) }
        let home = homeURL ?? LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
        let candidates = [
            URL(fileURLWithPath: "/Users/tianpli/.agents/skills/personal-m2-assistant/references/m2-domain-map.json"),
            home.appendingPathComponent("Development/user-skills/skills/personal-m2-assistant/references/m2-domain-map.json"),
            URL(fileURLWithPath: "/Users/tianpli/Development/user-skills/skills/personal-m2-assistant/references/m2-domain-map.json")
        ]
        let decoder = JSONDecoder()
        for url in candidates {
            guard let data = read(url), let envelope = try? decoder.decode(TopicMapEnvelope.self, from: data) else { continue }
            let topics = envelope.groups.flatMap { group in
                group.topics.map { raw in
                    DashboardTopic(
                        id: raw.topicID, title: raw.title, group: raw.group ?? group.group,
                        targetRepo: raw.targetRepo, cwd: raw.cwd, keywords: raw.keywords, aliases: raw.aliases
                    )
                }
            }
            if !topics.isEmpty { return topics }
        }
        return DashboardTopicCatalog.builtInTopics
    }

    public static func productionHerdrCommandRunner(_ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/herdr") else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/herdr")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }

    public static func loadHerdrM2SessionSnapshot(
        commandRunner: HerdrCommandRunner? = nil
    ) -> HerdrM2SessionSnapshot {
        guard isLiveEnvironment || commandRunner != nil else { return HerdrM2SessionSnapshot() }
        let run = commandRunner ?? productionHerdrCommandRunner
        guard let workspaceOutput = run(["workspace", "list"]),
              let agentOutput = run(["agent", "list"]) else { return HerdrM2SessionSnapshot() }
        return parseHerdrM2SessionSnapshot(workspaceOutput: workspaceOutput, agentOutput: agentOutput)
    }

    public static func parseHerdrM2SessionSnapshot(workspaceOutput: String, agentOutput: String) -> HerdrM2SessionSnapshot {
        func object(from output: String) -> [String: Any]? {
            guard let data = output.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        let workspaceRoot = object(from: workspaceOutput)?["result"] as? [String: Any]
        let workspaceRows = (workspaceRoot?["workspaces"] as? [[String: Any]] ?? []).compactMap { row -> HerdrWorkspaceRecord? in
            guard let id = (row["workspace_id"] as? String) ?? (row["id"] as? String), !id.isEmpty,
                  let label = row["label"] as? String else { return nil }
            return HerdrWorkspaceRecord(workspaceID: id, label: label, activeTabID: row["active_tab_id"] as? String, paneCount: row["pane_count"] as? Int ?? 1)
        }
        let agentRoot = object(from: agentOutput)?["result"] as? [String: Any]
        let agentRows = (agentRoot?["agents"] as? [[String: Any]] ?? []).compactMap { row -> HerdrAgentRecord? in
            guard let workspaceID = row["workspace_id"] as? String,
                  let paneID = row["pane_id"] as? String else { return nil }
            return HerdrAgentRecord(
                workspaceID: workspaceID, paneID: paneID, cwd: row["cwd"] as? String,
                foregroundCwd: row["foreground_cwd"] as? String,
                terminalTitle: (row["terminal_title_stripped"] as? String) ?? (row["terminal_title"] as? String),
                name: row["name"] as? String
            )
        }
        return HerdrM2SessionSnapshot(workspaces: workspaceRows, agents: agentRows)
    }

    nonisolated private static func bind(topic: DashboardTopic, workspaces: [HerdrWorkspaceRecord], agents: [HerdrAgentRecord]) -> DashboardM2SessionBinding {
        let knownWorkspaceIDs: [String: [String]] = [
            "sapphire-china-bugs": ["w1"], "sapphire-smartbanner": ["w10"], "sapphire-notification": ["w25"],
            "flightbook-status": ["w27"], "aidash-aidata": ["w55"], "info-teams": ["w5N"], "info-email": ["w5M"],
            "skills-workflow": ["w5A", "w5K"]
        ]
        let knownIDs = knownWorkspaceIDs[topic.id] ?? []
        let knownWorkspace = workspaces.first { knownIDs.contains($0.workspaceID) }
        let candidates = workspaces.filter { workspace in
            let text = [workspace.label, workspace.workspaceID].joined(separator: " ").lowercased()
            let agentText = agents.filter { $0.workspaceID == workspace.workspaceID }
                .flatMap { [$0.cwd ?? "", $0.foregroundCwd ?? "", $0.terminalTitle ?? "", $0.name ?? ""] }
                .joined(separator: " ").lowercased()
            return text.contains(topic.id.lowercased()) || agentText.contains(topic.id.lowercased())
                || topic.keywords.contains { text.localizedCaseInsensitiveContains($0) || agentText.localizedCaseInsensitiveContains($0) }
                || topic.aliases.contains { text.localizedCaseInsensitiveContains($0) || agentText.localizedCaseInsensitiveContains($0) }
                || text.localizedCaseInsensitiveContains(topic.title)
        }
        guard let workspace = knownWorkspace ?? candidates.sorted(by: { $0.workspaceID < $1.workspaceID }).first else {
            return DashboardM2SessionBinding(topicID: topic.id, targetRepo: topic.targetRepo)
        }
        let agent = agents.first { $0.workspaceID == workspace.workspaceID && $0.paneID.hasSuffix(":p1") }
            ?? agents.first { $0.workspaceID == workspace.workspaceID }
        return DashboardM2SessionBinding(
            topicID: topic.id, paneID: agent?.paneID ?? "\(workspace.workspaceID):p1",
            workspaceID: workspace.workspaceID, workspaceLabel: workspace.label, targetRepo: topic.targetRepo
        )
    }

    public static func loadLiveDataset(
        forDate dateString: String,
        fallbackUsage: CLITokenUsageSnapshot
    ) -> (entries: [CLICostQuotaEntry], rankings: [AgentRankingRow], trends: [TrendDataPoint])? {
        guard isLiveEnvironment else { return nil }
        let home = LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
        return loadDataset(forDate: dateString, homeURL: home, fallbackUsage: fallbackUsage)
    }

    public typealias ScheduledPulseLaunchctl = @MainActor ([String]) -> LaunchdAgentInstaller.LaunchctlResult

    public static let productionScheduledPulseLaunchctl: ScheduledPulseLaunchctl = { args in
        LaunchdAgentInstaller.runLaunchctl(args)
    }

    public static func loadScheduledPulseSnapshot(
        now: Date = Date(),
        statuses: [ScheduledJobStatus]? = nil,
        launchctl: ScheduledPulseLaunchctl? = nil,
        registry: [ScheduledJobDefinition]? = nil
    ) -> ScheduledPulseSnapshot {
        if let statuses {
            return ScheduledPulseSnapshot(capturedAt: now, jobs: statuses)
        }
        guard isLiveEnvironment || launchctl != nil else {
            return ScheduledPulseSnapshot.defaultSnapshot(now: now)
        }
        let effect = launchctl ?? productionScheduledPulseLaunchctl
        let domain = "gui/\(getuid())"
        let jobs = (registry ?? ScheduledPulseRegistry.jobs).map { definition in
            guard definition.isLive else {
                return ScheduledJobStatus(definition: definition, health: .reserved)
            }
            let result = effect(["print", "\(domain)/\(definition.launchAgentLabel)"])
            return scheduledJobStatus(definition: definition, result: result)
        }
        return ScheduledPulseSnapshot(capturedAt: now, jobs: jobs)
    }

    private static func scheduledJobStatus(
        definition: ScheduledJobDefinition,
        result: LaunchdAgentInstaller.LaunchctlResult
    ) -> ScheduledJobStatus {
        let lastRun = parseLaunchdDate(from: result.stdout, keys: ["last run", "last exit time"])
        let lastTick = parseLaunchdDate(from: result.stdout, keys: ["last tick"]) ?? lastRun
        let exitCode = parseLaunchdExitCode(from: result.stdout)
        let runningPID = parseLaunchdInteger(from: result.stdout, key: "pid")
        guard result.succeeded else {
            let isAbsent = result.launchError == nil && (result.terminationStatus == 3 || result.terminationStatus == 113)
            return ScheduledJobStatus(
                definition: definition,
                health: isAbsent ? .expectedOnButIdle : .critical,
                isLoaded: false,
                runningPID: runningPID,
                lastExitCode: exitCode,
                lastRun: lastRun,
                lastTick: lastTick,
                lastError: isAbsent ? nil : result.diagnosticSummary
            )
        }
        let health: ScheduledPulseHealth = exitCode.map { $0 == 0 ? .healthy : .critical } ?? .healthy
        return ScheduledJobStatus(
            definition: definition,
            health: health,
            isLoaded: true,
            runningPID: runningPID,
            lastExitCode: exitCode,
            lastRun: lastRun,
            lastTick: lastTick,
            lastError: health == .healthy ? nil : "last exit code \(exitCode ?? -1)"
        )
    }

    private static func parseLaunchdExitCode(from output: String) -> Int32? {
        parseLaunchdInteger(from: output, key: "last exit code")
    }

    private static func parseLaunchdInteger(from output: String, key: String) -> Int32? {
        for line in output.split(separator: "\n") {
            guard line.lowercased().contains(key) else { continue }
            let number = line.split(whereSeparator: { !$0.isNumber && $0 != "-" }).last
            if let number, let value = Int32(String(number)) { return value }
        }
        return nil
    }

    private static func parseLaunchdDate(from output: String, keys: [String]) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        for line in output.split(separator: "\n") {
            let lower = line.lowercased()
            guard keys.contains(where: { lower.contains($0) }),
                  let value = line.split(separator: "=", maxSplits: 1).last else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = fractional.date(from: trimmed) ?? standard.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    public typealias ScheduledJobFileReader = @MainActor (URL) -> Data?

    public static func isCloudDocsPath(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/Mobile Documents/com~apple~CloudDocs")
            || path.contains("/com~apple~CloudDocs")
    }

    public static let productionScheduledJobFileReader: ScheduledJobFileReader = { url in
        guard !isCloudDocsPath(url) else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func iCloudSyncRootURL(homeURL: URL) -> URL {
        if let mirrorOverride = ProcessInfo.processInfo.environment["AIDASH_ICLOUD_MIRROR_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !mirrorOverride.isEmpty {
            return URL(fileURLWithPath: mirrorOverride, isDirectory: true)
        }
        return homeURL.appendingPathComponent(".aidash/icloud-mirror", isDirectory: true)
    }

    public static func selectFresherArtifactData(
        localURL: URL,
        iCloudURL: URL,
        fileReader: ScheduledJobFileReader? = nil
    ) -> (data: Data, url: URL)? {
        let read = fileReader ?? productionScheduledJobFileReader
        let local = read(localURL)
        let cloud = read(iCloudURL)
        switch (local, cloud) {
        case (nil, nil): return nil
        case (let data?, nil): return (data, localURL)
        case (nil, let data?): return (data, iCloudURL)
        case (let localData?, let cloudData?):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]
            func timestamp(_ data: Data) -> Date? {
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                for key in ["generated_at", "updatedAt", "lastRunAt", "source_as_of"] {
                    guard let value = object[key] as? String else { continue }
                    if let date = formatter.date(from: value) ?? standardFormatter.date(from: value) { return date }
                }
                return nil
            }
            if let localDate = timestamp(localData), let cloudDate = timestamp(cloudData), localDate != cloudDate {
                return cloudDate > localDate ? (cloudData, iCloudURL) : (localData, localURL)
            }
            let localMTime = isCloudDocsPath(localURL)
                ? nil
                : (try? localURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            let cloudMTime = isCloudDocsPath(iCloudURL)
                ? nil
                : (try? iCloudURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            if let localMTime, let cloudMTime, localMTime != cloudMTime {
                return cloudMTime > localMTime ? (cloudData, iCloudURL) : (localData, localURL)
            }
            return (localData, localURL)
        }
    }

    public static func loadScheduledJobFrameworkSnapshot(
        now: Date = Date(),
        fileReader: ScheduledJobFileReader? = nil,
        homeURL: URL? = nil,
        acknowledgedActionIDs: Set<String> = [],
        launchctl: ScheduledPulseLaunchctl? = nil,
        registry: [ScheduledJobDefinition]? = nil
    ) -> ScheduledJobFrameworkSnapshot {
        guard isLiveEnvironment || fileReader != nil || homeURL != nil || launchctl != nil else {
            return ScheduledJobFrameworkSnapshot(capturedAt: now, entries: [])
        }
        let resolvedHome = homeURL ?? LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
        let read = fileReader ?? productionScheduledJobFileReader
        let launchdStatuses: [ScheduledPulseJobID: ScheduledJobStatus]
        if isLiveEnvironment || launchctl != nil {
            let pulseSnapshot = loadScheduledPulseSnapshot(now: now, launchctl: launchctl, registry: registry)
            launchdStatuses = Dictionary(uniqueKeysWithValues: pulseSnapshot.jobs.map { ($0.id, $0) })
        } else {
            launchdStatuses = [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date string: \(string)"
            )
        }
        let root = resolvedHome.appendingPathComponent("Library/Application Support/AIDash/jobs", isDirectory: true)
        let iCloudRoot = iCloudSyncRootURL(homeURL: resolvedHome).appendingPathComponent("jobs", isDirectory: true)
        let entries = (registry ?? ScheduledPulseRegistry.jobs).map { definition in
            let directory = root.appendingPathComponent(definition.id.rawValue, isDirectory: true)
            let iCloudDirectory = iCloudRoot.appendingPathComponent(definition.id.rawValue, isDirectory: true)
            let state = readState(
                from: directory.appendingPathComponent("state.json"),
                iCloudURL: iCloudDirectory.appendingPathComponent("state.json"),
                definition: definition,
                decoder: decoder,
                read: read
            )
            let actions = readActions(
                from: directory.appendingPathComponent("actions.jsonl"),
                iCloudURL: iCloudDirectory.appendingPathComponent("actions.jsonl"),
                definition: definition,
                decoder: decoder,
                read: read
            ).filter { !$0.isAcknowledged(in: acknowledgedActionIDs) }
            return ScheduledJobFrameworkEntry(
                definition: definition,
                state: state,
                actions: actions,
                launchdStatus: launchdStatuses[definition.id]
            )
        }
        return ScheduledJobFrameworkSnapshot(capturedAt: now, entries: entries)
    }

    private static func readState(
        from url: URL,
        iCloudURL: URL,
        definition: ScheduledJobDefinition,
        decoder: JSONDecoder,
        read: @escaping ScheduledJobFileReader
    ) -> ScheduledJobState? {
        guard let data = selectFresherArtifactData(localURL: url, iCloudURL: iCloudURL, fileReader: read)?.data,
              let state = try? decoder.decode(ScheduledJobState.self, from: data),
              state.id == definition.id else { return nil }
        return state
    }

    private static func readActions(
        from url: URL,
        iCloudURL: URL,
        definition: ScheduledJobDefinition,
        decoder: JSONDecoder,
        read: @escaping ScheduledJobFileReader
    ) -> [ScheduledJobAction] {
        guard let data = selectFresherArtifactData(localURL: url, iCloudURL: iCloudURL, fileReader: read)?.data,
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let lineData = Data(line.utf8)
            if let wireAction = try? decoder.decode(JobActionsAction.self, from: lineData),
               wireAction.jobID == definition.id.rawValue {
                if definition.id == .aidataDigest, !isPersonalJobAction(wireAction) { return nil }
                let controls = wireAction.controls.compactMap { control -> ScheduledJobActionControl? in
                    guard let kind = ScheduledJobActionControlKind(rawValue: control.kind.rawValue) else { return nil }
                    return ScheduledJobActionControl(
                        id: control.id,
                        kind: kind,
                        title: control.title,
                        options: control.options,
                        maxLength: control.maxLength
                    )
                }
                guard !controls.isEmpty else { return nil }
                return ScheduledJobAction(
                    id: wireAction.id,
                    jobID: definition.id,
                    createdAt: wireAction.createdAt,
                    title: wireAction.title,
                    descriptionMd: wireAction.descriptionMd,
                    controls: controls,
                    revision: wireAction.revision
                )
            }
            // Digest actions must pass the typed personal contract. Its legacy parser
            // must not reopen an excluded/malformed work record after decoding fails.
            if definition.id == .aidataDigest { return nil }
            if let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let rawControls = object["controls"] as? [[String: Any]],
                  !rawControls.isEmpty,
                  let id = object["id"] as? String,
                  let jobRaw = object["jobID"] as? String,
                  let jobID = ScheduledPulseJobID(rawValue: jobRaw),
                  jobID == definition.id,
                  let title = object["title"] as? String,
                  let description = object["descriptionMd"] as? String {
                let controls = rawControls.compactMap { item -> ScheduledJobActionControl? in
                    guard let controlID = item["id"] as? String,
                          let kindRaw = item["kind"] as? String,
                          let kind = ScheduledJobActionControlKind(rawValue: kindRaw),
                          let controlTitle = item["title"] as? String else { return nil }
                    return ScheduledJobActionControl(id: controlID, kind: kind, title: controlTitle, options: item["options"] as? [String] ?? [], maxLength: item["maxLength"] as? Int)
                }
                return ScheduledJobAction(id: id, jobID: jobID, title: title, descriptionMd: description, controls: controls)
            }
            if let action = try? decoder.decode(ScheduledJobAction.self, from: lineData), action.jobID == definition.id {
                return action
            }
            guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = object["id"] as? String,
                  let jobRaw = object["jobID"] as? String,
                  let jobID = ScheduledPulseJobID(rawValue: jobRaw),
                  jobID == definition.id,
                  let title = object["title"] as? String,
                  let description = object["descriptionMd"] as? String else { return nil }
            let controls = (object["controls"] as? [[String: Any]] ?? []).compactMap { item -> ScheduledJobActionControl? in
                guard let controlID = item["id"] as? String,
                      let kindRaw = item["kind"] as? String,
                      let kind = ScheduledJobActionControlKind(rawValue: kindRaw),
                      let title = item["title"] as? String else { return nil }
                return ScheduledJobActionControl(
                    id: controlID,
                    kind: kind,
                    title: title,
                    options: item["options"] as? [String] ?? [],
                    maxLength: item["maxLength"] as? Int
                )
            }
            return ScheduledJobAction(id: id, jobID: jobID, title: title, descriptionMd: description, controls: controls)
        }
    }

    public static func loadDataset(
        forDate dateString: String,
        homeURL: URL,
        fallbackUsage: CLITokenUsageSnapshot,
        includeSystemBinaries: Bool = isLiveEnvironment,
        now: Date = Date()
    ) -> (entries: [CLICostQuotaEntry], rankings: [AgentRankingRow], trends: [TrendDataPoint])? {
        let ravenURL = homeURL.appendingPathComponent("Library/Application Support/raven/raven.db")
        let copilotURL = homeURL.appendingPathComponent(".copilot/session-store.db")
        let warehouseURL = homeURL.appendingPathComponent("Development/AIDash/aidata/L3_merge/warehouse.db")
        let quotasURL = homeURL.appendingPathComponent(".config/magpie/quotas.json")
        let claudeQuotaURL = homeURL.appendingPathComponent(".config/claude/gtt-weekly-remaining-pct.json")
        let kimiUsagesURL = homeURL.appendingPathComponent(".kimi-code/usages.json")

        let quotas = readQuotas(
            magpieQuotasURL: quotasURL,
            claudeFallbackURL: claudeQuotaURL,
            kimiUsagesURL: kimiUsagesURL,
            fallbackUsage: fallbackUsage,
            now: now
        )

        let codexStats = queryRavenCLIStats(dbURL: ravenURL, clientPrefix: "codex", dateString: dateString)
        let copilotSessionStats = queryCopilotSessionStats(dbURL: copilotURL, dateString: dateString)
        let copilotRavenStats = queryRavenCLIStats(dbURL: ravenURL, clientPrefix: "magpie", dateString: dateString)
        let claudeRavenStats = queryRavenCLIStats(dbURL: ravenURL, clientPrefix: "claude", dateString: dateString)
        let claudeWarehouseStats = queryWarehouseClaudeStats(dbURL: warehouseURL, dateString: dateString)
        let kimiStats = queryKimiStats(homeURL: homeURL, dateString: dateString)
        let grokStats = queryGrokStats(homeURL: homeURL, ravenURL: ravenURL, dateString: dateString)
        let deepseekStats = queryRavenCLIStats(dbURL: ravenURL, clientPrefix: "deepseek", dateString: dateString)

        let hasAnyDatabase = FileManager.default.fileExists(atPath: ravenURL.path)
            || FileManager.default.fileExists(atPath: copilotURL.path)
            || FileManager.default.fileExists(atPath: warehouseURL.path)
            || FileManager.default.fileExists(atPath: quotasURL.path)
            || FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(".kimi-code").path)
            || FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(".grok").path)
        guard hasAnyDatabase else { return nil }

        let entries = buildCLIEntries(
            homeURL: homeURL,
            includeSystemBinaries: includeSystemBinaries,
            now: now,
            quotas: quotas,
            codexStats: codexStats,
            copilotSessionStats: copilotSessionStats,
            copilotRavenStats: copilotRavenStats,
            claudeRavenStats: claudeRavenStats,
            claudeWarehouseStats: claudeWarehouseStats,
            kimiStats: kimiStats,
            grokStats: grokStats,
            deepseekStats: deepseekStats
        )
        let rankings = queryRealRankings(ravenURL: ravenURL, copilotURL: copilotURL, dateString: dateString, fallbackEntries: entries)
        let trends = querySevenDayTrends(
            ravenURL: ravenURL, copilotURL: copilotURL, dateString: dateString,
            kimiDailyBuckets: kimiStats.dailyBuckets, grokDailyBuckets: grokStats.dailyBuckets,
            fallbackEntries: entries
        )
        return (entries, rankings, trends)
    }

    public static func isCLIInstalled(
        _ cli: AgentCLIKind,
        homeURL: URL,
        includeSystemBinaries: Bool = isLiveEnvironment
    ) -> Bool {
        let fm = FileManager.default
        let binaryName: String
        var candidatePaths: [URL] = []
        switch cli {
        case .claude:
            binaryName = "claude"
            candidatePaths = [
                homeURL.appendingPathComponent(".local/bin/claude"),
                homeURL.appendingPathComponent(".claude"),
                homeURL.appendingPathComponent(".config/claude/gtt-weekly-remaining-pct.json")
            ]
        case .codex:
            binaryName = "codex"
            candidatePaths = [
                homeURL.appendingPathComponent(".local/bin/codex"),
                homeURL.appendingPathComponent(".codex/config.toml"),
                homeURL.appendingPathComponent(".codex/sessions")
            ]
        case .copilot:
            binaryName = "copilot"
            candidatePaths = [
                homeURL.appendingPathComponent(".local/bin/copilot"),
                homeURL.appendingPathComponent(".copilot/config.json"),
                homeURL.appendingPathComponent(".copilot/session-store.db")
            ]
        case .kimi:
            binaryName = "kimi"
            candidatePaths = [
                homeURL.appendingPathComponent(".kimi-code/bin/kimi"),
                homeURL.appendingPathComponent(".local/bin/kimi"),
                homeURL.appendingPathComponent(".kimi-code/session_index.jsonl"),
                homeURL.appendingPathComponent(".kimi-code/credentials/kimi-code.json"),
                homeURL.appendingPathComponent(".kimi/credentials/kimi-code.json")
            ]
        case .grok:
            binaryName = "grok"
            candidatePaths = [
                homeURL.appendingPathComponent(".grok/bin/grok"),
                homeURL.appendingPathComponent(".local/bin/grok"),
                homeURL.appendingPathComponent(".grok/auth.json"),
                homeURL.appendingPathComponent(".grok/config.toml"),
                homeURL.appendingPathComponent(".grok/sessions")
            ]
        case .deepseek:
            binaryName = "deepseek"
            candidatePaths = [
                homeURL.appendingPathComponent(".local/bin/deepseek"),
                homeURL.appendingPathComponent(".deepseek/config.json"),
                homeURL.appendingPathComponent(".deepseek/config.toml"),
                homeURL.appendingPathComponent(".deepseek/auth.json"),
                homeURL.appendingPathComponent(".deepseek/sessions")
            ]
        }
        if includeSystemBinaries {
            candidatePaths.append(URL(fileURLWithPath: "/opt/homebrew/bin/\(binaryName)"))
            candidatePaths.append(URL(fileURLWithPath: "/usr/local/bin/\(binaryName)"))
        }
        return candidatePaths.contains { fm.fileExists(atPath: $0.path) }
    }

    public static func detectClaudeAuthState(
        homeURL: URL,
        quotas: RealQuotaSnapshot,
        now: Date = Date()
    ) -> CLIAuthState {
        let loginsURL = homeURL.appendingPathComponent(".config/magpie/logins.json")
        guard let data = try? Data(contentsOf: loginsURL),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            if let readAt = quotas.claudeReadAtDate, now.timeIntervalSince(readAt) <= 86_400 {
                return .authenticated
            }
            return .notLoggedIn(loginCommand: "claude login")
        }
        guard let claudeLogin = items.first(where: { ($0["agent"] as? String) == "claude" }) else {
            return .notLoggedIn(loginCommand: "claude login")
        }
        if let auth = claudeLogin["auth"] as? [String: Any],
           let oauth = auth["claudeAiOauth"] as? [String: Any],
           let expiresMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           expiresMs / 1000.0 < now.timeIntervalSince1970 {
            let reason = DashboardL10n.format("dashboard.auth.expired_hint_format", "Auth expired · run %@", "claude login")
            return .authExpired(reason: reason, loginCommand: "claude login")
        }
        if let readAt = quotas.claudeReadAtDate {
            if now.timeIntervalSince(readAt) > 86_400 {
                let reason = DashboardL10n.format("dashboard.auth.expired_hint_format", "Auth expired · run %@", "claude login")
                return .authExpired(reason: reason, loginCommand: "claude login")
            }
            return .authenticated
        }
        if quotas.claudeSevenDayUsedFraction != nil {
            return .authenticated
        }
        return .notLoggedIn(loginCommand: "claude login")
    }

    public static func detectKimiAuthState(
        homeURL: URL,
        kimiStats: KimiTelemetryStats,
        now: Date = Date()
    ) -> CLIAuthState {
        if kimiStats.isQuotaExhausted {
            return .quotaExhausted(
                reason: DashboardL10n.tr("dashboard.auth.kimi_quota_exhausted", "Weekly quota exhausted (429)")
            )
        }
        let credCandidates = [
            homeURL.appendingPathComponent(".kimi-code/credentials/kimi-code.json"),
            homeURL.appendingPathComponent(".kimi/credentials/kimi-code.json")
        ]
        guard let credURL = credCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: credURL),
              !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .notLoggedIn(loginCommand: "kimi login")
        }
        let token = (obj["access_token"] as? String) ?? ""
        if token.isEmpty {
            return .notLoggedIn(loginCommand: "kimi login")
        }
        if let expiresAt = (obj["expires_at"] as? NSNumber)?.doubleValue {
            let expSec = expiresAt > 10_000_000_000 ? expiresAt / 1000.0 : expiresAt
            if expSec < now.timeIntervalSince1970 && kimiStats.latestCompletedTimestamp <= expSec {
                let reason = DashboardL10n.format("dashboard.auth.login_expired_hint_format", "Login expired · run %@", "kimi login")
                return .authExpired(reason: reason, loginCommand: "kimi login")
            }
        }
        return .authenticated
    }

    public static func detectGrokAuthState(
        homeURL: URL,
        quotas: RealQuotaSnapshot,
        now: Date = Date()
    ) -> CLIAuthState {
        let authURL = homeURL.appendingPathComponent(".grok/auth.json")
        let pluginAuthURL = homeURL.appendingPathComponent(".config/magpie/plugin-auth.json")
        var grokExpiresDate: Date?
        var hasGrokAuthEntry = false

        if let data = try? Data(contentsOf: authURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (_, val) in root {
                guard let entry = val as? [String: Any] else { continue }
                hasGrokAuthEntry = true
                if let expStr = entry["expires_at"] as? String, let parsed = parseISO8601Date(expStr) {
                    grokExpiresDate = parsed
                } else if let expNum = (entry["expires_at"] as? NSNumber)?.doubleValue {
                    let sec = expNum > 10_000_000_000 ? expNum / 1000.0 : expNum
                    grokExpiresDate = Date(timeIntervalSince1970: sec)
                }
            }
        }

        var pluginValid = false
        if let pData = try? Data(contentsOf: pluginAuthURL),
           let pRoot = try? JSONSerialization.jsonObject(with: pData) as? [String: Any],
           let grokPlugin = pRoot["grok"] as? [String: Any],
           let expMs = (grokPlugin["expires"] as? NSNumber)?.doubleValue {
            hasGrokAuthEntry = true
            let sec = expMs > 10_000_000_000 ? expMs / 1000.0 : expMs
            if sec >= now.timeIntervalSince1970 {
                pluginValid = true
            }
        }

        if !hasGrokAuthEntry && quotas.grokSevenDayUsedFraction == nil {
            return .notLoggedIn(loginCommand: "grok login")
        }
        if let expDate = grokExpiresDate, expDate < now, !pluginValid {
            let reason = DashboardL10n.format("dashboard.auth.expired_hint_format", "Auth expired · run %@", "grok login")
            return .authExpired(reason: reason, loginCommand: "grok login")
        }
        return .authenticated
    }

    // swiftlint:disable:next function_parameter_count
    private static func buildCLIEntries(
        homeURL: URL,
        includeSystemBinaries: Bool,
        now: Date,
        quotas: RealQuotaSnapshot,
        codexStats: CLIWindowStats,
        copilotSessionStats: CLIWindowStats,
        copilotRavenStats: CLIWindowStats,
        claudeRavenStats: CLIWindowStats,
        claudeWarehouseStats: CLIWindowStats,
        kimiStats: KimiTelemetryStats,
        grokStats: GrokTelemetryStats,
        deepseekStats: CLIWindowStats
    ) -> [CLICostQuotaEntry] {
        let weeklyQuotaLabel = DashboardL10n.tr("dashboard.quota.weekly_label", "7d Quota")
        let claudeQuotaLabel = DashboardL10n.tr("dashboard.quota.claude_7d_label", "Pro 7d Quota")
        var entries: [CLICostQuotaEntry] = []

        if isCLIInstalled(.claude, homeURL: homeURL, includeSystemBinaries: includeSystemBinaries) {
            entries.append(makeClaudeEntry(homeURL: homeURL, now: now, quotas: quotas, claudeRavenStats: claudeRavenStats, claudeWarehouseStats: claudeWarehouseStats, claudeQuotaLabel: claudeQuotaLabel))
        }

        if isCLIInstalled(.codex, homeURL: homeURL, includeSystemBinaries: includeSystemBinaries) {
            entries.append(makeCodexEntry(homeURL: homeURL, quotas: quotas, codexStats: codexStats, weeklyQuotaLabel: weeklyQuotaLabel))
        }

        if isCLIInstalled(.kimi, homeURL: homeURL, includeSystemBinaries: includeSystemBinaries) {
            let kimiAuth = detectKimiAuthState(homeURL: homeURL, kimiStats: kimiStats, now: now)
            let isExhausted = (kimiAuth.badgeTitle == DashboardL10n.tr("dashboard.auth.badge_quota_exhausted", "Quota Exhausted"))
            let isAuthenticated = (kimiAuth == .authenticated)
            let kimi7dQuota: Double? = isExhausted ? 1.0 : (isAuthenticated ? (quotas.kimiSevenDayUsedFraction ?? 0.0) : nil)
            let kimi5hQuota: Double? = isAuthenticated ? quotas.kimiFiveHourUsedFraction : nil
            entries.append(
                CLICostQuotaEntry(
                    id: "cli-kimi", cliFilter: .kimi, displayName: "Kimi CLI", modelTag: "Kimi Code (5h / 7d)",
                    todayCostUSD: 0.0, periodCostUSD: 0.0, quotaLimitUSD: 100.0,
                    activeTokens: kimiStats.dayTokens, cacheTokens: 0, interactionCount: kimiStats.dayRuns,
                    isAvailable: true, quotaUsedOverride: kimi7dQuota,
                    quotaLabel: (isAuthenticated || isExhausted) ? weeklyQuotaLabel : nil,
                    periodTotalTokens: kimiStats.weekTokens,
                    secondaryQuotaUsed: kimi5hQuota,
                    secondaryQuotaLabel: kimi5hQuota != nil ? "5h" : nil,
                    quotaResetText: isAuthenticated ? quotas.kimiResetText : nil,
                    authState: kimiAuth
                )
            )
        }

        if isCLIInstalled(.copilot, homeURL: homeURL, includeSystemBinaries: includeSystemBinaries) {
            entries.append(makeCopilotEntry(homeURL: homeURL, copilotSessionStats: copilotSessionStats, copilotRavenStats: copilotRavenStats))
        }

        if isCLIInstalled(.grok, homeURL: homeURL, includeSystemBinaries: includeSystemBinaries) {
            let grokAuth = detectGrokAuthState(homeURL: homeURL, quotas: quotas, now: now)
            let grokQuota = grokAuth == .authenticated ? quotas.grokSevenDayUsedFraction : nil
            entries.append(
                CLICostQuotaEntry(
                    id: "cli-grok", cliFilter: .grok, displayName: "Grok CLI",
                    modelTag: grokStats.modelsSummary.isEmpty ? "grok-4.7-build" : grokStats.modelsSummary,
                    todayCostUSD: grokStats.dayCostUSD, periodCostUSD: grokStats.weekCostUSD, quotaLimitUSD: 100.0,
                    activeTokens: grokStats.dayActiveTokens, cacheTokens: grokStats.dayCacheTokens, interactionCount: grokStats.dayRuns,
                    isAvailable: true, quotaUsedOverride: grokQuota,
                    quotaLabel: grokQuota != nil ? weeklyQuotaLabel : nil,
                    periodTotalTokens: grokStats.weekTotalTokens,
                    quotaResetText: grokAuth == .authenticated ? quotas.grokResetText : nil,
                    authState: grokAuth
                )
            )
        }

        if isCLIInstalled(.deepseek, homeURL: homeURL, includeSystemBinaries: includeSystemBinaries) {
            let hasDeepSeekConfig = FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(".deepseek/config.json").path)
                || FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(".deepseek/config.toml").path)
                || FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(".deepseek/auth.json").path)
                || (deepseekStats.weekIn + deepseekStats.weekOut) > 0
            let deepseekAuth: CLIAuthState = hasDeepSeekConfig ? .authenticated : .notLoggedIn(loginCommand: "deepseek login")
            entries.append(
                CLICostQuotaEntry(
                    id: "cli-deepseek", cliFilter: .deepseek, displayName: "DeepSeek CLI",
                    modelTag: deepseekStats.modelsSummary.isEmpty ? "deepseek-chat / reasoner" : deepseekStats.modelsSummary,
                    todayCostUSD: 0.0, periodCostUSD: 0.0, quotaLimitUSD: 100.0,
                    activeTokens: deepseekStats.dayIn + deepseekStats.dayOut, cacheTokens: deepseekStats.dayCache,
                    interactionCount: deepseekStats.dayRuns,
                    isAvailable: true, quotaUsedOverride: nil, quotaLabel: nil,
                    periodTotalTokens: deepseekStats.weekIn + deepseekStats.weekOut + deepseekStats.weekCache,
                    authState: deepseekAuth
                )
            )
        }

        return entries
    }

    private static func makeClaudeEntry(
        homeURL: URL, now: Date, quotas: RealQuotaSnapshot,
        claudeRavenStats: CLIWindowStats, claudeWarehouseStats: CLIWindowStats, claudeQuotaLabel: String
    ) -> CLICostQuotaEntry {
        let dayIn = claudeRavenStats.dayIn + claudeWarehouseStats.dayIn
        let dayOut = claudeRavenStats.dayOut + claudeWarehouseStats.dayOut
        let dayCache = claudeRavenStats.dayCache + claudeWarehouseStats.dayCache
        let dayRuns = claudeRavenStats.dayRuns + claudeWarehouseStats.dayRuns
        let weekIn = claudeRavenStats.weekIn + claudeWarehouseStats.weekIn
        let weekOut = claudeRavenStats.weekOut + claudeWarehouseStats.weekOut
        let weekCache = claudeRavenStats.weekCache + claudeWarehouseStats.weekCache
        let todayCost = computeCostUSD(input: dayIn, output: dayOut, cache: dayCache, inRate: 3.0, outRate: 15.0, cacheRate: 0.30)
        let weekCost = computeCostUSD(input: weekIn, output: weekOut, cache: weekCache, inRate: 3.0, outRate: 15.0, cacheRate: 0.30)
        let auth = detectClaudeAuthState(homeURL: homeURL, quotas: quotas, now: now)
        let validQuota = auth == .authenticated ? quotas.claudeSevenDayUsedFraction : nil
        return CLICostQuotaEntry(
            id: "cli-claude", cliFilter: .claude, displayName: "Claude Code", modelTag: "Claude Pro (5h / 7d)",
            todayCostUSD: todayCost, periodCostUSD: weekCost, quotaLimitUSD: 100.0,
            activeTokens: dayIn + dayOut, cacheTokens: dayCache, interactionCount: dayRuns,
            isAvailable: true, quotaUsedOverride: validQuota,
            quotaLabel: auth == .authenticated && validQuota != nil ? claudeQuotaLabel : nil,
            periodTotalTokens: weekIn + weekOut + weekCache,
            secondaryQuotaUsed: auth == .authenticated ? quotas.claudeFiveHourUsedFraction : nil,
            secondaryQuotaLabel: auth == .authenticated ? "5h" : nil,
            quotaResetText: auth == .authenticated ? quotas.claudeResetText : nil,
            authState: auth
        )
    }

    private static func makeCodexEntry(
        homeURL: URL, quotas: RealQuotaSnapshot, codexStats: CLIWindowStats, weeklyQuotaLabel: String
    ) -> CLICostQuotaEntry {
        let todayCost = computeCostUSD(input: codexStats.dayIn, output: codexStats.dayOut, cache: codexStats.dayCache, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
        let weekCost = computeCostUSD(input: codexStats.weekIn, output: codexStats.weekOut, cache: codexStats.weekCache, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
        let hasConfig = FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(".codex/config.toml").path)
            || codexStats.weekIn + codexStats.weekOut > 0
            || quotas.cursorWeeklyUsedFraction != nil
        let auth: CLIAuthState = hasConfig ? .authenticated : .notLoggedIn(loginCommand: "codex login")
        return CLICostQuotaEntry(
            id: "cli-codex", cliFilter: .codex, displayName: "Codex CLI",
            modelTag: codexStats.modelsSummary.isEmpty ? "gpt-6.1-sol / gemini-4-argon" : codexStats.modelsSummary,
            todayCostUSD: todayCost, periodCostUSD: weekCost, quotaLimitUSD: 100.0,
            activeTokens: codexStats.dayIn + codexStats.dayOut, cacheTokens: codexStats.dayCache, interactionCount: codexStats.dayRuns,
            isAvailable: true, quotaUsedOverride: quotas.cursorWeeklyUsedFraction ?? 0.0,
            quotaLabel: auth == .authenticated ? weeklyQuotaLabel : nil,
            periodTotalTokens: codexStats.weekIn + codexStats.weekOut + codexStats.weekCache,
            quotaResetText: quotas.cursorResetText, authState: auth
        )
    }

    private static func makeCopilotEntry(
        homeURL: URL, copilotSessionStats: CLIWindowStats, copilotRavenStats: CLIWindowStats
    ) -> CLICostQuotaEntry {
        let useRaven = copilotSessionStats.dayRuns == 0 && copilotRavenStats.dayRuns > 0
        let dayIn = useRaven ? copilotRavenStats.dayIn : copilotSessionStats.dayIn
        let dayOut = useRaven ? copilotRavenStats.dayOut : copilotSessionStats.dayOut
        let dayCache = useRaven ? copilotRavenStats.dayCache : copilotSessionStats.dayCache
        let dayRuns = useRaven ? copilotRavenStats.dayRuns : copilotSessionStats.dayRuns
        let weekIn = max(copilotSessionStats.weekIn, copilotRavenStats.weekIn)
        let weekOut = max(copilotSessionStats.weekOut, copilotRavenStats.weekOut)
        let weekCache = max(copilotSessionStats.weekCache, copilotRavenStats.weekCache)
        let todayCost = computeCostUSD(input: dayIn, output: dayOut, cache: dayCache, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
        let weekCost = computeCostUSD(input: weekIn, output: weekOut, cache: weekCache, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
        let hasConfig = FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(".copilot/config.json").path)
            || FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(".copilot/session-store.db").path)
            || (weekIn + weekOut) > 0
        let auth: CLIAuthState = hasConfig ? .authenticated : .notLoggedIn(loginCommand: "copilot login")
        return CLICostQuotaEntry(
            id: "cli-copilot", cliFilter: .copilot, displayName: "Copilot CLI",
            modelTag: copilotSessionStats.modelsSummary.isEmpty ? "gemini-4-argon / gpt-5.6-luna" : copilotSessionStats.modelsSummary,
            todayCostUSD: todayCost, periodCostUSD: weekCost, quotaLimitUSD: 100.0,
            activeTokens: dayIn + dayOut, cacheTokens: dayCache, interactionCount: dayRuns,
            isAvailable: true, quotaUsedOverride: 0.0, quotaLabel: nil,
            periodTotalTokens: weekIn + weekOut + weekCache, authState: auth
        )
    }

    private static func computeCostUSD(input: UInt64, output: UInt64, cache: UInt64, inRate: Double, outRate: Double, cacheRate: Double) -> Double {
        (Double(input) / 1_000_000.0) * inRate + (Double(output) / 1_000_000.0) * outRate + (Double(cache) / 1_000_000.0) * cacheRate
    }
}

extension LiveDashboardTelemetryReader {
    public static func readQuotas(
        magpieQuotasURL: URL,
        claudeFallbackURL: URL,
        kimiUsagesURL: URL? = nil,
        fallbackUsage: CLITokenUsageSnapshot,
        now: Date = Date()
    ) -> RealQuotaSnapshot {
        var claude7d: Double?
        var claude5h: Double?
        var cursorWeekly: Double?
        var grok7d: Double?
        var kimi7d: Double?
        var kimi5h: Double?
        var claudeReset: String?
        var cursorReset: String?
        var grokReset: String?
        var kimiReset: String?
        var claudeReadAt: Date?
        var grokReadAt: Date?
        if let data = try? Data(contentsOf: magpieQuotasURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, val) in root {
                let windows = extractWindows(from: val)
                let readAt = extractReadAtDate(from: val)
                if key.hasPrefix("claude") {
                    claudeReadAt = readAt ?? claudeReadAt
                    let isStale = readAt.map { now.timeIntervalSince($0) > 86_400 } ?? false
                    if !isStale {
                        claude7d = windowUsedFraction(in: windows, matching: "7 day") ?? claude7d
                        claude5h = windowUsedFraction(in: windows, matching: "5 hour") ?? claude5h
                        claudeReset = windowResetText(in: windows, matching: "7 day") ?? claudeReset
                    }
                } else if key.hasPrefix("cursor") {
                    cursorWeekly = windowUsedFraction(in: windows, matching: "Weekly") ?? cursorWeekly
                    cursorReset = windowResetText(in: windows, matching: "Weekly") ?? cursorReset
                } else if key.hasPrefix("grok") {
                    grokReadAt = readAt ?? grokReadAt
                    grok7d = windowUsedFraction(in: windows, matching: nil) ?? grok7d
                    grokReset = windowResetText(in: windows, matching: nil) ?? grokReset
                } else if key.hasPrefix("kimi") {
                    kimi7d = windowUsedFraction(in: windows, matching: "7 day")
                        ?? windowUsedFraction(in: windows, matching: nil)
                        ?? kimi7d
                    kimi5h = windowUsedFraction(in: windows, matching: "5 hour") ?? kimi5h
                    kimiReset = windowResetText(in: windows, matching: "7 day")
                        ?? windowResetText(in: windows, matching: nil)
                        ?? kimiReset
                }
            }
        }
        if let kimiUsagesURL,
           let parsedKimi = parseKimiUsagesFile(url: kimiUsagesURL) {
            kimi7d = parsedKimi.sevenDay ?? kimi7d
            kimi5h = parsedKimi.fiveHour ?? kimi5h
            kimiReset = parsedKimi.resetText ?? kimiReset
        }
        if claudeReadAt == nil,
           let fallbackClaude = readClaudeFallbackQuota(url: claudeFallbackURL, fallbackUsage: fallbackUsage, now: now) {
            claude7d = max(claude7d ?? 0, fallbackClaude)
        }
        return RealQuotaSnapshot(
            claudeSevenDayUsedFraction: claude7d, claudeFiveHourUsedFraction: claude5h,
            cursorWeeklyUsedFraction: cursorWeekly, grokSevenDayUsedFraction: grok7d,
            kimiSevenDayUsedFraction: kimi7d, kimiFiveHourUsedFraction: kimi5h,
            claudeResetText: claudeReset, cursorResetText: cursorReset, grokResetText: grokReset,
            kimiResetText: kimiReset, claudeReadAtDate: claudeReadAt, grokReadAtDate: grokReadAt
        )
    }

    private static func parseKimiUsagesFile(
        url: URL
    ) -> (sevenDay: Double?, fiveHour: Double?, resetText: String?)? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var sevenDay: Double?
        var fiveHour: Double?
        var resetText: String?

        if let usages = root["usages"] as? [String: Any] {
            if let limit7d = usages["limit_7d"] as? [String: Any] {
                if let ratio = (limit7d["used_ratio"] as? NSNumber)?.doubleValue {
                    sevenDay = min(max(ratio, 0), 1)
                }
                if let rawReset = limit7d["reset_time"] as? String {
                    resetText = formatResetTimestamp(rawReset)
                }
            }
            if let limit5h = usages["limit_5h"] as? [String: Any],
               let ratio = (limit5h["used_ratio"] as? NSNumber)?.doubleValue {
                fiveHour = min(max(ratio, 0), 1)
            }
        }

        if let usage = root["usage"] as? [String: Any] {
            if sevenDay == nil {
                let usedVal = (usage["used"] as? NSNumber)?.doubleValue ?? (usage["used"] as? String).flatMap(Double.init)
                let limitVal = (usage["limit"] as? NSNumber)?.doubleValue ?? (usage["limit"] as? String).flatMap(Double.init)
                if let usedVal, let limitVal, limitVal > 0 {
                    sevenDay = min(max(usedVal / limitVal, 0), 1)
                }
            }
            if resetText == nil, let rawReset = usage["resetTime"] as? String {
                resetText = formatResetTimestamp(rawReset)
            }
        }
        return (sevenDay, fiveHour, resetText)
    }

    private static func formatResetTimestamp(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        if raw.count >= 16 {
            let monthDay = String(raw.dropFirst(5).prefix(5))
            let hm = String(raw.dropFirst(11).prefix(5))
            return "Reset \(monthDay) \(hm)"
        }
        return raw
    }

    private static func extractWindows(from rawEntry: Any) -> [[String: Any]] {
        guard let entry = rawEntry as? [String: Any],
              let quota = entry["quota"] as? [String: Any],
              let windows = quota["windows"] as? [[String: Any]] else { return [] }
        return windows
    }

    private static func extractReadAtDate(from rawEntry: Any) -> Date? {
        guard let entry = rawEntry as? [String: Any] else { return nil }
        let quota = entry["quota"] as? [String: Any]
        if let raw = (quota?["readAt"] as? String) ?? (entry["at"] as? String) {
            return parseISO8601Date(raw)
        }
        return nil
    }

    internal static func parseISO8601Date(_ raw: String) -> Date? {
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: raw) { return d }
        let std = ISO8601DateFormatter()
        std.formatOptions = [.withInternetDateTime]
        return std.date(from: raw)
    }

    internal static func localDateString(from raw: String) -> String? {
        guard let date = parseISO8601Date(raw) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func windowUsedFraction(in windows: [[String: Any]], matching substring: String?) -> Double? {
        for win in windows {
            let name = (win["name"] as? String) ?? ""
            if let substring, !name.contains(substring) { continue }
            if let used = (win["used"] as? NSNumber)?.doubleValue {
                return min(max(used / 100.0, 0), 1)
            }
        }
        return nil
    }

    private static func windowResetText(in windows: [[String: Any]], matching substring: String?) -> String? {
        for win in windows {
            let name = (win["name"] as? String) ?? ""
            if let substring, !name.contains(substring) { continue }
            guard let raw = win["resetsAt"] as? String, !raw.isEmpty else { continue }
            return formatResetTimestamp(raw)
        }
        return nil
    }

    private static func readClaudeFallbackQuota(url: URL, fallbackUsage: CLITokenUsageSnapshot, now: Date) -> Double? {
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let used = (obj["used_percentage"] as? NSNumber)?.doubleValue {
            if let measuredAt = (obj["measured_at"] as? NSNumber)?.doubleValue {
                let sec = measuredAt > 10_000_000_000 ? measuredAt / 1000.0 : measuredAt
                if now.timeIntervalSince1970 - sec > 86_400 {
                    return nil
                }
            }
            return min(max(used / 100.0, 0), 1)
        }
        if let rem = fallbackUsage.claudeWeeklyRemainingPercent {
            return min(max(Double(100 - rem) / 100.0, 0), 1)
        }
        return nil
    }
}

extension LiveDashboardTelemetryReader {
    struct CLIWindowStats {
        var dayRuns: UInt64 = 0
        var dayIn: UInt64 = 0
        var dayOut: UInt64 = 0
        var dayCache: UInt64 = 0
        var weekIn: UInt64 = 0
        var weekOut: UInt64 = 0
        var weekCache: UInt64 = 0
        var modelsSummary: String = ""
    }

    static func sanitizeSQLToken(_ value: String) -> String {
        String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" })
    }

    static func openReadOnlySQLite(path: String) -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db {
            sqlite3_busy_timeout(db, 120)
            if sqlite3_exec(db, "SELECT 1 FROM sqlite_master LIMIT 1;", nil, nil, nil) == SQLITE_OK {
                return db
            }
            sqlite3_close(db)
        } else if let db {
            sqlite3_close(db)
        }
        var uriDB: OpaquePointer?
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        if sqlite3_open_v2("file:\(encoded)?mode=ro&immutable=1", &uriDB, flags | SQLITE_OPEN_URI, nil) == SQLITE_OK, let uriDB {
            return uriDB
        }
        if let uriDB { sqlite3_close(uriDB) }
        return nil
    }

    private static func executeWindowStatsQuery(
        dbURL: URL, sql: String, hasModelsColumn: Bool = true, defaultModels: String = ""
    ) -> CLIWindowStats {
        guard let db = openReadOnlySQLite(path: dbURL.path) else { return CLIWindowStats() }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            if let stmt { sqlite3_finalize(stmt) }
            return CLIWindowStats()
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return CLIWindowStats() }
        let models = hasModelsColumn ? (sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "") : defaultModels
        return CLIWindowStats(
            dayRuns: UInt64(max(sqlite3_column_int64(stmt, 0), 0)),
            dayIn: UInt64(max(sqlite3_column_int64(stmt, 1), 0)),
            dayOut: UInt64(max(sqlite3_column_int64(stmt, 2), 0)),
            dayCache: UInt64(max(sqlite3_column_int64(stmt, 3), 0)),
            weekIn: UInt64(max(sqlite3_column_int64(stmt, 4), 0)),
            weekOut: UInt64(max(sqlite3_column_int64(stmt, 5), 0)),
            weekCache: UInt64(max(sqlite3_column_int64(stmt, 6), 0)),
            modelsSummary: models
        )
    }

    static func queryRavenCLIStats(dbURL: URL, clientPrefix: String, dateString: String) -> CLIWindowStats {
        let safeDate = sanitizeSQLToken(dateString)
        let safePrefix = sanitizeSQLToken(clientPrefix)
        let sql = """
        SELECT
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = '\(safeDate)' THEN 1 ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = '\(safeDate)' THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = '\(safeDate)' THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = '\(safeDate)' THEN COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0) ELSE 0 END),
            GROUP_CONCAT(DISTINCT CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = '\(safeDate)' AND resolved_model != '' THEN resolved_model ELSE NULL END)
        FROM requests WHERE client_name LIKE '\(safePrefix)%'
          AND date(timestamp/1000, 'unixepoch', 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)';
        """
        return executeWindowStatsQuery(dbURL: dbURL, sql: sql)
    }

    static func queryCopilotSessionStats(dbURL: URL, dateString: String) -> CLIWindowStats {
        let safeDate = sanitizeSQLToken(dateString)
        let uncached = "MAX(0, COALESCE(input_tokens, 0) - COALESCE(cache_read_tokens, 0) - COALESCE(cache_write_tokens, 0))"
        let sql = """
        SELECT
            SUM(CASE WHEN date(created_at, 'localtime') = '\(safeDate)' THEN 1 ELSE 0 END),
            SUM(CASE WHEN date(created_at, 'localtime') = '\(safeDate)' THEN \(uncached) ELSE 0 END),
            SUM(CASE WHEN date(created_at, 'localtime') = '\(safeDate)' THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(created_at, 'localtime') = '\(safeDate)' THEN COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(created_at, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN \(uncached) ELSE 0 END),
            SUM(CASE WHEN date(created_at, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(created_at, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0) ELSE 0 END),
            GROUP_CONCAT(DISTINCT CASE WHEN date(created_at, 'localtime') = '\(safeDate)' AND model != '' THEN model ELSE NULL END)
        FROM assistant_usage_events
        WHERE date(created_at, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)';
        """
        return executeWindowStatsQuery(dbURL: dbURL, sql: sql)
    }

    static func queryWarehouseClaudeStats(dbURL: URL, dateString: String) -> CLIWindowStats {
        let safeDate = sanitizeSQLToken(dateString)
        let sql = """
        SELECT
            SUM(CASE WHEN date(ts, 'localtime') = '\(safeDate)' THEN 1 ELSE 0 END),
            SUM(CASE WHEN date(ts, 'localtime') = '\(safeDate)' THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(ts, 'localtime') = '\(safeDate)' THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(ts, 'localtime') = '\(safeDate)' THEN COALESCE(cache_read,0)+COALESCE(cache_creation,0) ELSE 0 END),
            SUM(CASE WHEN date(ts, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(ts, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(ts, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)' THEN COALESCE(cache_read,0)+COALESCE(cache_creation,0) ELSE 0 END)
        FROM fact_turn
        WHERE date(ts, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)';
        """
        return executeWindowStatsQuery(dbURL: dbURL, sql: sql, hasModelsColumn: false, defaultModels: "claude-opus / sonnet")
    }

    public struct KimiTelemetryStats: Sendable, Equatable {
        public var dayTokens: UInt64 = 0
        public var dayRuns: UInt64 = 0
        public var weekTokens: UInt64 = 0
        public var isQuotaExhausted: Bool = false
        public var latestCompletedTimestamp: Double = 0
        public var dailyBuckets: [String: (tokens: UInt64, runs: Int)] = [:]

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.dayTokens == rhs.dayTokens
                && lhs.dayRuns == rhs.dayRuns
                && lhs.weekTokens == rhs.weekTokens
                && lhs.isQuotaExhausted == rhs.isQuotaExhausted
                && lhs.latestCompletedTimestamp == rhs.latestCompletedTimestamp
        }
    }

    private static var cachedKimiKey: String?
    private static var cachedKimiStats: KimiTelemetryStats?

    public static func queryKimiStats(homeURL: URL, dateString: String) -> KimiTelemetryStats {
        let kimiRoot = homeURL.appendingPathComponent(".kimi-code")
        let indexURL = kimiRoot.appendingPathComponent("session_index.jsonl")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: indexURL.path),
              let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 else {
            return KimiTelemetryStats()
        }
        let cacheKey = "\(homeURL.path)-\(dateString)-\(Int(mtime))"
        if cachedKimiKey == cacheKey, let cached = cachedKimiStats {
            return cached
        }
        guard let indexText = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return KimiTelemetryStats()
        }
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        let hrFmt = DateFormatter()
        hrFmt.calendar = fmt.calendar
        hrFmt.locale = fmt.locale
        hrFmt.timeZone = fmt.timeZone
        hrFmt.dateFormat = "yyyy-MM-dd HH:00"
        let targetDate = fmt.date(from: dateString) ?? Date()
        let cutoffSec = targetDate.timeIntervalSince1970 - 6.0 * 86_400.0
        let endSec = targetDate.timeIntervalSince1970 + 86_400.0

        var buckets: [String: (tokens: UInt64, runs: Int)] = [:]
        var latestExhaustedTs: Double = 0
        var latestCompletedTs: Double = 0

        for line in indexText.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionDir = obj["sessionDir"] as? String else { continue }
            let wireURL = URL(fileURLWithPath: sessionDir).appendingPathComponent("agents/main/wire.jsonl")
            guard let wAttrs = try? FileManager.default.attributesOfItem(atPath: wireURL.path),
                  let wMtime = (wAttrs[.modificationDate] as? Date)?.timeIntervalSince1970,
                  wMtime >= cutoffSec,
                  let wireText = try? String(contentsOf: wireURL, encoding: .utf8) else { continue }
            var sessionLastExhausted = 0.0
            var sessionLastCompleted = 0.0
            for wLine in wireText.split(separator: "\n") {
                if wLine.contains("APIProviderQuotaExhaustedError") {
                    if let wData = wLine.data(using: .utf8),
                       let rec = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
                       let tsMs = (rec["time"] as? NSNumber)?.doubleValue {
                        sessionLastExhausted = max(sessionLastExhausted, tsMs / 1000.0)
                    } else {
                        sessionLastExhausted = max(sessionLastExhausted, wMtime)
                    }
                } else if wLine.contains("\"prompt.completed\"") {
                    if let wData = wLine.data(using: .utf8),
                       let rec = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
                       let tsMs = (rec["time"] as? NSNumber)?.doubleValue {
                        sessionLastCompleted = max(sessionLastCompleted, tsMs / 1000.0)
                    } else {
                        sessionLastCompleted = max(sessionLastCompleted, wMtime + 0.001)
                    }
                }
                if wLine.contains("token_counting.turn_recorded") {
                    guard let wData = wLine.data(using: .utf8),
                          let rec = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
                          let tok = (rec["tokens"] as? NSNumber)?.uint64Value,
                          let tsMs = (rec["time"] as? NSNumber)?.doubleValue else { continue }
                    let sec = tsMs / 1000.0
                    guard sec >= cutoffSec && sec <= endSec else { continue }
                    let hrStr = hrFmt.string(from: Date(timeIntervalSince1970: sec))
                    let prev = buckets[hrStr] ?? (0, 0)
                    buckets[hrStr] = (prev.tokens + tok, prev.runs + 1)
                }
            }
            latestExhaustedTs = max(latestExhaustedTs, sessionLastExhausted)
            latestCompletedTs = max(latestCompletedTs, sessionLastCompleted)
        }

        let dayStat = buckets.reduce((tokens: UInt64(0), runs: 0)) { acc, pair in
            pair.key.hasPrefix(dateString) ? (acc.tokens + pair.value.tokens, acc.runs + pair.value.runs) : acc
        }
        let weekTok = buckets.values.reduce(UInt64(0)) { $0 + $1.tokens }
        let isExhausted = latestExhaustedTs > 0 && latestExhaustedTs > latestCompletedTs
        let stats = KimiTelemetryStats(
            dayTokens: dayStat.tokens,
            dayRuns: UInt64(dayStat.runs),
            weekTokens: weekTok,
            isQuotaExhausted: isExhausted,
            latestCompletedTimestamp: latestCompletedTs,
            dailyBuckets: buckets
        )
        cachedKimiKey = cacheKey
        cachedKimiStats = stats
        return stats
    }

    struct DailyTokenBucket {
        var input: UInt64 = 0
        var output: UInt64 = 0
        var cache: UInt64 = 0
        var runs: Int = 0
        var total: UInt64 { input + output + cache }
    }

    struct GrokTelemetryStats {
        var dayActiveTokens: UInt64 = 0
        var dayCacheTokens: UInt64 = 0
        var dayRuns: UInt64 = 0
        var weekTotalTokens: UInt64 = 0
        var dayCostUSD: Double = 0.0
        var weekCostUSD: Double = 0.0
        var modelsSummary: String = ""
        var dailyBuckets: [String: DailyTokenBucket] = [:]
    }

    static func queryGrokStats(homeURL: URL, ravenURL: URL, dateString: String) -> GrokTelemetryStats {
        let ravenStats = queryRavenCLIStats(dbURL: ravenURL, clientPrefix: "grok", dateString: dateString)
        var stats = GrokTelemetryStats(
            dayActiveTokens: ravenStats.dayIn + ravenStats.dayOut,
            dayCacheTokens: ravenStats.dayCache,
            dayRuns: ravenStats.dayRuns,
            weekTotalTokens: ravenStats.weekIn + ravenStats.weekOut + ravenStats.weekCache,
            modelsSummary: ravenStats.modelsSummary
        )
        let sessionsRoot = homeURL.appendingPathComponent(".grok/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return stats
        }
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        let hrFmt = DateFormatter()
        hrFmt.calendar = fmt.calendar
        hrFmt.locale = fmt.locale
        hrFmt.timeZone = fmt.timeZone
        hrFmt.dateFormat = "yyyy-MM-dd HH:00"
        let targetDate = fmt.date(from: dateString) ?? Date()
        let cutoffSec = targetDate.timeIntervalSince1970 - 6.0 * 86_400.0
        let endSec = targetDate.timeIntervalSince1970 + 86_400.0

        var models = Set<String>()
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "usage.json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let turns = obj["turns"] as? [[String: Any]] else { continue }
            for turn in turns {
                guard let endedAt = turn["endedAt"] as? String,
                      let date = parseISO8601Date(endedAt) else { continue }
                let sec = date.timeIntervalSince1970
                guard sec >= cutoffSec && sec <= endSec else { continue }
                let inTok = (turn["inputTokens"] as? NSNumber)?.uint64Value ?? 0
                let outTok = (turn["outputTokens"] as? NSNumber)?.uint64Value ?? 0
                let cacheTok = ((turn["cachedReadTokens"] as? NSNumber)?.uint64Value ?? 0)
                    + ((turn["cacheCreationTokens"] as? NSNumber)?.uint64Value ?? 0)
                let calls = max((turn["modelCalls"] as? NSNumber)?.intValue ?? 1, 1)
                if let modelId = turn["primaryModelId"] as? String, !modelId.isEmpty {
                    models.insert(modelId)
                }
                let hrKey = hrFmt.string(from: date)
                let prev = stats.dailyBuckets[hrKey] ?? DailyTokenBucket()
                stats.dailyBuckets[hrKey] = DailyTokenBucket(
                    input: prev.input + inTok,
                    output: prev.output + outTok,
                    cache: prev.cache + cacheTok,
                    runs: prev.runs + calls
                )
                stats.weekTotalTokens += inTok + outTok + cacheTok
                if hrKey.hasPrefix(dateString) {
                    stats.dayActiveTokens += inTok + outTok
                    stats.dayCacheTokens += cacheTok
                    stats.dayRuns += UInt64(calls)
                }
            }
        }
        if stats.modelsSummary.isEmpty && !models.isEmpty {
            stats.modelsSummary = models.sorted().joined(separator: " / ")
        }
        return stats
    }

    static func querySevenDayTrends(
        ravenURL: URL, copilotURL: URL, dateString: String,
        kimiDailyBuckets: [String: (tokens: UInt64, runs: Int)] = [:],
        grokDailyBuckets: [String: DailyTokenBucket] = [:],
        fallbackEntries: [CLICostQuotaEntry]
    ) -> [TrendDataPoint] {
        let safeDate = sanitizeSQLToken(dateString)
        let hrFmt = DateFormatter()
        hrFmt.calendar = Calendar(identifier: .gregorian)
        hrFmt.locale = Locale(identifier: "en_US_POSIX")
        hrFmt.timeZone = TimeZone.current
        hrFmt.dateFormat = "yyyy-MM-dd HH:mm"

        var bucketMap: [String: [DashboardCLIFilter: DailyTokenBucket]] = [:]
        for (hrKey, stat) in kimiDailyBuckets where stat.tokens > 0 {
            let inTok = UInt64(Double(stat.tokens) * 0.85)
            bucketMap[hrKey, default: [:]][.kimi] = DailyTokenBucket(input: inTok, output: stat.tokens - inTok, cache: 0, runs: stat.runs)
        }
        for (hrKey, stat) in grokDailyBuckets where stat.total > 0 {
            bucketMap[hrKey, default: [:]][.grok] = stat
        }
        populateRavenTrendBuckets(&bucketMap, ravenURL: ravenURL, safeDate: safeDate)
        populateCopilotTrendBuckets(&bucketMap, copilotURL: copilotURL, safeDate: safeDate)

        var points: [TrendDataPoint] = []
        for hrKey in bucketMap.keys.sorted() {
            guard let cliDict = bucketMap[hrKey] else { continue }
            let parsedDate = hrFmt.date(from: hrKey)
            for cli in [DashboardCLIFilter.copilot, .codex, .claude, .kimi, .grok, .deepseek] {
                guard let stat = cliDict[cli], stat.total > 0 else { continue }
                points.append(
                    TrendDataPoint(
                        id: "trend-\(hrKey)-\(cli.rawValue)", bucketLabel: hrKey, category: cli.rawValue,
                        cliFilter: cli, invocations: stat.runs, successRate: 0.99, costUSD: 0,
                        totalTokens: stat.total, inputTokens: stat.input, outputTokens: stat.output,
                        cacheTokens: stat.cache, bucketDate: parsedDate
                    )
                )
            }
        }
        return points.isEmpty ? DashboardWorkspaceStore.deriveTrendPoints(from: fallbackEntries) : points
    }

    private static func populateRavenTrendBuckets(
        _ bucketMap: inout [String: [DashboardCLIFilter: DailyTokenBucket]],
        ravenURL: URL, safeDate: String
    ) {
        guard let db = openReadOnlySQLite(path: ravenURL.path) else { return }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT strftime('%Y-%m-%d %H:00', timestamp/1000, 'unixepoch', 'localtime') as hr,
               CASE WHEN client_name LIKE 'codex%' THEN 'codex'
                    WHEN client_name LIKE 'claude%' THEN 'claude'
                    WHEN client_name LIKE 'grok%' THEN 'grok'
                    WHEN client_name LIKE 'deepseek%' THEN 'deepseek'
                    ELSE 'copilot' END as cli_kind,
               SUM(COALESCE(input_tokens,0)), SUM(COALESCE(output_tokens,0)),
               SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)), COUNT(*)
        FROM requests
        WHERE date(timestamp/1000, 'unixepoch', 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)'
        GROUP BY hr, cli_kind;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let hrPtr = sqlite3_column_text(stmt, 0), let kindPtr = sqlite3_column_text(stmt, 1) else { continue }
            let hrKey = String(cString: hrPtr)
            let kind = String(cString: kindPtr)
            let cli: DashboardCLIFilter = kind == "codex" ? .codex
                : (kind == "claude" ? .claude : (kind == "grok" ? .grok : (kind == "deepseek" ? .deepseek : .copilot)))
            bucketMap[hrKey, default: [:]][cli] = DailyTokenBucket(
                input: UInt64(max(sqlite3_column_int64(stmt, 2), 0)),
                output: UInt64(max(sqlite3_column_int64(stmt, 3), 0)),
                cache: UInt64(max(sqlite3_column_int64(stmt, 4), 0)),
                runs: Int(max(sqlite3_column_int64(stmt, 5), 0))
            )
        }
    }

    private static func populateCopilotTrendBuckets(
        _ bucketMap: inout [String: [DashboardCLIFilter: DailyTokenBucket]],
        copilotURL: URL, safeDate: String
    ) {
        guard let db = openReadOnlySQLite(path: copilotURL.path) else { return }
        defer { sqlite3_close(db) }
        let uncached = "MAX(0, COALESCE(input_tokens, 0) - COALESCE(cache_read_tokens, 0) - COALESCE(cache_write_tokens, 0))"
        let sql = """
        SELECT strftime('%Y-%m-%d %H:00', created_at, 'localtime') as hr,
               SUM(\(uncached)), SUM(COALESCE(output_tokens,0)),
               SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)), COUNT(*)
        FROM assistant_usage_events
        WHERE date(created_at, 'localtime') BETWEEN date('\(safeDate)', '-6 days') AND '\(safeDate)'
        GROUP BY hr;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let hrPtr = sqlite3_column_text(stmt, 0) else { continue }
            let hrKey = String(cString: hrPtr)
            let inTok = UInt64(max(sqlite3_column_int64(stmt, 1), 0))
            let outTok = UInt64(max(sqlite3_column_int64(stmt, 2), 0))
            let cacheTok = UInt64(max(sqlite3_column_int64(stmt, 3), 0))
            let runs = Int(max(sqlite3_column_int64(stmt, 4), 0))
            let prev = bucketMap[hrKey]?[.copilot] ?? DailyTokenBucket()
            if (inTok + outTok + cacheTok) > prev.total {
                bucketMap[hrKey, default: [:]][.copilot] = DailyTokenBucket(input: inTok, output: outTok, cache: cacheTok, runs: max(prev.runs, runs))
            }
        }
    }

    static func queryRealRankings(
        ravenURL: URL, copilotURL: URL, dateString: String, fallbackEntries: [CLICostQuotaEntry]
    ) -> [AgentRankingRow] {
        var rows: [AgentRankingRow] = []
        let safeDate = sanitizeSQLToken(dateString)
        let homeURL = ravenURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let magpieUsageURL = homeURL.appendingPathComponent(".config/magpie/usage.jsonl")
        let cindyDirURL = homeURL.appendingPathComponent("Library/Application Support/CindyGlobal")
        appendMagpieRoleRankingRows(&rows, magpieURL: magpieUsageURL, datePrefix: safeDate)
        appendCopilotSessionRankingRows(&rows, copilotURL: copilotURL, safeDate: safeDate)
        appendCindyRankingRows(&rows, cindyDirURL: cindyDirURL, safeDate: safeDate)
        appendRavenRankingRows(&rows, ravenURL: ravenURL, safeDate: safeDate)
        appendFallbackChannelRows(&rows, fallbackEntries: fallbackEntries)
        rows.sort { $0.totalTokens != $1.totalTokens ? $0.totalTokens > $1.totalTokens : $0.runs > $1.runs }
        return rows.isEmpty ? DashboardWorkspaceStore.deriveRankingRows(from: fallbackEntries) : Array(rows.prefix(12))
    }

    private struct RoleModelStat {
        var role: String = ""
        var model: String = ""
        var cli: DashboardCLIFilter = .copilot
        var calls: Int = 0
        var turns: Int = 0
        var tokens: UInt64 = 0
        var okCount: Int = 0
        var totalMs: Double = 0
    }

    private static var cachedMagpieRankingKey: String?
    private static var cachedMagpieRankingRows: [AgentRankingRow]?
    private static var cachedLiveEfficiencyKey: String?
    private static var cachedLiveEfficiencySummary: LiveEfficiencySummary?

    public static func readTailLines(of fileURL: URL, maxBytes: Int = 524_288) -> String {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return "" }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return "" }
        let limit = UInt64(max(maxBytes, 1))
        let startOffset = fileSize > limit ? (fileSize - limit) : 0
        try? handle.seek(toOffset: startOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty,
              let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return "" }
        if startOffset > 0, let newlineIdx = decoded.firstIndex(of: "\n") {
            return String(decoded[decoded.index(after: newlineIdx)...])
        }
        return decoded
    }

    private static func fileCacheSignature(for fileURL: URL) -> String {
        guard !isCloudDocsPath(fileURL),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            return "\(fileURL.path)-missing"
        }
        let mtime = Int((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        return "\(fileURL.path)-\(mtime)-\(size)"
    }

    private static func appendMagpieRoleRankingRows(
        _ rows: inout [AgentRankingRow], magpieURL: URL, datePrefix: String
    ) {
        let cacheKey = "\(fileCacheSignature(for: magpieURL))-\(datePrefix)"
        if cachedMagpieRankingKey == cacheKey, let cached = cachedMagpieRankingRows {
            rows.append(contentsOf: cached)
            return
        }
        let text = readTailLines(of: magpieURL)
        guard !text.isEmpty else { return }
        var map: [String: RoleModelStat] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = obj["t"] as? String,
                  localDateString(from: ts) == datePrefix else { continue }
            let req = (obj["req"] as? String) ?? ""
            let model = (obj["served"] as? String) ?? (obj["model"] as? String) ?? ""
            let agent = (obj["agent"] as? String) ?? "copilot"
            guard !model.isEmpty, model != "microsoft-decision-1", req != "router" else { continue }
            let inT = (obj["in"] as? NSNumber)?.uint64Value ?? 0
            let outT = (obj["out"] as? NSNumber)?.uint64Value ?? 0
            let crT = (obj["cache_read"] as? NSNumber)?.uint64Value ?? 0
            let cwT = (obj["cache_write"] as? NSNumber)?.uint64Value ?? 0
            let tok = inT + outT + crT + cwT
            let status = (obj["status"] as? NSNumber)?.intValue ?? 0
            let ms = (obj["ms"] as? NSNumber)?.doubleValue ?? 0
            let isStop = ((obj["stop"] as? String) ?? "") == "stop"
            let role: String = req.contains("steering") ? "M1 · Steering (TL)"
                : (req.contains("coding-escalated") ? "M1 · Writer (Escalated)"
                : (req.contains("coding") ? "M1 · Writer"
                : (req.contains("review") ? "M1 · Reviewer" : "M2 · Dispatcher (CLI)")))
            let cli: DashboardCLIFilter = agent.contains("codex") ? .codex : (agent.contains("claude") ? .claude : .copilot)
            let key = "\(role)|\(model)|\(cli.rawValue)"
            var cur = map[key] ?? RoleModelStat(role: role, model: model, cli: cli)
            cur.calls += 1
            if isStop { cur.turns += 1 }
            cur.tokens += tok
            if (200...299).contains(status) { cur.okCount += 1 }
            cur.totalMs += ms
            map[key] = cur
        }
        var built: [AgentRankingRow] = []
        for (key, s) in map where s.tokens > 0 {
            let avgSec = max((s.totalMs / Double(max(s.calls, 1))) / 1000.0, 0.1)
            let okRate = Double(s.okCount) / Double(max(s.calls, 1))
            built.append(
                AgentRankingRow(
                    id: "magpie-\(key)", agentName: s.role, modelName: s.model,
                    cliFilter: s.cli, providerName: s.cli.rawValue,
                    runs: s.calls, totalTokens: s.tokens, successRate: okRate, avgDurationSeconds: avgSec, costUSD: 0,
                    detailSummary: "\(s.role) · \(s.model) (\(s.cli.rawValue)) · \(max(s.turns, 1)) turns / \(s.calls) API calls · \(DashboardTokenFormatter.compact(s.tokens)) tok",
                    recentIssue: nil
                )
            )
        }
        cachedMagpieRankingKey = cacheKey
        cachedMagpieRankingRows = built
        rows.append(contentsOf: built)
    }

    private static func appendRavenRankingRows(
        _ rows: inout [AgentRankingRow], ravenURL: URL, safeDate: String
    ) {
        guard let db = openReadOnlySQLite(path: ravenURL.path) else { return }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT
            CASE WHEN client_name LIKE 'codex_exec%' THEN 'M1 · Writer (codex_exec)'
                 WHEN client_name LIKE 'codex-tui%' THEN 'M2 · Dispatcher (Codex)'
                 WHEN client_name LIKE 'codex_cli_rs%' THEN 'M2 · Dispatcher (Codex)'
                 WHEN client_name LIKE 'claude%' THEN 'M1 · Steering (Claude)'
                 ELSE 'M1 · Worker' END as role_group,
            CASE WHEN client_name LIKE 'codex%' THEN 'codex'
                 WHEN client_name LIKE 'claude%' THEN 'claude' ELSE 'copilot' END as cli_kind,
            COALESCE(NULLIF(resolved_model, ''), NULLIF(model, ''), 'default') as effective_model,
            COUNT(*) as runs,
            SUM(COALESCE(input_tokens,0)), SUM(COALESCE(output_tokens,0)),
            SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
            AVG(latency_ms) / 1000.0,
            1.0 * SUM(CASE WHEN status_code BETWEEN 200 AND 299 THEN 1 ELSE 0 END) / COUNT(*)
        FROM requests
        WHERE date(timestamp/1000, 'unixepoch', 'localtime') = '\(safeDate)'
          AND client_name NOT LIKE 'magpie%'
          AND COALESCE(NULLIF(resolved_model, ''), NULLIF(model, ''), '') NOT LIKE 'group/%'
        GROUP BY role_group, effective_model
        HAVING (SUM(COALESCE(input_tokens,0)) + SUM(COALESCE(output_tokens,0)) + SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0))) > 0
        ORDER BY runs DESC LIMIT 10;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        let preRavenRows = rows
        while sqlite3_step(stmt) == SQLITE_ROW {
            let role = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "M1 · Worker"
            let kind = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "copilot"
            let model = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "default"
            let runs = Int(max(sqlite3_column_int64(stmt, 3), 0))
            let inTok = UInt64(max(sqlite3_column_int64(stmt, 4), 0))
            let outTok = UInt64(max(sqlite3_column_int64(stmt, 5), 0))
            let cacheTok = UInt64(max(sqlite3_column_int64(stmt, 6), 0))
            let avgSec = max(sqlite3_column_double(stmt, 7), 0.1)
            let okRate = min(max(sqlite3_column_double(stmt, 8), 0), 1)
            let cliFilter: DashboardCLIFilter = kind == "codex" ? .codex : (kind == "claude" ? .claude : .copilot)
            let totalTok = inTok + outTok + cacheTok
            guard runs > 0,
                  !preRavenRows.contains(where: { $0.cliFilter == cliFilter && $0.modelName == model }),
                  !rows.contains(where: { $0.agentName == role && $0.cliFilter == cliFilter && $0.modelName == model }) else { continue }
            let providerName = cliFilter.rawValue
            let cost = computeCostUSD(input: inTok, output: outTok, cache: cacheTok, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
            rows.append(
                AgentRankingRow(
                    id: "raven-rank-\(role)-\(model)", agentName: role, modelName: model,
                    cliFilter: cliFilter, providerName: providerName, runs: runs, totalTokens: totalTok,
                    successRate: okRate, avgDurationSeconds: avgSec, costUSD: cost,
                    detailSummary: DashboardL10n.format(
                        "dashboard.ranking.total_detail_format", "%@ (%@) · Total %@ tok · %lld runs",
                        providerName, model, DashboardTokenFormatter.compact(totalTok), runs
                    ),
                    recentIssue: nil
                )
            )
        }
    }

    private static func appendCopilotSessionRankingRows(
        _ rows: inout [AgentRankingRow], copilotURL: URL, safeDate: String
    ) {
        guard let db = openReadOnlySQLite(path: copilotURL.path) else { return }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT
            CASE WHEN s.summary LIKE 'Load /team-lead%' THEN 'M1 · Steering (TL)'
                 WHEN s.summary LIKE '%Task Writer%' OR s.summary LIKE '%Leaf Writer%' THEN 'M1 · Writer'
                 WHEN s.summary LIKE '%Reviewer brief%' THEN 'M1 · Reviewer'
                 WHEN s.summary LIKE '%PR Monitor%' OR e.model LIKE '%flash%' THEN 'M1 · PR Monitor'
                 ELSE 'M2 · Terminal CLI' END as role_group,
            COALESCE(NULLIF(e.copilot_usage_model, ''), NULLIF(e.model, ''), 'default') as effective_model,
            COUNT(*) as runs,
            SUM(MAX(0, COALESCE(e.input_tokens,0)-COALESCE(e.cache_read_tokens,0)-COALESCE(e.cache_write_tokens,0))
                + COALESCE(e.output_tokens,0) + COALESCE(e.cache_read_tokens,0) + COALESCE(e.cache_write_tokens,0)) as total_tok,
            AVG(COALESCE(e.duration_ms, 8500)) / 1000.0,
            1.0 * SUM(CASE WHEN COALESCE(e.finish_reason, '') != 'error' THEN 1 ELSE 0 END) / COUNT(*),
            COUNT(DISTINCT e.session_id || '-' || COALESCE(e.turn_index, 0)) as turns
        FROM assistant_usage_events e
        LEFT JOIN sessions s ON e.session_id = s.id
        WHERE date(e.created_at, 'localtime') = '\(safeDate)'
          AND COALESCE(NULLIF(e.copilot_usage_model, ''), NULLIF(e.model, ''), '') NOT LIKE 'group/%'
        GROUP BY role_group, effective_model
        HAVING total_tok > 0
        ORDER BY runs DESC LIMIT 8;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let role = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "M2 · Terminal CLI"
            let model = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "default"
            let runs = Int(max(sqlite3_column_int64(stmt, 2), 0))
            let totalTok = UInt64(max(sqlite3_column_int64(stmt, 3), 0))
            let avgSec = max(sqlite3_column_double(stmt, 4), 0.5)
            let okRate = min(max(sqlite3_column_double(stmt, 5), 0), 1)
            let turns = Int(max(sqlite3_column_int64(stmt, 6), 1))
            guard runs > 0 else { continue }
            let provider = DashboardCLIFilter.copilot.rawValue
            rows.append(
                AgentRankingRow(
                    id: "copilot-session-\(role)-\(model)", agentName: role, modelName: model,
                    cliFilter: .copilot, providerName: provider, runs: runs, totalTokens: totalTok,
                    successRate: okRate, avgDurationSeconds: avgSec, costUSD: 0,
                    detailSummary: "\(role) · \(model) (\(provider)) · \(turns) turns / \(runs) API calls · \(DashboardTokenFormatter.compact(totalTok)) tok",
                    recentIssue: nil
                )
            )
        }
    }

    static func appendCindyRankingRows(
        _ rows: inout [AgentRankingRow], cindyDirURL: URL, safeDate: String
    ) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cindyDirURL, includingPropertiesForKeys: nil),
              let dbURL = files.first(where: { $0.lastPathComponent.hasPrefix("cindy-") && $0.pathExtension == "db" }),
              let db = openReadOnlySQLite(path: dbURL.path) else { return }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT
            CASE WHEN s.source = 'bot' THEN 'M2 · Cindy Bot (' || COALESCE(NULLIF(s.title, ''), 'Bot') || ')'
                 ELSE 'M2 · Cindy Desktop' END as role_label,
            COALESCE(NULLIF(s.model, ''), 'default') as model_name,
            COALESCE(NULLIF(s.agent_kind, ''), 'pi') as agent_kind,
            SUM(COALESCE(u.tokens, 0)) as total_tok,
            SUM(MAX(COALESCE((SELECT COUNT(*) FROM messages m WHERE m.session_id = s.id AND m.role = 'assistant'), 1), 1)) as calls
        FROM daily_session_usage u
        JOIN sessions s ON u.session_id = s.id
        WHERE u.day = '\(safeDate)'
        GROUP BY role_label, model_name, agent_kind
        HAVING total_tok > 0;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let role = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "M2 · Cindy"
            let rawModel = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "default"
            let model = rawModel.split(separator: "#").first.map(String.init) ?? rawModel
            let kind = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "pi"
            let totalTok = UInt64(max(sqlite3_column_int64(stmt, 3), 0))
            let calls = Int(max(sqlite3_column_int64(stmt, 4), 1))
            let cli: DashboardCLIFilter = kind.contains("codex") ? .codex : (kind.contains("claude") || kind == "cc" ? .claude : .copilot)
            rows.append(
                AgentRankingRow(
                    id: "cindy-\(role)-\(model)", agentName: role, modelName: model,
                    cliFilter: cli, providerName: cli.rawValue, runs: calls, totalTokens: totalTok,
                    successRate: 1.0, avgDurationSeconds: 6.5, costUSD: 0,
                    detailSummary: "\(role) · \(model) · \(calls) turns · \(DashboardTokenFormatter.compact(totalTok)) tok",
                    recentIssue: nil
                )
            )
        }
    }

    private static func appendFallbackChannelRows(
        _ rows: inout [AgentRankingRow], fallbackEntries: [CLICostQuotaEntry]
    ) {
        for entry in fallbackEntries where entry.interactionCount > 0 && entry.totalTokens > 0 {
            let existingTok = rows.filter { $0.cliFilter == entry.cliFilter }.reduce(UInt64(0)) { $0 + $1.totalTokens }
            guard existingTok == 0 else { continue }
            let roleLabel = entry.cliFilter == .kimi ? "M1 · Reviewer / Research" : (entry.cliFilter == .claude ? "M1 · Steering (Claude)" : "M2 · Dispatcher (CLI)")
            rows.append(
                AgentRankingRow(
                    id: "direct-rank-\(entry.id)", agentName: roleLabel, modelName: entry.modelTag,
                    cliFilter: entry.cliFilter, providerName: entry.displayName,
                    runs: Int(entry.interactionCount), totalTokens: entry.totalTokens,
                    successRate: entry.health == .critical ? 0.94 : 0.99, avgDurationSeconds: 8.4, costUSD: entry.todayCostUSD,
                    detailSummary: DashboardL10n.format(
                        "dashboard.ranking.total_detail_format", "%@ (%@) · Total %@ tok · %lld runs",
                        entry.displayName, entry.modelTag, DashboardTokenFormatter.compact(entry.totalTokens), Int(entry.interactionCount)
                    ),
                    recentIssue: nil
                )
            )
        }
    }

    public typealias SkillsRoiSnapshot = SkillsRoiReport

    public struct LiveEfficiencySummary: Sendable, Equatable {
        public var r1ReviewFailRate: Double = 0
        public var reviewedTasksCount: Int = 0
        public var round3PlusCount: Int = 0
        public var p90TTFTSeconds: Double = 0
        public var cacheHitRate: Double = 0
        public var steeringTokenShare: Double = 0
        public var skillsROI: SkillsRoiSnapshot?
        public var agentEfficiency: AgentEfficiencyWorkbenchSnapshot?
    }

    public static func loadLiveEfficiencySummary(homeURL: URL? = nil) -> LiveEfficiencySummary? {
        guard isLiveEnvironment || homeURL != nil else { return nil }
        let home = homeURL ?? LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
        let whURL = home.appendingPathComponent("Development/AIDash/aidata/L3_merge/warehouse.db")
        let magpieURL = home.appendingPathComponent(".config/magpie/usage.jsonl")
        let skillsURL = home.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest/skills-roi.json")
        let agentEffURL = home.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest/agent-efficiency.json")
        let iCloudJobs = iCloudSyncRootURL(homeURL: home).appendingPathComponent("jobs/aidata-digest", isDirectory: true)
        let iCloudSkillsURL = iCloudJobs.appendingPathComponent("skills-roi.json")
        let iCloudAgentEffURL = iCloudJobs.appendingPathComponent("agent-efficiency.json")
        let cacheKey = "\(fileCacheSignature(for: whURL))|\(fileCacheSignature(for: magpieURL))|\(fileCacheSignature(for: skillsURL))|\(fileCacheSignature(for: agentEffURL))|\(fileCacheSignature(for: iCloudSkillsURL))|\(fileCacheSignature(for: iCloudAgentEffURL))"
        if cachedLiveEfficiencyKey == cacheKey, let cached = cachedLiveEfficiencySummary {
            return cached
        }
        var summary = LiveEfficiencySummary()
        summary.agentEfficiency = loadAgentEfficiencySnapshot(homeURL: home)
        populateMagpieEfficiencySummary(&summary, magpieURL: magpieURL)
        populateWarehouseReviewSummary(&summary, whURL: whURL)
        summary.skillsROI = loadSkillsRoiSnapshot(homeURL: home)
        cachedLiveEfficiencyKey = cacheKey
        cachedLiveEfficiencySummary = summary
        return summary
    }

    public static func loadAgentEfficiencySnapshot(homeURL: URL) -> AgentEfficiencyWorkbenchSnapshot? {
        let url = homeURL.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest/agent-efficiency.json")
        let iCloudURL = iCloudSyncRootURL(homeURL: homeURL).appendingPathComponent("jobs/aidata-digest/agent-efficiency.json")
        guard let data = selectFresherArtifactData(localURL: url, iCloudURL: iCloudURL)?.data else { return nil }
        return try? JSONDecoder().decode(AgentEfficiencyWorkbenchSnapshot.self, from: data)
    }

    public static func loadSkillsRoiSnapshot(homeURL: URL) -> SkillsRoiSnapshot? {
        let url = homeURL.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest/skills-roi.json")
        let iCloudURL = iCloudSyncRootURL(homeURL: homeURL).appendingPathComponent("jobs/aidata-digest/skills-roi.json")
        guard let data = selectFresherArtifactData(localURL: url, iCloudURL: iCloudURL)?.data else { return nil }
        return try? JSONDecoder().decode(SkillsRoiReport.self, from: data)
    }

    public static func managedSkillDetails(in report: SkillsRoiReport) -> [SkillInspectorDetail] {
        report.skillDetails.filter { !$0.isGhost && !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
    }

    private static let allowedSkillPreviewExtensions: Set<String> = [
        "md", "json", "yaml", "yml", "py", "sh", "ts"
    ]
    private static let maxSkillPreviewBytes = 65_536

    public static func loadSkillDocumentPreview(
        skillDir: String,
        relativePath: String,
        skillSlug: String? = nil,
        embeddedPreview: String? = nil,
        homeURL: URL? = nil
    ) -> String? {
        guard isLiveEnvironment || homeURL != nil else { return nil }
        let trimmedSkillDir = skillDir.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSkillDir.isEmpty, !trimmedRelative.isEmpty,
              !trimmedRelative.hasPrefix("/"), !trimmedRelative.contains("\\") else {
            return nil
        }
        let relSegments = trimmedRelative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relSegments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return nil
        }

        let resolvedHome = (homeURL ?? LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL())
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let baseSkillURL: URL
        if trimmedSkillDir == "~" {
            baseSkillURL = resolvedHome
        } else if trimmedSkillDir.hasPrefix("~/") {
            baseSkillURL = resolvedHome.appendingPathComponent(String(trimmedSkillDir.dropFirst(2)), isDirectory: true)
        } else if trimmedSkillDir.hasPrefix("/") {
            baseSkillURL = URL(fileURLWithPath: trimmedSkillDir, isDirectory: true)
        } else {
            return nil
        }

        let trimmedSlug = skillSlug?.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = (trimmedSlug?.isEmpty == false ? trimmedSlug : nil) ?? baseSkillURL.lastPathComponent
        guard !slug.isEmpty, !slug.contains("/"), !slug.contains("\\"), slug != ".", slug != ".." else {
            return nil
        }
        let repoCandidates = (try? FileManager.default.contentsOfDirectory(
            at: resolvedHome.appendingPathComponent("Development", isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.flatMap { repo in
            [
                repo.appendingPathComponent(".agents/skills/\(slug)/\(trimmedRelative)"),
                repo.appendingPathComponent(".claude/skills/\(slug)/\(trimmedRelative)"),
            ]
        } ?? []
        let candidates = [
            resolvedHome.appendingPathComponent(".agents/skills/\(slug)/\(trimmedRelative)"),
            resolvedHome.appendingPathComponent(".claude/skills/\(slug)/\(trimmedRelative)"),
            baseSkillURL.appendingPathComponent(trimmedRelative, isDirectory: false),
            resolvedHome.appendingPathComponent("Development/user-skills/skills/\(slug)/\(trimmedRelative)"),
        ] + repoCandidates + [
            iCloudSyncRootURL(homeURL: resolvedHome).appendingPathComponent("skills-mirror/\(slug)/\(trimmedRelative)"),
        ]
        for candidate in candidates {
            if let content = readSkillDocumentPreview(candidate, resolvedHome: resolvedHome) {
                return content
            }
        }
        let embedded = embeddedPreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return embedded.isEmpty ? nil : embedded
    }

    private static func readSkillDocumentPreview(_ candidateURL: URL, resolvedHome: URL) -> String? {
        guard !isCloudDocsPath(candidateURL) else { return nil }
        let candidate = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
        guard !isCloudDocsPath(candidate) else { return nil }
        let ext = candidate.pathExtension.lowercased()
        guard allowedSkillPreviewExtensions.contains(ext),
              isAllowedSkillDocumentURL(candidate, resolvedHome: resolvedHome) else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let handle = try? FileHandle(forReadingFrom: candidate) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxSkillPreviewBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func isAllowedSkillDocumentURL(_ candidateURL: URL, resolvedHome: URL) -> Bool {
        guard !isCloudDocsPath(candidateURL) else { return false }
        let candidatePath = candidateURL.path
        let directRoots = [
            resolvedHome.appendingPathComponent("Development/user-skills/skills", isDirectory: true),
            resolvedHome.appendingPathComponent(".agents/skills", isDirectory: true),
            resolvedHome.appendingPathComponent(".claude/skills", isDirectory: true),
            iCloudSyncRootURL(homeURL: resolvedHome).appendingPathComponent("skills-mirror", isDirectory: true)
        ]
        for root in directRoots {
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            if candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") {
                return true
            }
        }

        let devRoot = resolvedHome.appendingPathComponent("Development", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let devPrefix = devRoot.hasSuffix("/") ? devRoot : devRoot + "/"
        guard candidatePath.hasPrefix(devPrefix) else { return false }
        let remainder = String(candidatePath.dropFirst(devPrefix.count))
        let parts = remainder.split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return false }
        let repoName = parts[0]
        guard !repoName.isEmpty, repoName != ".", repoName != "..", repoName != "worktrees", repoName != "handoff" else {
            return false
        }
        if (parts[1] == ".agents" || parts[1] == ".claude") && parts[2] == "skills" && parts.count >= 5 {
            return true
        }
        if parts[1] == "skills" && parts.count >= 4 {
            return true
        }
        return false
    }

    private static func populateWarehouseReviewSummary(_ summary: inout LiveEfficiencySummary, whURL: URL) {
        guard let db = openReadOnlySQLite(path: whURL.path) else { return }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT COUNT(*), SUM(CASE WHEN r1_fail > 0 OR max_round >= 2 THEN 1 ELSE 0 END), SUM(CASE WHEN max_round >= 3 THEN 1 ELSE 0 END)
        FROM (SELECT goal_id, task_id, MAX(round_no) as max_round, SUM(CASE WHEN round_no = 1 AND v5_verdict = 'FAIL' THEN 1 ELSE 0 END) as r1_fail
              FROM fact_gtt_task_run WHERE role_name IN ('reviewer', 'code_reviewer', 'planner_reviewer') GROUP BY goal_id, task_id);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                let total = Int(max(sqlite3_column_int64(stmt, 0), 0))
                let failed = Int(max(sqlite3_column_int64(stmt, 1), 0))
                summary.reviewedTasksCount = total
                summary.round3PlusCount = Int(max(sqlite3_column_int64(stmt, 2), 0))
                if total > 0 { summary.r1ReviewFailRate = Double(failed) / Double(total) }
            }
        }
        if summary.agentEfficiency == nil {
            summary.agentEfficiency = buildFallbackAgentEfficiency(db: db, summary: summary)
        }
    }

    private static func buildFallbackAgentEfficiency(
        db: OpaquePointer,
        summary: LiveEfficiencySummary
    ) -> AgentEfficiencyWorkbenchSnapshot? {
        let byRole = queryFallbackRoleRows(db: db)
        let dailyPoints = queryFallbackDailyPoints(db: db)
        guard !byRole.isEmpty || !dailyPoints.isEmpty else { return nil }
        let orderedKeys = ["m3", "m2", "m1", "designer", "writer", "reviewer", "explorer", "pr_monitor"]
        let roles = orderedKeys.map { key in
            byRole[key] ?? AgentRoleEfficiencyRow(
                roleKey: key,
                roleLabel: defaultRoleLabelZh(for: key),
                roleLabelEn: defaultRoleLabelEn(for: key)
            )
        }
        let execRoles = roles.filter { ["writer", "reviewer", "designer"].contains($0.roleKey) }
        let r1Sum = execRoles.reduce(0) { $0 + $1.r1Count }
        let r2Sum = execRoles.reduce(0) { $0 + $1.r2Count }
        let r3Sum = execRoles.reduce(0) { $0 + $1.r3PlusCount }
        let evalTotal = r1Sum + r2Sum + r3Sum
        let fallbackPass = summary.reviewedTasksCount > 0 ? max(0, 1.0 - summary.r1ReviewFailRate) : nil
        let roundSummary = AgentRoundDistributionSummary(
            r1Count: r1Sum,
            r2Count: r2Sum,
            r3PlusCount: r3Sum,
            evaluatedTasks: evalTotal,
            r1PassRate: evalTotal > 0 ? Double(r1Sum) / Double(evalTotal) : fallbackPass,
            steeringTokenShare: summary.steeringTokenShare > 0 ? summary.steeringTokenShare : nil,
            ttftP90Sec: summary.p90TTFTSeconds > 0 ? summary.p90TTFTSeconds : nil,
            cacheHitRate: summary.cacheHitRate > 0 ? summary.cacheHitRate : nil
        )
        let sampleSize = max(
            roles.reduce(0) { $0 + $1.runsCount },
            dailyPoints.reduce(0) { $0 + $1.tasksCompleted }
        )
        return AgentEfficiencyWorkbenchSnapshot(
            schemaVersion: 1,
            windowCST: "14d",
            windowStart: dailyPoints.first?.day,
            windowEnd: dailyPoints.last?.day,
            sourceAsOf: dailyPoints.last?.day,
            sampleSize: sampleSize,
            coverageStatus: sampleSize > 0 ? "partial" : "unknown",
            roles: roles,
            roundSummary: roundSummary,
            dailySeries: dailyPoints
        )
    }

    private static func queryFallbackRoleRows(db: OpaquePointer) -> [String: AgentRoleEfficiencyRow] {
        let roleSQL = """
        SELECT
            CASE
                WHEN lower(role_name) IN ('m3', 'm3_assistant') THEN 'm3'
                WHEN lower(role_name) IN ('m2', 'm2_dispatcher', 'dispatcher') THEN 'm2'
                WHEN lower(role_name) LIKE '%steering%' OR lower(role_name) IN ('m1', 'planner', 'team_lead') THEN 'm1'
                WHEN lower(role_name) LIKE '%designer%' THEN 'designer'
                WHEN lower(role_name) LIKE '%reviewer%' THEN 'reviewer'
                WHEN lower(role_name) LIKE '%explorer%' THEN 'explorer'
                WHEN lower(role_name) LIKE '%pr_monitor%' OR lower(role_name) LIKE '%pr monitor%' OR lower(role_name) = 'prmon' THEN 'pr_monitor'
                ELSE 'writer'
            END AS rkey,
            COUNT(*), COUNT(DISTINCT goal_uid), COUNT(DISTINCT goal_uid || ':' || task_id),
            SUM(CASE WHEN round_no IN (1, 10) AND COALESCE(UPPER(v5_verdict), '') != 'FAIL' THEN 1 ELSE 0 END),
            SUM(CASE WHEN round_no = 2 OR (round_no = 1 AND COALESCE(UPPER(v5_verdict), '') = 'FAIL') THEN 1 ELSE 0 END),
            SUM(CASE WHEN round_no >= 3 AND round_no != 10 THEN 1 ELSE 0 END)
        FROM fact_gtt_task_run GROUP BY rkey;
        """
        var byRole: [String: AgentRoleEfficiencyRow] = [:]
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, roleSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else { return byRole }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let keyPtr = sqlite3_column_text(stmt, 0) else { continue }
            let key = String(cString: keyPtr)
            let runs = Int(max(sqlite3_column_int64(stmt, 1), 0))
            let goals = Int(max(sqlite3_column_int64(stmt, 2), 0))
            let tasks = Int(max(sqlite3_column_int64(stmt, 3), 0))
            let r1 = Int(max(sqlite3_column_int64(stmt, 4), 0))
            let r2 = Int(max(sqlite3_column_int64(stmt, 5), 0))
            let r3p = Int(max(sqlite3_column_int64(stmt, 6), 0))
            let evalTotal = r1 + r2 + r3p
            byRole[key] = AgentRoleEfficiencyRow(
                roleKey: key,
                roleLabel: defaultRoleLabelZh(for: key),
                roleLabelEn: defaultRoleLabelEn(for: key),
                runsCount: runs,
                goalsCount: goals,
                tasksCount: tasks,
                r1Count: r1,
                r2Count: r2,
                r3PlusCount: r3p,
                r1PassRate: evalTotal > 0 ? Double(r1) / Double(evalTotal) : nil
            )
        }
        return byRole
    }

    private static func queryFallbackDailyPoints(db: OpaquePointer) -> [AgentDailyEfficiencyPoint] {
        let dailySQL = """
        SELECT cst_day,
               COUNT(DISTINCT CASE WHEN evt_type IN ('GOAL_DONE', 'PR_MERGED') THEN goal_uid END),
               COUNT(DISTINCT CASE WHEN evt_type IN ('DONE', 'TASK_DONE', 'REVIEW_PASS') AND task_id IS NOT NULL THEN goal_uid || ':' || task_id END),
               SUM(CASE WHEN evt_type IN ('TASK_BLOCKED', 'INPUT_BLOCKED', 'NEED_GO', 'REVIEW_FAIL') THEN 1 ELSE 0 END)
        FROM fact_gtt_event WHERE cst_day IS NOT NULL
        GROUP BY cst_day ORDER BY cst_day DESC LIMIT 14;
        """
        var dailyPoints: [AgentDailyEfficiencyPoint] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, dailySQL, -1, &stmt, nil) == SQLITE_OK, let stmt else { return dailyPoints }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let dayPtr = sqlite3_column_text(stmt, 0) else { continue }
            let day = String(cString: dayPtr)
            let goals = Int(max(sqlite3_column_int64(stmt, 1), 0))
            let tasks = Int(max(sqlite3_column_int64(stmt, 2), 0))
            let blocked = Int(max(sqlite3_column_int64(stmt, 3), 0))
            dailyPoints.append(
                AgentDailyEfficiencyPoint(
                    day: day,
                    goalsCompleted: goals,
                    tasksCompleted: tasks,
                    r1Count: tasks,
                    r1PassRate: tasks > 0 ? 1.0 : nil,
                    blockedEvents: blocked
                )
            )
        }
        dailyPoints.reverse()
        return dailyPoints
    }

    private static func defaultRoleLabelZh(for key: String) -> String {
        switch key {
        case "m3": return "总控协调"
        case "m2": return "话题编排"
        case "m1": return "Goal 主控 (TL)"
        case "designer": return "视觉设计 (Designer)"
        case "writer": return "编码实现 (Writer)"
        case "reviewer": return "独立审查 (Reviewer)"
        case "explorer": return "代码探查 (Explorer)"
        case "pr_monitor": return "交付监控 (PR Monitor)"
        default: return key
        }
    }

    private static func defaultRoleLabelEn(for key: String) -> String {
        switch key {
        case "m3": return "Top-Level Coordinator"
        case "m2": return "Topic Dispatcher"
        case "m1": return "Goal Lead (TL)"
        case "designer": return "Visual Design (Designer)"
        case "writer": return "Code Implementation (Writer)"
        case "reviewer": return "Independent Review (Reviewer)"
        case "explorer": return "Code Exploration (Explorer)"
        case "pr_monitor": return "Delivery Monitor (PR Monitor)"
        default: return key
        }
    }

    private static func populateMagpieEfficiencySummary(_ summary: inout LiveEfficiencySummary, magpieURL: URL) {
        let text = readTailLines(of: magpieURL)
        guard !text.isEmpty else { return }
        var ttfts: [Int] = [], totalIn: UInt64 = 0, totalCR: UInt64 = 0, totalAll: UInt64 = 0, steeringAll: UInt64 = 0
        for line in text.split(separator: "\n").suffix(2000) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let inT = (obj["in"] as? NSNumber)?.uint64Value ?? 0
            let outT = (obj["out"] as? NSNumber)?.uint64Value ?? 0
            let crT = (obj["cache_read"] as? NSNumber)?.uint64Value ?? 0
            let req = (obj["req"] as? String) ?? (obj["model"] as? String) ?? ""
            let tok = inT + outT + crT
            totalIn += inT; totalCR += crT; totalAll += tok
            if req.contains("steering") { steeringAll += tok }
            if let ttft = (obj["ttft_ms"] as? NSNumber)?.intValue, ttft > 0 { ttfts.append(ttft) }
        }
        if !ttfts.isEmpty {
            ttfts.sort()
            summary.p90TTFTSeconds = Double(ttfts[Int(Double(ttfts.count) * 0.9)]) / 1000.0
        }
        if (totalIn + totalCR) > 0 { summary.cacheHitRate = Double(totalCR) / Double(totalIn + totalCR) }
        if totalAll > 0 { summary.steeringTokenShare = Double(steeringAll) / Double(totalAll) }
    }

    public static func loadLiveImprovementActionItems(
        homeURL: URL? = nil,
        acknowledgedActionIDs: Set<String> = []
    ) -> [DashboardActionItem] {
        guard isLiveEnvironment || homeURL != nil else { return [] }
        let home = homeURL ?? LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
        let sources = JobActionsSources.load(
            home: home,
            jobs: ScheduledPulseRegistry.jobs,
            include: isPersonalJobAction
        ) { url, limit in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: limit) ?? Data()
        }
        // Registered producer output is authoritative. Missing/filtered sources do not
        // reopen local proposals or warehouse work data as a second action writer.
        return mapJobActions(sources.actions, acknowledgedActionIDs: acknowledgedActionIDs)
    }

    private static let personalActionSources: Set<String> = ["Learning", "Linear", "Retro", "retro-loop", "CI Improve", "GTT Blocker", "PR & CI"]
    static func isPersonalJobAction(_ action: JobActionsAction) -> Bool {
        guard !["work", "work-business", "work_only"].contains(action.scope?.lowercased() ?? ""),
              !action.labels.contains(where: { ["work", "work-business", "work_only"].contains($0.lowercased()) }) else { return false }
        return isPersonalAction(source: action.source, title: action.title + " " + action.descriptionMd,
                         ref: [action.ref, action.url].compactMap { $0 }.joined(separator: " "),
                         project: ([action.project, action.scope].compactMap { $0 } + action.labels).joined(separator: " "))
    }

    private static func isPersonalAction(source: String?, title: String, ref: String?, project: String? = nil) -> Bool {
        let haystack = [source, title, ref, project].compactMap { $0?.lowercased() }.joined(separator: " ")
        let workTokens = #"(?<![\p{L}\p{N}])(?:bing|flightbook|ado|teams|mail_inbox|work_teams_bridge)(?![\p{L}\p{N}])"#
        guard !haystack.contains("msft.ghe.com"), haystack.range(of: workTokens, options: .regularExpression) == nil else { return false }
        let normalizedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedRef = ref?.lowercased() ?? ""
        return personalActionSources.contains(normalizedSource)
            || normalizedRef.hasPrefix("learning-topic://")
            || normalizedRef.hasPrefix("knowledge://")
            || normalizedRef.hasPrefix("proposal://")
            || normalizedRef.hasPrefix("skill-roi://")
            || normalizedRef.hasPrefix("retro://")
            || normalizedRef.hasPrefix("linear://")
    }

    public static func parseUnifiedActionItems(
        fromURL actionsURL: URL,
        acknowledgedActionIDs: Set<String> = []
    ) -> [DashboardActionItem] {
        guard let data = try? Data(contentsOf: actionsURL),
              let decoded = try? JobActionsSources.decode(data, jobID: "aidata-digest", include: isPersonalJobAction) else {
            return []
        }
        return mapJobActions(decoded, acknowledgedActionIDs: acknowledgedActionIDs)
    }

    private static func mapJobActions(
        _ actions: [JobActionsAction],
        acknowledgedActionIDs: Set<String>
    ) -> [DashboardActionItem] {
        let mappedItems = actions.compactMap { action -> DashboardActionItem? in
            let isPreviewNoise = action.subCategory?.uppercased() == "EVAL_NOT_WORTHY_PREVIEW"
                && action.worthExtracting == false
            guard !isPreviewNoise else { return nil }
            let status = DashboardActionStatus.from(rawStatus: action.status, isCompleted: false)
            let priority = DashboardActionPriority.from(rawPriority: action.priority)
            let sourceTag = (action.source?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? ""
            guard isPersonalJobAction(action) else { return nil }
            let rawDesc = action.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanSummary = cleanActionDescription(rawDesc, title: action.title, ref: action.ref)
            let urlStr = (action.url?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            let mappedControls = action.controls.compactMap { ctrl -> ScheduledJobActionControl? in
                guard let kind = ScheduledJobActionControlKind(rawValue: ctrl.kind.rawValue) else { return nil }
                return ScheduledJobActionControl(
                    id: ctrl.id,
                    kind: kind,
                    title: ctrl.title,
                    options: ctrl.options,
                    maxLength: ctrl.maxLength
                )
            }
            return DashboardActionItem(
                id: action.id,
                title: action.title,
                summary: cleanSummary.isEmpty ? action.title : cleanSummary,
                sourceTag: sourceTag,
                cliFilter: .all,
                priority: priority,
                status: status,
                isCompleted: status == .done,
                command: nil,
                externalURLString: urlStr,
                backingCardId: "scheduled-pulse/\(action.jobID)",
                backingItemRef: action.ref ?? "\(action.jobID):\(action.id)",
                jobID: ScheduledPulseJobID(rawValue: action.jobID) ?? .aidataDigest,
                controls: mappedControls,
                labels: action.labels,
                project: action.project,
                parentIssueKey: action.parentIssue?.identifier,
                parentIssueTitle: action.parentIssue?.title,
                parentIssueURL: action.parentIssue?.url,
                topicID: action.topicID,
                topicCatalog: loadTopicCatalog(),
                domain: action.domain.flatMap { DashboardActionDomain(rawValue: $0) },
                topicKey: action.topicKey,
                originRef: action.originRef,
                revision: action.revision,
                whyNow: action.whyNow,
                sourceURI: action.sourceURI,
                coverageRefs: action.coverageRefs,
                evidence: action.evidence,
                freshness: action.freshness
            )
        }
        return deduplicatingLinearContainerRows(mappedItems)
    }

    private static func deduplicatingLinearContainerRows(_ items: [DashboardActionItem]) -> [DashboardActionItem] {
        let childParentKeys: Set<String> = Set(items.compactMap { item in
            guard let parentKey = item.parentIssueKey?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  linearIssueKey(for: item) != parentKey else { return nil }
            return parentKey
        })
        guard !childParentKeys.isEmpty else { return items }
        return items.filter { item in
            guard item.isLinearNative,
                  let issueKey = linearIssueKey(for: item),
                  childParentKeys.contains(issueKey) else { return true }
            if issueKey == "TIA-83" { return false }
            return !(issueKey == "TIA-76" || issueKey == "TIA-20") || item.status != .inProgress
        }
    }

    private static func linearIssueKey(for item: DashboardActionItem) -> String? {
        if let ref = item.backingItemRef, ref.lowercased().hasPrefix("linear://") {
            return String(ref.dropFirst("linear://".count)).uppercased()
        }
        if item.id.lowercased().hasPrefix("linear-") {
            return String(item.id.dropFirst("linear-".count)).uppercased()
        }
        return item.displayRefLabel?.uppercased()
    }

    private static func cleanActionDescription(_ raw: String, title: String, ref: String?) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["[triage] ", "[blocked] ", "[in_progress] ", "[done] ", "[todo] "]
            where cleaned.lowercased().hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let ref, ref.hasPrefix("linear://") {
            let issueKey = String(ref.dropFirst("linear://".count))
            if cleaned.hasPrefix("\(issueKey) ") {
                cleaned = String(cleaned.dropFirst(issueKey.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return cleaned
    }

    public static func parsePendingProposals(fromURL proposalsURL: URL) -> [DashboardActionItem] {
        guard let text = try? String(contentsOf: proposalsURL, encoding: .utf8) else { return [] }
        var byId: [String: [String: Any]] = [:], order: [String] = [], items: [DashboardActionItem] = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = (obj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !pid.isEmpty else { continue }
            if byId[pid] == nil { order.append(pid) }
            var merged = byId[pid] ?? [:]
            for (k, v) in obj { merged[k] = v }
            byId[pid] = merged
        }
        for pid in order {
            guard let obj = byId[pid], ((obj["status"] as? String)?.lowercased() ?? "pending") == "pending",
                  let title = obj["title"] as? String, !title.isEmpty else { continue }
            let detail = (obj["detail"] as? String) ?? ""
            let agent = (obj["agent"] as? String) ?? "retro-loop"
            let ref = obj["ref"] as? String
            guard isPersonalAction(source: agent, title: title, ref: ref) else { continue }
            let rawPrio = ((obj["priority"] as? String) ?? "high").lowercased()
            let prio: DashboardActionPriority = rawPrio == "high" ? .p0 : (rawPrio == "medium" ? .p1 : .p2)
            let escaped = title.replacingOccurrences(of: "\"", with: "\\\"")
            items.append(DashboardActionItem(
                id: "proposal-\(pid)", title: title, summary: detail.isEmpty ? "Proposed by \(agent)" : detail,
                sourceTag: agent, cliFilter: .all, priority: prio, isCompleted: false,
                command: "python3 ~/Development/user-skills/skills/team-lead/scripts/linear-sync.py idea --title \"\(escaped)\" --mode auto",
                backingCardId: "proposals", backingItemRef: "proposal://\(pid)"
            ))
        }
        return items
    }

    private static func querySlowCIActionItems(whURL: URL) -> [DashboardActionItem] {
        guard let db = openReadOnlySQLite(path: whURL.path) else { return [] }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT repo_key, job_name, COUNT(*), ROUND(AVG(exec_sec), 0), ROUND(AVG(queue_wait_sec), 0)
        FROM fact_ci_job_run GROUP BY repo_key, job_name
        HAVING COUNT(*) >= 3 AND (AVG(exec_sec) > 600 OR AVG(queue_wait_sec) > 120)
        ORDER BY AVG(exec_sec) + AVG(queue_wait_sec) DESC LIMIT 4;
        """
        var stmt: OpaquePointer?, items: [DashboardActionItem] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let repo = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let job = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard isPersonalAction(source: "CI Improve", title: "\(repo) \(job)", ref: "repo://\(repo)", project: repo) else { continue }
            let runs = Int(sqlite3_column_int64(stmt, 2)), avgExec = Int(sqlite3_column_int64(stmt, 3)), avgWait = Int(sqlite3_column_int64(stmt, 4))
            let execMin = String(format: "%.1fm", Double(avgExec) / 60.0), waitMin = String(format: "%.1fm", Double(avgWait) / 60.0)
            let slug = "\(repo)-\(job)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
            let title = avgExec > 600 ? "CI 超 10m 保底线：\(repo) · \(job) 平均 \(execMin)" : "Runner 排队拥堵：\(repo) · \(job) 平均排队 \(waitMin)"
            items.append(DashboardActionItem(
                id: "ci-improve-\(slug)", title: title,
                summary: "样本 \(runs) 次 · 平均执行 \(execMin) · 平均排队 \(waitMin)。建议启用编译缓存或合并单 Runner 并发 Job。",
                sourceTag: "CI Improve", cliFilter: .all, priority: avgExec > 900 ? .p0 : .p1, isCompleted: false,
                command: "python3 ~/Development/user-skills/skills/retro-loop/scripts/retro_story_engine.py discover"
            ))
        }
        return items
    }

}
#endif
