#if os(macOS)
import Foundation
import SQLite3
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@Suite("Pew token alignment")
@MainActor
struct PewTokenAlignmentTests {
    private static let cst = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current

    @Test("Copilot inclusive input is de-duplicated and underflow is clamped")
    func copilotInclusiveInputNormalization() throws {
        let database = try SQLiteFixture(schema: """
        CREATE TABLE assistant_usage_events (
            input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_write_tokens INTEGER,
            model TEXT, created_at TEXT
        );
        INSERT INTO assistant_usage_events VALUES (310000, 3000, 300000, 2000, 'gpt-5', '2026-11-22T18:30:00Z');
        INSERT INTO assistant_usage_events VALUES (10, 5, 100, 20, 'gpt-5', '2026-11-23T03:00:00Z');
        INSERT INTO assistant_usage_events VALUES (1000, 100, 50, 25, 'gpt-5', '2026-11-16T18:30:00Z');
        INSERT INTO assistant_usage_events VALUES (9999, 100, 10, 5, 'gpt-5', '2026-11-15T18:30:00Z');
        """)
        defer { database.remove() }

        let stats = LiveDashboardTelemetryReader.queryCopilotSessionStats(
            dbURL: database.url,
            dateString: "2026-11-23",
            timeZone: Self.cst
        )

        #expect(stats.dayRuns == 2)
        #expect(stats.dayIn == 8_000)
        #expect(stats.dayOut == 3_005)
        #expect(stats.dayCache == 302_120)
        #expect(stats.dayIn + stats.dayOut == 11_005)
        #expect(stats.dayIn + stats.dayOut + stats.dayCache == 313_125)
        #expect(stats.weekIn == 8_925)
        #expect(stats.weekOut == 3_105)
        #expect(stats.weekCache == 302_195)
        #expect(stats.weekIn + stats.weekOut + stats.weekCache == 314_225)
    }

    @Test("Raven input remains mutually exclusive from cache tokens")
    func ravenInputIsNotReducedByCache() throws {
        let database = try SQLiteFixture(schema: """
        CREATE TABLE requests (
            timestamp INTEGER, client_name TEXT, input_tokens INTEGER,
            output_tokens INTEGER, cache_read_tokens INTEGER,
            cache_write_tokens INTEGER, resolved_model TEXT
        );
        """)
        defer { database.remove() }
        try database.execute("""
        INSERT INTO requests VALUES (
            \(try Self.epochMilliseconds("2026-11-22T18:30:00Z")), 'codex_exec', 800, 400, 130000, 0, 'gpt-5'
        );
        INSERT INTO requests VALUES (
            \(try Self.epochMilliseconds("2026-11-16T18:30:00Z")), 'codex_exec', 50, 60, 70, 0, 'gpt-5'
        );
        INSERT INTO requests VALUES (
            \(try Self.epochMilliseconds("2026-11-15T18:30:00Z")), 'codex_exec', 900, 900, 900, 0, 'gpt-5'
        );
        """)

        let stats = LiveDashboardTelemetryReader.queryRavenCLIStats(
            dbURL: database.url,
            clientPrefix: "codex",
            dateString: "2026-11-23",
            timeZone: Self.cst
        )

        #expect(stats.dayRuns == 1)
        #expect(stats.dayIn == 800)
        #expect(stats.dayOut == 400)
        #expect(stats.dayCache == 130_000)
        #expect(stats.weekIn == 850)
        #expect(stats.weekOut == 460)
        #expect(stats.weekCache == 130_070)
    }

    @Test("UTC Copilot timestamps bucket into the local CST day")
    func copilotUsesLocalDateForUTCISOString() throws {
        #expect(LiveDashboardTelemetryReader.localDateString(from: "2026-11-22T18:30:00Z", timeZone: Self.cst) == "2026-11-23")
        let database = try SQLiteFixture(schema: """
        CREATE TABLE assistant_usage_events (
            input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_write_tokens INTEGER,
            model TEXT, created_at TEXT
        );
        INSERT INTO assistant_usage_events VALUES (100, 20, 30, 0, 'gpt-5', '2026-11-22T18:30:00Z');
        """)
        defer { database.remove() }

        let stats = LiveDashboardTelemetryReader.queryCopilotSessionStats(dbURL: database.url, dateString: "2026-11-23", timeZone: Self.cst)
        #expect(stats.dayRuns == 1)
        #expect(stats.dayIn == 70)
        #expect(stats.dayOut == 20)
        #expect(stats.dayCache == 30)
    }

    @Test("Seven-day window includes date minus six days but excludes date minus seven days")
    func sevenDayWindowIsInclusiveOfExactlySevenDays() throws {
        let database = try SQLiteFixture(schema: """
        CREATE TABLE fact_turn (
            ts TEXT, input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_creation INTEGER
        );
        INSERT INTO fact_turn VALUES ('2026-11-22T18:30:00Z', 100, 20, 3, 4);
        INSERT INTO fact_turn VALUES ('2026-11-16T18:30:00Z', 200, 30, 5, 6);
        INSERT INTO fact_turn VALUES ('2026-11-15T18:30:00Z', 900, 90, 50, 60);
        """)
        defer { database.remove() }

        let stats = LiveDashboardTelemetryReader.queryWarehouseClaudeStats(dbURL: database.url, dateString: "2026-11-23", timeZone: Self.cst)
        #expect(stats.weekIn == 300)
        #expect(stats.weekOut == 50)
        #expect(stats.weekCache == 18)
        #expect(stats.weekIn + stats.weekOut + stats.weekCache == 368)
    }

