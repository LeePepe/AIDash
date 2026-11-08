#if os(macOS)
import Darwin
import Foundation
import SQLite3

public struct RealQuotaSnapshot: Sendable, Equatable {
    public let claudeSevenDayUsedFraction: Double?
    public let claudeFiveHourUsedFraction: Double?
    public let cursorWeeklyUsedFraction: Double?
    public let grokSevenDayUsedFraction: Double?

    public init(
        claudeSevenDayUsedFraction: Double? = nil,
        claudeFiveHourUsedFraction: Double? = nil,
        cursorWeeklyUsedFraction: Double? = nil,
        grokSevenDayUsedFraction: Double? = nil
    ) {
        self.claudeSevenDayUsedFraction = claudeSevenDayUsedFraction
        self.claudeFiveHourUsedFraction = claudeFiveHourUsedFraction
        self.cursorWeeklyUsedFraction = cursorWeeklyUsedFraction
        self.grokSevenDayUsedFraction = grokSevenDayUsedFraction
    }
}

@MainActor
public enum LiveDashboardTelemetryReader {
    public static var isLiveEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    public static func loadLiveDataset(
        forDate dateString: String,
        fallbackUsage: CLITokenUsageSnapshot
    ) -> (entries: [CLICostQuotaEntry], rankings: [AgentRankingRow], trends: [TrendDataPoint])? {
        guard isLiveEnvironment else { return nil }
        let home = LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
        return loadDataset(forDate: dateString, homeURL: home, fallbackUsage: fallbackUsage)
    }

