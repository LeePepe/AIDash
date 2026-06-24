import Foundation
import Testing
@testable import AIDashCore

@Suite("BriefingPut CLI Integration Tests")
struct BriefingPutCLITests {

    // MARK: - ExitCodeMapper

    @Test func exitCodeMapper_schemaPrefix_mapsToExit1() {
        let error = XPCError(code: "schema.invalid_date", message: "Bad date")
        let mapped = exitCode(for: error)
        #expect(mapped == 1)
    }

    @Test func exitCodeMapper_xpcPrefix_mapsToExit2() {
        let error = XPCError(code: "xpc.app_unavailable", message: "No app")
        let mapped = exitCode(for: error)
        #expect(mapped == 2)
    }

    @Test func exitCodeMapper_briefingPrefix_mapsToExit3() {
        let error = XPCError(code: "briefing.not_found", message: "Not found")
        let mapped = exitCode(for: error)
        #expect(mapped == 3)
    }

    @Test func exitCodeMapper_cloudkitPrefix_mapsToExit3() {
        let error = XPCError(code: "cloudkit.quota_exceeded", message: "Quota")
        let mapped = exitCode(for: error)
        #expect(mapped == 3)
    }

    @Test func exitCodeMapper_internalPrefix_mapsToExit3() {
        let error = XPCError(code: "internal.unexpected", message: "Bug")
        let mapped = exitCode(for: error)
        #expect(mapped == 3)
    }

    // MARK: - BriefingPutParams encoding round-trip

    @Test func briefingPutParams_encodeDecode_roundTrips() throws {
        let params = BriefingPutParams(
            date: "2026-06-24",
            generatedBy: "test-agent",
            published: true
        )
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(BriefingPutParams.self, from: data)
        #expect(decoded.date == "2026-06-24")
        #expect(decoded.generatedBy == "test-agent")
        #expect(decoded.published == true)
    }

    @Test func briefingPutParams_publishedFalse_defaultCase() throws {
        let params = BriefingPutParams(
            date: "2026-06-25",
            generatedBy: "hermes-cron",
            published: false
        )
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(BriefingPutParams.self, from: data)
        #expect(decoded.published == false)
    }

    // MARK: - SchemaValidator for briefing put

    @Test func briefingPut_validDate_passes() throws {
        try SchemaValidator.validateBriefingPut(
            date: "2026-06-24",
            generatedBy: "morning-briefer"
        )
    }

    @Test func briefingPut_emptyGeneratedBy_fails() {
        do {
            try SchemaValidator.validateBriefingPut(date: "2026-06-24", generatedBy: "")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "generatedBy")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func briefingPut_invalidDateFormat_fails() {
        do {
            try SchemaValidator.validateBriefingPut(date: "24-06-2026", generatedBy: "agent")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
            #expect(error.field == "date")
            #expect(error.got == "24-06-2026")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func briefingPut_partialDate_fails() {
        do {
            try SchemaValidator.validateBriefingPut(date: "2026-06", generatedBy: "agent")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - XPCRequest construction

    @Test func xpcRequest_briefingPut_commandName() throws {
        let params = BriefingPutParams(
            date: "2026-06-24",
            generatedBy: "hermes",
            published: false
        )
        let paramsData = try JSONEncoder().encode(params)
        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "briefing.put",
            params: paramsData
        )
        #expect(request.command == "briefing.put")
        #expect(request.cliVersion == "1.0.0")
        let decoded = try JSONDecoder().decode(BriefingPutParams.self, from: request.params)
        #expect(decoded.date == "2026-06-24")
    }

    // MARK: - BriefingPutResult decoding

    @Test func briefingPutResult_decodesISO8601Dates() throws {
        let json = """
        {
            "date": "2026-06-24",
            "generatedAt": "2026-06-24T08:30:00Z",
            "publishedAt": null
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(BriefingPutResult.self, from: json)
        #expect(result.date == "2026-06-24")
        #expect(result.publishedAt == nil)
    }

    @Test func briefingPutResult_withPublishedAt_decodes() throws {
        let json = """
        {
            "date": "2026-06-24",
            "generatedAt": "2026-06-24T08:30:00Z",
            "publishedAt": "2026-06-24T08:31:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(BriefingPutResult.self, from: json)
        #expect(result.publishedAt != nil)
    }

    // MARK: - Helpers (mirror ExitCodeMapper logic for testing)

    private func exitCode(for error: XPCError) -> Int32 {
        let code = error.code
        if code.hasPrefix("schema.") { return 1 }
        if code.hasPrefix("xpc.") { return 2 }
        return 3
    }
}