    @Test("Menu bar provider filters fact_turn to its explicit local target day")
    @MainActor
    func menuBarTargetDayFilter() throws {
        let database = try SQLiteFixture(schema: """
        CREATE TABLE fact_turn (
            ts TEXT, input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_creation INTEGER
        );
        INSERT INTO fact_turn VALUES ('2026-11-22T18:30:00Z', 10, 20, 3, 4);
        INSERT INTO fact_turn VALUES ('2026-11-21T18:30:00Z', 1000, 2000, 3000, 4000);
        """)
        defer { database.remove() }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Self.cst
        formatter.dateFormat = "yyyy-MM-dd"
        let referenceDate = try #require(formatter.date(from: "2026-11-23"))
        let provider = LiveMenuBarSystemStatusProvider(
            tokenDatabasePaths: CLITokenDatabasePaths(claude: [database.url]),
            referenceDate: referenceDate,
            timeZone: Self.cst,
            ssdMountPath: "/does-not-exist/SSD"
        )

        let result = provider.captureTokenStatus()
        let claude = try #require(result.usage.items.first(where: { $0.cli == .claude }))
        #expect(claude.isAvailable)
        #expect(claude.inputTokens == 10)
        #expect(claude.outputTokens == 20)
        #expect(claude.cacheTokens == 7)
        #expect(claude.interactionCount == 1)
        #expect(MenuBarController.cliTokenSummary(cli: .claude, usage: result.usage).contains("30"))
        #expect(!MenuBarController.cliTokenSummary(cli: .claude, usage: result.usage).contains("3,000"))

        let reqDatabase = try SQLiteFixture(schema: """
        CREATE TABLE req (
            ts INTEGER, input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_write INTEGER
        );
        """)
        defer { reqDatabase.remove() }
        try reqDatabase.execute("""
        INSERT INTO req VALUES (\(try Self.epochMilliseconds("2026-11-22T18:30:00Z")), 10, 20, 3, 4);
        INSERT INTO req VALUES (\(try Self.epochMilliseconds("2026-11-21T18:30:00Z")), 1000, 2000, 3000, 4000);
        """)
        let codexProvider = LiveMenuBarSystemStatusProvider(
            tokenDatabasePaths: CLITokenDatabasePaths(codex: [reqDatabase.url]),
            referenceDate: referenceDate,
            timeZone: Self.cst,
            ssdMountPath: "/does-not-exist/SSD"
        )
        let codex = try #require(codexProvider.captureTokenStatus().usage.items.first(where: { $0.cli == .codex }))
        #expect(codex.inputTokens == 10)
        #expect(codex.outputTokens == 20)
        #expect(codex.cacheTokens == 7)
        #expect(codex.interactionCount == 1)

        let mixedDatabase = try SQLiteFixture(schema: """
        CREATE TABLE fact_turn (
            input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_creation INTEGER
        );
        CREATE TABLE turn (
            created_at TEXT, input_tokens INTEGER, output_tokens INTEGER,
            cache_read INTEGER, cache_creation INTEGER
        );
        INSERT INTO fact_turn VALUES (9000, 9000, 9000, 9000);
        INSERT INTO turn VALUES ('2026-11-22T18:30:00Z', 11, 22, 3, 4);
        INSERT INTO turn VALUES ('2026-11-21T18:30:00Z', 1000, 2000, 3000, 4000);
        """)
        defer { mixedDatabase.remove() }
        let mixedProvider = LiveMenuBarSystemStatusProvider(
            tokenDatabasePaths: CLITokenDatabasePaths(claude: [mixedDatabase.url]),
            referenceDate: referenceDate,
            timeZone: Self.cst,
            ssdMountPath: "/does-not-exist/SSD"
        )
        let mixedClaude = try #require(mixedProvider.captureTokenStatus().usage.items.first(where: { $0.cli == .claude }))
        #expect(mixedClaude.inputTokens == 11)
        #expect(mixedClaude.outputTokens == 22)
        #expect(mixedClaude.cacheTokens == 7)
        #expect(mixedClaude.interactionCount == 1)
    }

    private static func epochMilliseconds(_ raw: String) throws -> Int64 {
        let date = try #require(LiveDashboardTelemetryReader.parseISO8601Date(raw))
        return Int64(date.timeIntervalSince1970 * 1000.0)
    }
}

private struct SQLiteFixture {
    let url: URL

    init(schema: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/pew-token-alignment-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        url = root.appendingPathComponent("fixture-\(UUID().uuidString).sqlite")
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw FixtureError.openFailed
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.executeFailed
        }
    }

    func execute(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw FixtureError.openFailed
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.executeFailed
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    enum FixtureError: Error {
        case openFailed
        case executeFailed
    }
}
#endif