    public static func loadDataset(
        forDate dateString: String,
        homeURL: URL,
        fallbackUsage: CLITokenUsageSnapshot
    ) -> (entries: [CLICostQuotaEntry], rankings: [AgentRankingRow], trends: [TrendDataPoint])? {
        let ravenURL = homeURL.appendingPathComponent("Library/Application Support/raven/raven.db")
        let copilotURL = homeURL.appendingPathComponent(".copilot/session-store.db")
        let warehouseURL = homeURL.appendingPathComponent("Development/AIDash/aidata/L3_merge/warehouse.db")
        let quotasURL = homeURL.appendingPathComponent(".config/magpie/quotas.json")
        let claudeQuotaURL = homeURL.appendingPathComponent(".config/claude/gtt-weekly-remaining-pct.json")

        let quotas = readQuotas(magpieQuotasURL: quotasURL, claudeFallbackURL: claudeQuotaURL, fallbackUsage: fallbackUsage)

        let codexStats = queryRavenCLIStats(dbURL: ravenURL, clientPrefix: "codex", dateString: dateString)
        let copilotSessionStats = queryCopilotSessionStats(dbURL: copilotURL, dateString: dateString)
        let copilotRavenStats = queryRavenCLIStats(dbURL: ravenURL, clientPrefix: "magpie", dateString: dateString)
        let claudeRavenStats = queryRavenCLIStats(dbURL: ravenURL, clientPrefix: "claude", dateString: dateString)
        let claudeWarehouseStats = queryWarehouseClaudeStats(dbURL: warehouseURL, dateString: dateString)

        let hasAnyDatabase = FileManager.default.fileExists(atPath: ravenURL.path)
            || FileManager.default.fileExists(atPath: copilotURL.path)
            || FileManager.default.fileExists(atPath: warehouseURL.path)
        guard hasAnyDatabase else { return nil }

        let claudeDayIn = claudeRavenStats.dayIn + claudeWarehouseStats.dayIn
        let claudeDayOut = claudeRavenStats.dayOut + claudeWarehouseStats.dayOut
        let claudeDayCache = claudeRavenStats.dayCache + claudeWarehouseStats.dayCache
        let claudeDayRuns = claudeRavenStats.dayRuns + claudeWarehouseStats.dayRuns
        let claudeWeekIn = claudeRavenStats.weekIn + claudeWarehouseStats.weekIn
        let claudeWeekOut = claudeRavenStats.weekOut + claudeWarehouseStats.weekOut
        let claudeWeekCache = claudeRavenStats.weekCache + claudeWarehouseStats.weekCache

        let claudeTodayCost = computeCostUSD(input: claudeDayIn, output: claudeDayOut, cache: claudeDayCache, inRate: 3.0, outRate: 15.0, cacheRate: 0.30)
        let claudeWeekCost = computeCostUSD(input: claudeWeekIn, output: claudeWeekOut, cache: claudeWeekCache, inRate: 3.0, outRate: 15.0, cacheRate: 0.30)

        let codexTodayCost = computeCostUSD(input: codexStats.dayIn, output: codexStats.dayOut, cache: codexStats.dayCache, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
        let codexWeekCost = computeCostUSD(input: codexStats.weekIn, output: codexStats.weekOut, cache: codexStats.weekCache, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)

        let useCopilotRaven = copilotSessionStats.dayRuns == 0 && copilotRavenStats.dayRuns > 0
        let copilotDayIn = useCopilotRaven ? copilotRavenStats.dayIn : copilotSessionStats.dayIn
        let copilotDayOut = useCopilotRaven ? copilotRavenStats.dayOut : copilotSessionStats.dayOut
        let copilotDayCache = useCopilotRaven ? copilotRavenStats.dayCache : copilotSessionStats.dayCache
        let copilotDayRuns = useCopilotRaven ? copilotRavenStats.dayRuns : copilotSessionStats.dayRuns
        let copilotWeekIn = max(copilotSessionStats.weekIn, copilotRavenStats.weekIn)
        let copilotWeekOut = max(copilotSessionStats.weekOut, copilotRavenStats.weekOut)
        let copilotWeekCache = max(copilotSessionStats.weekCache, copilotRavenStats.weekCache)

        let copilotTodayCost = computeCostUSD(input: copilotDayIn, output: copilotDayOut, cache: copilotDayCache, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
        let copilotWeekCost = computeCostUSD(input: copilotWeekIn, output: copilotWeekOut, cache: copilotWeekCache, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)

        let copilotWeekTotal = copilotWeekIn + copilotWeekOut + copilotWeekCache
        let codexWeekTotal = codexStats.weekIn + codexStats.weekOut + codexStats.weekCache
        let claudeWeekTotal = claudeWeekIn + claudeWeekOut + claudeWeekCache
        let kimiStats = queryKimiStats(homeURL: homeURL, dateString: dateString)

        let weeklyQuotaLabel = DashboardL10n.tr("dashboard.quota.weekly_label", "7d Quota")
        let claudeQuotaLabel = DashboardL10n.tr("dashboard.quota.claude_7d_label", "Pro 7d Quota")

        let entries: [CLICostQuotaEntry] = [
            CLICostQuotaEntry(
                id: "cli-claude", cliFilter: .claude, displayName: "Claude Code",
                modelTag: "Claude Pro (5h / 7d)",
                todayCostUSD: claudeTodayCost, periodCostUSD: claudeWeekCost, quotaLimitUSD: 100.0,
                activeTokens: claudeDayIn + claudeDayOut, cacheTokens: claudeDayCache,
                interactionCount: claudeDayRuns, isAvailable: true,
                quotaUsedOverride: quotas.claudeSevenDayUsedFraction ?? 0.0,
                quotaLabel: claudeQuotaLabel, periodTotalTokens: claudeWeekTotal
            ),
            CLICostQuotaEntry(
                id: "cli-codex", cliFilter: .codex, displayName: "Codex CLI",
                modelTag: codexStats.modelsSummary.isEmpty ? "gpt-6.1-sol / gemini-4-argon" : codexStats.modelsSummary,
                todayCostUSD: codexTodayCost, periodCostUSD: codexWeekCost, quotaLimitUSD: 100.0,
                activeTokens: codexStats.dayIn + codexStats.dayOut, cacheTokens: codexStats.dayCache,
                interactionCount: codexStats.dayRuns, isAvailable: true,
                quotaUsedOverride: quotas.cursorWeeklyUsedFraction ?? 0.0,
                quotaLabel: weeklyQuotaLabel, periodTotalTokens: codexWeekTotal
            ),
            CLICostQuotaEntry(
                id: "cli-kimi", cliFilter: .kimi, displayName: "Kimi CLI",
                modelTag: "kimi-code/k3",
                todayCostUSD: 0.0, periodCostUSD: 0.0, quotaLimitUSD: 100.0,
                activeTokens: kimiStats.dayTokens, cacheTokens: 0,
                interactionCount: kimiStats.dayRuns, isAvailable: true,
                quotaUsedOverride: kimiStats.quotaUsedFraction,
                quotaLabel: weeklyQuotaLabel, periodTotalTokens: kimiStats.weekTokens
            ),
            CLICostQuotaEntry(
                id: "cli-copilot", cliFilter: .copilot, displayName: "Copilot CLI",
                modelTag: copilotSessionStats.modelsSummary.isEmpty ? "gemini-4-argon / gpt-5.6-luna" : copilotSessionStats.modelsSummary,
                todayCostUSD: copilotTodayCost, periodCostUSD: copilotWeekCost, quotaLimitUSD: 100.0,
                activeTokens: copilotDayIn + copilotDayOut, cacheTokens: copilotDayCache,
                interactionCount: copilotDayRuns, isAvailable: true,
                quotaUsedOverride: 0.0,
                quotaLabel: nil, periodTotalTokens: copilotWeekTotal
            )
        ]

        let rankings = queryRealRankings(ravenURL: ravenURL, copilotURL: copilotURL, dateString: dateString, fallbackEntries: entries)
        let trends = querySevenDayTrends(
            ravenURL: ravenURL,
            copilotURL: copilotURL,
            dateString: dateString,
            kimiDailyBuckets: kimiStats.dailyBuckets,
            fallbackEntries: entries
        )
        return (entries, rankings, trends)
    }

    private static func computeCostUSD(
        input: UInt64,
        output: UInt64,
        cache: UInt64,
        inRate: Double,
        outRate: Double,
        cacheRate: Double
    ) -> Double {
        let inCost = (Double(input) / 1_000_000.0) * inRate
        let outCost = (Double(output) / 1_000_000.0) * outRate
        let cacheCost = (Double(cache) / 1_000_000.0) * cacheRate
        return inCost + outCost + cacheCost
    }

    public static func readQuotas(
        magpieQuotasURL: URL,
        claudeFallbackURL: URL,
        fallbackUsage: CLITokenUsageSnapshot
    ) -> RealQuotaSnapshot {
        var claude7d: Double?
        var claude5h: Double?
        var cursorWeekly: Double?
        var grok7d: Double?

        if let data = try? Data(contentsOf: magpieQuotasURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, val) in root {
                let windows = extractWindows(from: val)
                if key.hasPrefix("claude") {
                    claude7d = windowUsedFraction(in: windows, matching: "7 day") ?? claude7d
                    claude5h = windowUsedFraction(in: windows, matching: "5 hour") ?? claude5h
                } else if key.hasPrefix("cursor") {
                    cursorWeekly = windowUsedFraction(in: windows, matching: "Weekly") ?? cursorWeekly
                } else if key.hasPrefix("grok") {
                    grok7d = windowUsedFraction(in: windows, matching: nil) ?? grok7d
                }
            }
        }

        if let fallbackClaude = readClaudeFallbackQuota(url: claudeFallbackURL, fallbackUsage: fallbackUsage) {
            claude7d = max(claude7d ?? 0, fallbackClaude)
        }

        return RealQuotaSnapshot(
            claudeSevenDayUsedFraction: claude7d,
            claudeFiveHourUsedFraction: claude5h,
            cursorWeeklyUsedFraction: cursorWeekly,
            grokSevenDayUsedFraction: grok7d
        )
    }

    private static func extractWindows(from rawEntry: Any) -> [[String: Any]] {
        guard let entry = rawEntry as? [String: Any],
              let quota = entry["quota"] as? [String: Any],
              let windows = quota["windows"] as? [[String: Any]] else { return [] }
        return windows
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

    private static func readClaudeFallbackQuota(url: URL, fallbackUsage: CLITokenUsageSnapshot) -> Double? {
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let used = (obj["used_percentage"] as? NSNumber)?.doubleValue {
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
            SUM(COALESCE(input_tokens,0)), SUM(COALESCE(output_tokens,0)),
            SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
            GROUP_CONCAT(DISTINCT CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = '\(safeDate)' AND resolved_model != '' THEN resolved_model ELSE NULL END)
        FROM requests WHERE client_name LIKE '\(safePrefix)%' AND timestamp >= (strftime('%s', '\(safeDate)', '-7 days') * 1000);
        """
        return executeWindowStatsQuery(dbURL: dbURL, sql: sql)
    }

    static func queryCopilotSessionStats(dbURL: URL, dateString: String) -> CLIWindowStats {
        let safeDate = sanitizeSQLToken(dateString)
        let sql = """
        SELECT
            SUM(CASE WHEN substr(created_at, 1, 10) = '\(safeDate)' THEN 1 ELSE 0 END),
            SUM(CASE WHEN substr(created_at, 1, 10) = '\(safeDate)' THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN substr(created_at, 1, 10) = '\(safeDate)' THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN substr(created_at, 1, 10) = '\(safeDate)' THEN COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0) ELSE 0 END),
            SUM(COALESCE(input_tokens,0)), SUM(COALESCE(output_tokens,0)),
            SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
            GROUP_CONCAT(DISTINCT CASE WHEN substr(created_at, 1, 10) = '\(safeDate)' AND model != '' THEN model ELSE NULL END)
        FROM assistant_usage_events WHERE substr(created_at, 1, 10) >= date('\(safeDate)', '-7 days');
        """
        return executeWindowStatsQuery(dbURL: dbURL, sql: sql)
    }

    static func queryWarehouseClaudeStats(dbURL: URL, dateString: String) -> CLIWindowStats {
        let safeDate = sanitizeSQLToken(dateString)
        let sql = """
        SELECT
            SUM(CASE WHEN substr(ts, 1, 10) = '\(safeDate)' THEN 1 ELSE 0 END),
            SUM(CASE WHEN substr(ts, 1, 10) = '\(safeDate)' THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN substr(ts, 1, 10) = '\(safeDate)' THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN substr(ts, 1, 10) = '\(safeDate)' THEN COALESCE(cache_read,0)+COALESCE(cache_creation,0) ELSE 0 END),
            SUM(COALESCE(input_tokens,0)), SUM(COALESCE(output_tokens,0)),
            SUM(COALESCE(cache_read,0)+COALESCE(cache_creation,0))
        FROM fact_turn WHERE substr(ts, 1, 10) >= date('\(safeDate)', '-7 days');
        """
        return executeWindowStatsQuery(dbURL: dbURL, sql: sql, hasModelsColumn: false, defaultModels: "claude-opus / sonnet")
    }

    struct KimiTelemetryStats {
        var dayTokens: UInt64 = 0
        var dayRuns: UInt64 = 0
        var weekTokens: UInt64 = 0
        var quotaUsedFraction: Double = 0.0
        var dailyBuckets: [String: (tokens: UInt64, runs: Int)] = [:]
    }

    private static var cachedKimiKey: String?
    private static var cachedKimiStats: KimiTelemetryStats?

    static func queryKimiStats(homeURL: URL, dateString: String) -> KimiTelemetryStats {
        let kimiRoot = homeURL.appendingPathComponent(".kimi-code")
        let indexURL = kimiRoot.appendingPathComponent("session_index.jsonl")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: indexURL.path),
              let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 else {
            return KimiTelemetryStats()
        }
        let cacheKey = "\(dateString)-\(Int(mtime))"
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
            if wireText.contains("APIProviderQuotaExhaustedError") {
                latestExhaustedTs = max(latestExhaustedTs, wMtime)
            } else if wireText.contains("\"prompt.completed\"") {
                latestCompletedTs = max(latestCompletedTs, wMtime)
            }
            for wLine in wireText.split(separator: "\n") where wLine.contains("token_counting.turn_recorded") {
                guard let wData = wLine.data(using: .utf8),
                      let rec = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
                      let tok = (rec["tokens"] as? NSNumber)?.uint64Value,
                      let tsMs = (rec["time"] as? NSNumber)?.doubleValue else { continue }
                let sec = tsMs / 1000.0
                guard sec >= cutoffSec && sec <= endSec else { continue }
                let dayStr = fmt.string(from: Date(timeIntervalSince1970: sec))
                let prev = buckets[dayStr] ?? (0, 0)
                buckets[dayStr] = (prev.tokens + tok, prev.runs + 1)
            }
        }

        let dayStat = buckets[dateString] ?? (0, 0)
        let weekTok = buckets.values.reduce(UInt64(0)) { $0 + $1.tokens }
        let isExhausted = latestExhaustedTs > 0 && latestExhaustedTs >= latestCompletedTs
        let quotaFraction = isExhausted ? 1.0 : min(Double(weekTok) / 6_200_000.0, 0.99)
        let stats = KimiTelemetryStats(
            dayTokens: dayStat.tokens,
            dayRuns: UInt64(dayStat.runs),
            weekTokens: weekTok,
            quotaUsedFraction: quotaFraction,
            dailyBuckets: buckets
        )
        cachedKimiKey = cacheKey
        cachedKimiStats = stats
        return stats
    }

    static func querySevenDayTrends(
        ravenURL: URL,
        copilotURL: URL,
        dateString: String,
        kimiDailyBuckets: [String: (tokens: UInt64, runs: Int)] = [:],
        fallbackEntries: [CLICostQuotaEntry]
    ) -> [TrendDataPoint] {
        let safeDate = sanitizeSQLToken(dateString)
        var dailyMap: [String: [DashboardCLIFilter: (tokens: UInt64, runs: Int)]] = [:]
        for (day, stat) in kimiDailyBuckets where stat.tokens > 0 {
            var dayDict = dailyMap[day, default: [:]]
            dayDict[.kimi] = stat
            dailyMap[day] = dayDict
        }

        if let db = openReadOnlySQLite(path: ravenURL.path) {
            defer { sqlite3_close(db) }
            let sql = """
            SELECT
                date(timestamp/1000, 'unixepoch', 'localtime') as d,
                CASE
                    WHEN client_name LIKE 'codex%' THEN 'codex'
                    WHEN client_name LIKE 'claude%' THEN 'claude'
                    ELSE 'copilot'
                END as cli_kind,
                SUM(COALESCE(input_tokens,0)+COALESCE(output_tokens,0)+COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
                COUNT(*)
            FROM requests
            WHERE timestamp >= (strftime('%s', '\(safeDate)', '-6 days') * 1000)
              AND date(timestamp/1000, 'unixepoch', 'localtime') <= '\(safeDate)'
            GROUP BY d, cli_kind;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let dayPtr = sqlite3_column_text(stmt, 0),
                          let kindPtr = sqlite3_column_text(stmt, 1) else { continue }
                    let day = String(cString: dayPtr)
                    let kind = String(cString: kindPtr)
                    let tok = UInt64(max(sqlite3_column_int64(stmt, 2), 0))
                    let runs = Int(max(sqlite3_column_int64(stmt, 3), 0))
                    let cli: DashboardCLIFilter = kind == "codex" ? .codex : (kind == "claude" ? .claude : .copilot)
                    var dayDict = dailyMap[day, default: [:]]
                    dayDict[cli] = (tok, runs)
                    dailyMap[day] = dayDict
                }
            }
        }

        if let db = openReadOnlySQLite(path: copilotURL.path) {
            defer { sqlite3_close(db) }
            let sql = """
            SELECT
                substr(created_at, 1, 10) as d,
                SUM(COALESCE(input_tokens,0)+COALESCE(output_tokens,0)+COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
                COUNT(*)
            FROM assistant_usage_events
            WHERE substr(created_at, 1, 10) >= date('\(safeDate)', '-6 days')
              AND substr(created_at, 1, 10) <= '\(safeDate)'
            GROUP BY d;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let dayPtr = sqlite3_column_text(stmt, 0) else { continue }
                    let day = String(cString: dayPtr)
                    let tok = UInt64(max(sqlite3_column_int64(stmt, 1), 0))
                    let runs = Int(max(sqlite3_column_int64(stmt, 2), 0))
                    var dayDict = dailyMap[day, default: [:]]
                    let prev = dayDict[.copilot] ?? (0, 0)
                    dayDict[.copilot] = (max(prev.tokens, tok), max(prev.runs, runs))
                    dailyMap[day] = dayDict
                }
            }
        }

        var points: [TrendDataPoint] = []
        for day in dailyMap.keys.sorted() {
            let shortDay = day.count >= 10 ? String(day.suffix(5)) : day
            guard let cliDict = dailyMap[day] else { continue }
            for cli in [DashboardCLIFilter.copilot, .codex, .claude, .kimi] {
                guard let stat = cliDict[cli], stat.tokens > 0 else { continue }
                points.append(
                    TrendDataPoint(
                        id: "trend-\(day)-\(cli.rawValue)",
                        bucketLabel: shortDay,
                        category: cli.rawValue,
                        cliFilter: cli,
                        invocations: stat.runs,
                        successRate: 0.99,
                        costUSD: 0,
                        totalTokens: stat.tokens
                    )
                )
            }
        }
        return points.isEmpty ? DashboardWorkspaceStore.deriveTrendPoints(from: fallbackEntries) : points
    }

    static func queryRealRankings(
        ravenURL: URL, copilotURL: URL, dateString: String, fallbackEntries: [CLICostQuotaEntry]
    ) -> [AgentRankingRow] {
        var rows: [AgentRankingRow] = []
        if let db = openReadOnlySQLite(path: ravenURL.path) {
            defer { sqlite3_close(db) }
            let safeDate = sanitizeSQLToken(dateString)
            let sql = """
            SELECT
                CASE WHEN client_name LIKE 'codex_exec%' THEN 'Codex Worker (codex_exec)'
                     WHEN client_name LIKE 'codex-tui%' THEN 'Codex TUI (Interactive)'
                     WHEN client_name LIKE 'magpie-router%' THEN 'Magpie Router'
                     WHEN client_name LIKE 'magpie%' THEN 'Copilot / Magpie Agent'
                     WHEN client_name LIKE 'claude%' THEN 'Claude Code Agent'
                     ELSE client_name END as role_group,
                CASE WHEN client_name LIKE 'codex%' THEN 'codex'
                     WHEN client_name LIKE 'claude%' THEN 'claude' ELSE 'copilot' END as cli_kind,
                COALESCE(NULLIF(resolved_model, ''), model), COUNT(*) as runs,
                SUM(COALESCE(input_tokens,0)), SUM(COALESCE(output_tokens,0)),
                SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
                AVG(latency_ms) / 1000.0,
                1.0 * SUM(CASE WHEN status_code BETWEEN 200 AND 299 THEN 1 ELSE 0 END) / COUNT(*)
            FROM requests WHERE date(timestamp/1000, 'unixepoch', 'localtime') = '\(safeDate)'
            GROUP BY role_group, resolved_model ORDER BY runs DESC LIMIT 10;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                var index = 0
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let role = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "Agent"
                    let kind = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "copilot"
                    let model = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "default"
                    let runs = Int(max(sqlite3_column_int64(stmt, 3), 0))
                    let inTok = UInt64(max(sqlite3_column_int64(stmt, 4), 0))
                    let outTok = UInt64(max(sqlite3_column_int64(stmt, 5), 0))
                    let cacheTok = UInt64(max(sqlite3_column_int64(stmt, 6), 0))
                    let avgSec = max(sqlite3_column_double(stmt, 7), 0.1)
                    let okRate = min(max(sqlite3_column_double(stmt, 8), 0), 1)
                    guard runs > 0 else { continue }
                    let cliFilter: DashboardCLIFilter = kind == "codex" ? .codex : (kind == "claude" ? .claude : .copilot)
                    let providerName = cliFilter.rawValue
                    let totalTok = inTok + outTok + cacheTok
                    let cost = computeCostUSD(input: inTok, output: outTok, cache: cacheTok, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
                    rows.append(
                        AgentRankingRow(
                            id: "real-rank-\(index)-\(role)-\(model)", agentName: "\(role) · \(model)",
                            cliFilter: cliFilter, providerName: providerName, runs: runs, totalTokens: totalTok,
                            successRate: okRate, avgDurationSeconds: avgSec, costUSD: cost,
                            detailSummary: DashboardL10n.format(
                                "dashboard.ranking.total_detail_format", "%@ (%@) · Total %@ tok · %lld runs",
                                providerName, model, DashboardTokenFormatter.compact(totalTok), runs
                            ),
                            recentIssue: nil
                        )
                    )
                    index += 1
                }
            }
        }
        return rows.isEmpty ? DashboardWorkspaceStore.deriveRankingRows(from: fallbackEntries) : rows
    }
}
#endif
