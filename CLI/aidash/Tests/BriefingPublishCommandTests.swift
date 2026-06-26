import Foundation
import Testing
import AIDashCore

@Suite("BriefingPublishCommand")
struct BriefingPublishCommandTests {

    // MARK: - Date resolution

    @Test("resolves 'today' to current date in YYYY-MM-DD format")
    func resolvesToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expected = formatter.string(from: Date())

        let resolved = DateResolver.resolve("today")
        #expect(resolved == expected)
    }

    @Test("resolves 'yesterday' to previous date")
    func resolvesYesterday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let expected = formatter.string(from: yesterday)

        let resolved = DateResolver.resolve("yesterday")
        #expect(resolved == expected)
    }

    @Test("passes through YYYY-MM-DD dates unchanged")
    func passesThrough() {
        let resolved = DateResolver.resolve("2026-06-24")
        #expect(resolved == "2026-06-24")
    }

    @Test("resolution is case-insensitive")
    func caseInsensitive() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expected = formatter.string(from: Date())

        #expect(DateResolver.resolve("TODAY") == expected)
        #expect(DateResolver.resolve("Today") == expected)
    }

    // MARK: - Validation

    @Test("validateBriefingPublish accepts valid YYYY-MM-DD date")
    func validDateAccepted() throws {
        try SchemaValidator.validateBriefingPublish(date: "2026-06-24")
    }

    @Test("validateBriefingPublish rejects empty date")
    func emptyDateRejected() {
        do {
            try SchemaValidator.validateBriefingPublish(date: "")
            Issue.record("Expected XPCError for empty date")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateBriefingPublish rejects invalid date format")
    func invalidDateRejected() {
        do {
            try SchemaValidator.validateBriefingPublish(date: "not-a-date")
            Issue.record("Expected XPCError for invalid date")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
            #expect(error.field == "date")
            #expect(error.got == "not-a-date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("validateBriefingPublish rejects invalid month")
    func invalidMonthRejected() {
        do {
            try SchemaValidator.validateBriefingPublish(date: "2026-13-01")
            Issue.record("Expected XPCError for invalid month")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - ExitCodeMapper tests

@Suite("ExitCodeMapper")
struct ExitCodeMapperTests {

    @Test("schema errors map to exit 1")
    func schemaErrors() {
        let error = XPCError(code: "schema.invalid_date", message: "bad date")
        #expect(ExitCodeMapper.code(for: error) == 1)
    }

    @Test("xpc errors map to exit 2")
    func xpcErrors() {
        let error = XPCError(code: "xpc.app_unavailable", message: "no app")
        #expect(ExitCodeMapper.code(for: error) == 2)
    }

    @Test("remote errors map to exit 3")
    func remoteErrors() {
        let error = XPCError(code: "briefing.not_found", message: "no briefing")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }

    @Test("internal errors map to exit 3")
    func internalErrors() {
        let error = XPCError(code: "internal.unexpected", message: "oops")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }

    @Test("cloudkit errors map to exit 3")
    func cloudkitErrors() {
        let error = XPCError(code: "cloudkit.quota_exceeded", message: "quota")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }
}
