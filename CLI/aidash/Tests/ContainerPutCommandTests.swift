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
}
