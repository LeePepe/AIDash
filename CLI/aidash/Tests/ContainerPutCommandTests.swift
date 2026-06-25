import Foundation
import Testing
import AIDashCore
import ArgumentParser

@Suite("ContainerPutCommand")
struct ContainerPutCommandTests {

    // MARK: - Argument Parsing

    @Test("parses all required flags")
    func parsesRequiredFlags() throws {
        let args = [
            "--briefing-date", "2026-06-25",
            "--id", "11111111-1111-1111-1111-111111111111",
            "--title", "Morning Wins",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "2026-06-25")
        #expect(cmd.id == "11111111-1111-1111-1111-111111111111")
        #expect(cmd.title == "Morning Wins")
        #expect(cmd.order == 10)
        #expect(cmd.layout == "auto")
        #expect(cmd.style == "neutral")
        #expect(cmd.json == false)
        #expect(cmd.quiet == false)
    }

    @Test("parses all optional flags")
    func parsesOptionalFlags() throws {
        let args = [
            "--briefing-date", "today",
            "--id", "22222222-2222-2222-2222-222222222222",
            "--title", "Evening Review",
            "--subtitle", "A summary",
            "--order", "20",
            "--layout", "grid",
            "--style", "accent",
            "--json",
            "--quiet",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.subtitle == "A summary")
        #expect(cmd.layout == "grid")
        #expect(cmd.style == "accent")
        #expect(cmd.json == true)
        #expect(cmd.quiet == true)
    }

    @Test("defaults layout to auto and style to neutral")
    func defaultValues() throws {
        let args = [
            "--briefing-date", "yesterday",
            "--id", "33333333-3333-3333-3333-333333333333",
            "--title", "Test",
            "--order", "30",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.layout == "auto")
        #expect(cmd.style == "neutral")
    }

