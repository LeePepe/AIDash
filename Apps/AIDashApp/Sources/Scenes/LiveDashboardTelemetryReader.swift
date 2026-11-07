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
    ) -> (entries: [CLICostQuotaEntry], rankings: [AgentRankingRow])? {
        guard isLiveEnvironment else { return nil }
        let home = LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
        return loadDataset(forDate: dateString, homeURL: home, fallbackUsage: fallbackUsage)
    }

    public static func loadDataset(
        forDate dateString: String,
        homeURL: URL,
        fallbackUsage: CLITokenUsageSnapshot
    ) -> (entries: [CLICostQuotaEntry], rankings: [AgentRankingRow])? {
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

        let weeklyQuotaLabel = DashboardL10n.tr("dashboard.quota.weekly_label", "7d Quota")
        let claudeQuotaLabel = DashboardL10n.tr("dashboard.quota.claude_7d_label", "Pro 7d Quota")

        let entries: [CLICostQuotaEntry] = [
            CLICostQuotaEntry(
                id: "cli-copilot", cliFilter: .copilot, displayName: "Copilot CLI",
                modelTag: copilotSessionStats.modelsSummary.isEmpty ? "gemini-4-argon / gpt-5.6-luna" : copilotSessionStats.modelsSummary,
                todayCostUSD: copilotTodayCost, periodCostUSD: copilotWeekCost, quotaLimitUSD: 100.0,
                activeTokens: copilotDayIn + copilotDayOut, cacheTokens: copilotDayCache,
                interactionCount: copilotDayRuns, isAvailable: true,
                quotaUsedOverride: quotas.cursorWeeklyUsedFraction ?? 0.0, quotaLabel: weeklyQuotaLabel
            ),
            CLICostQuotaEntry(
                id: "cli-codex", cliFilter: .codex, displayName: "Codex CLI",
                modelTag: codexStats.modelsSummary.isEmpty ? "gpt-6.1-sol / gemini-4-argon" : codexStats.modelsSummary,
                todayCostUSD: codexTodayCost, periodCostUSD: codexWeekCost, quotaLimitUSD: 100.0,
                activeTokens: codexStats.dayIn + codexStats.dayOut, cacheTokens: codexStats.dayCache,
                interactionCount: codexStats.dayRuns, isAvailable: true,
                quotaUsedOverride: quotas.cursorWeeklyUsedFraction ?? 0.0, quotaLabel: weeklyQuotaLabel
            ),
            CLICostQuotaEntry(
                id: "cli-claude", cliFilter: .claude, displayName: "Claude Code",
                modelTag: "Claude Pro (5h / 7d)",
                todayCostUSD: claudeTodayCost, periodCostUSD: claudeWeekCost, quotaLimitUSD: 100.0,
                activeTokens: claudeDayIn + claudeDayOut, cacheTokens: claudeDayCache,
                interactionCount: claudeDayRuns, isAvailable: true,
                quotaUsedOverride: quotas.claudeSevenDayUsedFraction ?? 0.0, quotaLabel: claudeQuotaLabel
            )
        ]

        let rankings = queryRealRankings(ravenURL: ravenURL, copilotURL: copilotURL, dateString: dateString, fallbackEntries: entries)
        return (entries, rankings)
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

        if claude7d == nil {
            claude7d = readClaudeFallbackQuota(url: claudeFallbackURL, fallbackUsage: fallbackUsage)
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

    static func openReadOnlySQLite(path: String) -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db {
            sqlite3_busy_timeout(db, 120)
            return db
        }
        if let db { sqlite3_close(db) }
        var uriDB: OpaquePointer?
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        if sqlite3_open_v2("file:\(encoded)?mode=ro&immutable=1", &uriDB, flags | SQLITE_OPEN_URI, nil) == SQLITE_OK, let uriDB {
            return uriDB
        }
        if let uriDB { sqlite3_close(uriDB) }
        return nil
    }

    static func queryRavenCLIStats(dbURL: URL, clientPrefix: String, dateString: String) -> CLIWindowStats {
        guard let db = openReadOnlySQLite(path: dbURL.path) else { return CLIWindowStats() }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = ?1 THEN 1 ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = ?1 THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = ?1 THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = ?1 THEN COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0) ELSE 0 END),
            SUM(COALESCE(input_tokens,0)),
            SUM(COALESCE(output_tokens,0)),
            SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
            GROUP_CONCAT(DISTINCT CASE WHEN date(timestamp/1000, 'unixepoch', 'localtime') = ?1 AND resolved_model != '' THEN resolved_model ELSE NULL END)
        FROM requests
        WHERE client_name LIKE ?2
          AND timestamp >= (strftime('%s', ?1, '-7 days') * 1000);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            if let stmt { sqlite3_finalize(stmt) }
            return CLIWindowStats()
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (dateString as NSString).utf8String, -1, nil)
        let pattern = "\(clientPrefix)%"
        sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return CLIWindowStats() }
        let models = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
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

    static func queryCopilotSessionStats(dbURL: URL, dateString: String) -> CLIWindowStats {
        guard let db = openReadOnlySQLite(path: dbURL.path) else { return CLIWindowStats() }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT
            SUM(CASE WHEN substr(created_at, 1, 10) = ?1 THEN 1 ELSE 0 END),
            SUM(CASE WHEN substr(created_at, 1, 10) = ?1 THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN substr(created_at, 1, 10) = ?1 THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN substr(created_at, 1, 10) = ?1 THEN COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0) ELSE 0 END),
            SUM(COALESCE(input_tokens,0)),
            SUM(COALESCE(output_tokens,0)),
            SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
            GROUP_CONCAT(DISTINCT CASE WHEN substr(created_at, 1, 10) = ?1 AND model != '' THEN model ELSE NULL END)
        FROM assistant_usage_events
        WHERE substr(created_at, 1, 10) >= date(?1, '-7 days');
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            if let stmt { sqlite3_finalize(stmt) }
            return CLIWindowStats()
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (dateString as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return CLIWindowStats() }
        let models = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
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

    static func queryWarehouseClaudeStats(dbURL: URL, dateString: String) -> CLIWindowStats {
        guard let db = openReadOnlySQLite(path: dbURL.path) else { return CLIWindowStats() }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT
            SUM(CASE WHEN substr(ts, 1, 10) = ?1 THEN 1 ELSE 0 END),
            SUM(CASE WHEN substr(ts, 1, 10) = ?1 THEN COALESCE(input_tokens,0) ELSE 0 END),
            SUM(CASE WHEN substr(ts, 1, 10) = ?1 THEN COALESCE(output_tokens,0) ELSE 0 END),
            SUM(CASE WHEN substr(ts, 1, 10) = ?1 THEN COALESCE(cache_read,0)+COALESCE(cache_creation,0) ELSE 0 END),
            SUM(COALESCE(input_tokens,0)),
            SUM(COALESCE(output_tokens,0)),
            SUM(COALESCE(cache_read,0)+COALESCE(cache_creation,0))
        FROM fact_turn
        WHERE substr(ts, 1, 10) >= date(?1, '-7 days');
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            if let stmt { sqlite3_finalize(stmt) }
            return CLIWindowStats()
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (dateString as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return CLIWindowStats() }
        return CLIWindowStats(
            dayRuns: UInt64(max(sqlite3_column_int64(stmt, 0), 0)),
            dayIn: UInt64(max(sqlite3_column_int64(stmt, 1), 0)),
            dayOut: UInt64(max(sqlite3_column_int64(stmt, 2), 0)),
            dayCache: UInt64(max(sqlite3_column_int64(stmt, 3), 0)),
            weekIn: UInt64(max(sqlite3_column_int64(stmt, 4), 0)),
            weekOut: UInt64(max(sqlite3_column_int64(stmt, 5), 0)),
            weekCache: UInt64(max(sqlite3_column_int64(stmt, 6), 0)),
            modelsSummary: "claude-opus / sonnet"
        )
    }

    static func queryRealRankings(
        ravenURL: URL,
        copilotURL: URL,
        dateString: String,
        fallbackEntries: [CLICostQuotaEntry]
    ) -> [AgentRankingRow] {
        var rows: [AgentRankingRow] = []

        if let db = openReadOnlySQLite(path: ravenURL.path) {
            defer { sqlite3_close(db) }
            let sql = """
            SELECT
                CASE
                    WHEN client_name LIKE 'codex_exec%' THEN 'Codex Worker (codex_exec)'
                    WHEN client_name LIKE 'codex-tui%' THEN 'Codex TUI (Interactive)'
                    WHEN client_name LIKE 'magpie-router%' THEN 'Magpie Router'
                    WHEN client_name LIKE 'magpie%' THEN 'Copilot / Magpie Agent'
                    WHEN client_name LIKE 'claude%' THEN 'Claude Code Agent'
                    ELSE client_name
                END as role_group,
                CASE
                    WHEN client_name LIKE 'codex%' THEN 'codex'
                    WHEN client_name LIKE 'claude%' THEN 'claude'
                    ELSE 'copilot'
                END as cli_kind,
                COALESCE(NULLIF(resolved_model, ''), model),
                COUNT(*) as runs,
                SUM(COALESCE(input_tokens,0)),
                SUM(COALESCE(output_tokens,0)),
                SUM(COALESCE(cache_read_tokens,0)+COALESCE(cache_write_tokens,0)),
                AVG(latency_ms) / 1000.0,
                1.0 * SUM(CASE WHEN status_code BETWEEN 200 AND 299 THEN 1 ELSE 0 END) / COUNT(*)
            FROM requests
            WHERE date(timestamp/1000, 'unixepoch', 'localtime') = ?1
            GROUP BY role_group, resolved_model
            ORDER BY runs DESC
            LIMIT 10;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, (dateString as NSString).utf8String, -1, nil)
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
                    let cost = computeCostUSD(input: inTok, output: outTok, cache: cacheTok, inRate: 1.25, outRate: 10.0, cacheRate: 0.125)
                    rows.append(
                        AgentRankingRow(
                            id: "real-rank-\(index)-\(role)-\(model)",
                            agentName: "\(role) · \(model)",
                            cliFilter: cliFilter,
                            providerName: providerName,
                            runs: runs,
                            totalTokens: inTok + outTok + cacheTok,
                            successRate: okRate,
                            avgDurationSeconds: avgSec,
                            costUSD: cost,
                            detailSummary: DashboardL10n.format(
                                "dashboard.ranking.detail_format",
                                "%@ (%@) · Active %@ tok · Cache %@ tok",
                                providerName,
                                model,
                                (inTok + outTok).formatted(.number),
                                cacheTok.formatted(.number)
                            ),
                            recentIssue: nil
                        )
                    )
                    index += 1
                }
            }
        }

        if rows.isEmpty {
            return DashboardWorkspaceStore.deriveRankingRows(from: fallbackEntries)
        }
        return rows
    }
}
#endif