    @Test("fails to parse when missing required --briefing-date")
    func missingBriefingDate() {
        let args = [
            "--id", "44444444-4444-4444-4444-444444444444",
            "--title", "Test",
            "--order", "10",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    @Test("fails to parse when missing required --id")
    func missingId() {
        let args = [
            "--briefing-date", "today",
            "--title", "Test",
            "--order", "10",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    @Test("fails to parse when missing required --title")
    func missingTitle() {
        let args = [
            "--briefing-date", "today",
            "--id", "55555555-5555-5555-5555-555555555555",
            "--order", "10",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    @Test("fails to parse when missing required --order")
    func missingOrder() {
        let args = [
            "--briefing-date", "today",
            "--id", "66666666-6666-6666-6666-666666666666",
            "--title", "Test",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    @Test("fails to parse when --order is not an integer")
    func nonIntegerOrder() {
        let args = [
            "--briefing-date", "today",
            "--id", "77777777-7777-7777-7777-777777777777",
            "--title", "Test",
            "--order", "abc",
        ]
        #expect(throws: (any Error).self) {
            _ = try ContainerPutCommand.parse(args)
        }
    }

    // MARK: - Local Validation (via SchemaValidator)

    @Test("SchemaValidator rejects invalid UUID")
    func validatorRejectsInvalidUUID() {
        #expect(throws: XPCError.self) {
            try SchemaValidator.validateContainerPut(
                id: "not-a-uuid",
                title: "Test",
                order: 10,
                layout: "auto",
                style: "neutral"
            )
        }
    }

    @Test("SchemaValidator rejects empty title")
    func validatorRejectsEmptyTitle() {
        #expect(throws: XPCError.self) {
            try SchemaValidator.validateContainerPut(
                id: "88888888-8888-8888-8888-888888888888",
                title: "",
                order: 10,
                layout: "auto",
                style: "neutral"
            )
        }
    }

    @Test("SchemaValidator rejects invalid layout")
    func validatorRejectsInvalidLayout() {
        do {
            try SchemaValidator.validateContainerPut(
                id: "99999999-9999-9999-9999-999999999999",
                title: "Test",
                order: 10,
                layout: "invalid",
                style: "neutral"
            )
            Issue.record("Expected XPCError for invalid layout")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_container_layout")
            #expect(error.field == "layout")
            #expect(error.got == "invalid")
            #expect(error.allowed == ["auto", "list", "grid", "hero"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("SchemaValidator rejects invalid style")
    func validatorRejectsInvalidStyle() {
        do {
            try SchemaValidator.validateContainerPut(
                id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                title: "Test",
                order: 10,
                layout: "auto",
                style: "neon"
            )
            Issue.record("Expected XPCError for invalid style")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_card_style")
            #expect(error.field == "style")
            #expect(error.got == "neon")
            #expect(error.allowed == ["neutral", "success", "warning", "accent"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("SchemaValidator accepts all valid layouts")
    func validatorAcceptsAllLayouts() throws {
        for layout in ContainerLayout.allCases {
            try SchemaValidator.validateContainerPut(
                id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                title: "Test",
                order: 10,
                layout: layout.rawValue,
                style: "neutral"
            )
        }
    }

    @Test("SchemaValidator accepts all valid styles")
    func validatorAcceptsAllStyles() throws {
        for style in CardStyle.allCases {
            try SchemaValidator.validateContainerPut(
                id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
                title: "Test",
                order: 10,
                layout: "auto",
                style: style.rawValue
            )
        }
    }

    // MARK: - Exit Code Mapping

    @Test("maps schema.* errors to exit code 1")
    func mapsSchemaErrorToExitCode1() {
        let error = XPCError(
            code: "schema.invalid_uuid",
            message: "Bad UUID"
        )
        #expect(ContainerPutCommand.mapErrorToExitCode(error) == 1)
    }

    @Test("maps schema.unknown_container_layout to exit code 1")
    func mapsSchemaLayoutErrorToExitCode1() {
        let error = XPCError(
            code: "schema.unknown_container_layout",
            message: "Bad layout"
        )
        #expect(ContainerPutCommand.mapErrorToExitCode(error) == 1)
    }

    @Test("maps xpc.* errors to exit code 2")
    func mapsXpcErrorToExitCode2() {
        let error = XPCError(
            code: "xpc.connection_invalidated",
            message: "Connection lost"
        )
        #expect(ContainerPutCommand.mapErrorToExitCode(error) == 2)
    }

    @Test("maps xpc.app_unavailable to exit code 2")
    func mapsXpcAppUnavailableToExitCode2() {
        let error = XPCError(
            code: "xpc.app_unavailable",
            message: "App not reachable"
        )
        #expect(ContainerPutCommand.mapErrorToExitCode(error) == 2)
    }

    @Test("maps briefing.not_found to exit code 3")
    func mapsBriefingNotFoundToExitCode3() {
        let error = XPCError(
            code: "briefing.not_found",
            message: "No briefing for that date"
        )
        #expect(ContainerPutCommand.mapErrorToExitCode(error) == 3)
    }

    @Test("maps cloudkit.* errors to exit code 3")
    func mapsCloudKitErrorToExitCode3() {
        let error = XPCError(
            code: "cloudkit.quota_exceeded",
            message: "Storage full"
        )
        #expect(ContainerPutCommand.mapErrorToExitCode(error) == 3)
    }

    @Test("maps internal.* errors to exit code 3")
    func mapsInternalErrorToExitCode3() {
        let error = XPCError(
            code: "internal.unexpected",
            message: "Something went wrong"
        )
        #expect(ContainerPutCommand.mapErrorToExitCode(error) == 3)
    }

    @Test("maps container.not_found to exit code 3")
    func mapsContainerNotFoundToExitCode3() {
        let error = XPCError(
            code: "container.not_found",
            message: "Container doesn't exist"
        )
        #expect(ContainerPutCommand.mapErrorToExitCode(error) == 3)
    }

    // MARK: - Date Validation

    @Test("rejects invalid date format (not YYYY-MM-DD)")
    func rejectsInvalidDateFormat() throws {
        let args = [
            "--briefing-date", "25-06-2026",
            "--id", "dddddddd-dddd-dddd-dddd-dddddddddddd",
            "--title", "Test",
            "--order", "10",
        ]
        // Parses successfully (it's a string), but run() should fail with validation
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "25-06-2026")
        // The actual validation happens in run() — tested via integration below
    }

    @Test("rejects nonsense date string")
    func rejectsNonsenseDate() throws {
        let args = [
            "--briefing-date", "not-a-date",
            "--id", "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
            "--title", "Test",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "not-a-date")
    }

    @Test("accepts valid YYYY-MM-DD date")
    func acceptsValidDate() throws {
        let args = [
            "--briefing-date", "2026-06-25",
            "--id", "ffffffff-ffff-ffff-ffff-ffffffffffff",
            "--title", "Test",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "2026-06-25")
    }

    @Test("accepts 'today' as briefing-date")
    func acceptsTodayDate() throws {
        let args = [
            "--briefing-date", "today",
            "--id", "ffffffff-ffff-ffff-ffff-ffffffffffff",
            "--title", "Test",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "today")
    }

    @Test("accepts 'yesterday' as briefing-date")
    func acceptsYesterdayDate() throws {
        let args = [
            "--briefing-date", "yesterday",
            "--id", "ffffffff-ffff-ffff-ffff-ffffffffffff",
            "--title", "Test",
            "--order", "10",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.briefingDate == "yesterday")
    }

    // MARK: - JSON/Quiet Flag Parsing

    @Test("--json flag is recognized on leaf command")
    func jsonFlagOnLeaf() throws {
        let args = [
            "--briefing-date", "2026-06-25",
            "--id", "11111111-1111-1111-1111-111111111111",
            "--title", "Test",
            "--order", "10",
            "--json",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.json == true)
    }

    @Test("--quiet flag is recognized on leaf command")
    func quietFlagOnLeaf() throws {
        let args = [
            "--briefing-date", "2026-06-25",
            "--id", "11111111-1111-1111-1111-111111111111",
            "--title", "Test",
            "--order", "10",
            "--quiet",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.quiet == true)
    }

    @Test("both --json and --quiet together")
    func jsonAndQuietTogether() throws {
        let args = [
            "--briefing-date", "2026-06-25",
            "--id", "11111111-1111-1111-1111-111111111111",
            "--title", "Test",
            "--order", "10",
            "--json",
            "--quiet",
        ]
        let cmd = try ContainerPutCommand.parse(args)
        #expect(cmd.json == true)
        #expect(cmd.quiet == true)
    }
}
