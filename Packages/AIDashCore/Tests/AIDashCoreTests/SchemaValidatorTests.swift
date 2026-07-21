import Foundation
import Testing
@testable import AIDashCore

@Suite("SchemaValidator Tests")
struct SchemaValidatorTests {

    // MARK: - BriefingPut

    @Test func briefingPut_validInput_doesNotThrow() throws {
        try SchemaValidator.validateBriefingPut(date: "2026-06-24", generatedBy: "test-agent")
    }

    @Test func briefingPut_emptyDate_throwsMissingField() {
        #expect(throws: XPCError.self) {
            try SchemaValidator.validateBriefingPut(date: "", generatedBy: "agent")
        }
        do {
            try SchemaValidator.validateBriefingPut(date: "", generatedBy: "agent")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "date")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func briefingPut_invalidDate_throwsInvalidDate() {
        do {
            try SchemaValidator.validateBriefingPut(date: "not-a-date", generatedBy: "agent")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
            #expect(error.got == "not-a-date")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func briefingPut_malformedDate_throwsInvalidDate() {
        do {
            try SchemaValidator.validateBriefingPut(date: "06-24-2026", generatedBy: "agent")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - ContainerPut

    @Test func containerPut_validInput_doesNotThrow() throws {
        try SchemaValidator.validateContainerPut(
            id: "550E8400-E29B-41D4-A716-446655440000",
            briefingDate: "2026-06-24",
            title: "Morning",
            order: 0,
            layout: "auto",
            style: "neutral"
        )
    }

    @Test func containerPut_unknownLayout_throws() {
        do {
            try SchemaValidator.validateContainerPut(
                id: "550E8400-E29B-41D4-A716-446655440000",
                briefingDate: "2026-06-24",
                title: "T",
                order: 0,
                layout: "carousel",
                style: "neutral"
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_container_layout")
            #expect(error.got == "carousel")
            #expect(error.allowed != nil)
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func containerPut_invalidUUID_throws() {
        do {
            try SchemaValidator.validateContainerPut(
                id: "not-a-uuid",
                briefingDate: "2026-06-24",
                title: "T",
                order: 0,
                layout: "auto",
                style: "neutral"
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_uuid")
            #expect(error.field == "id")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func containerPut_invalidBriefingDate_throws() {
        do {
            try SchemaValidator.validateContainerPut(
                id: "550E8400-E29B-41D4-A716-446655440000",
                briefingDate: "06-24-2026",
                title: "T",
                order: 0,
                layout: "auto",
                style: "neutral"
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
            #expect(error.field == "briefingDate")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - BriefingGet

    @Test func briefingGet_validInput_doesNotThrow() throws {
        try SchemaValidator.validateBriefingGet(date: "2026-06-24")
    }

    @Test func briefingGet_emptyDate_throwsMissingField() {
        do {
            try SchemaValidator.validateBriefingGet(date: "")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "date")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func briefingGet_invalidDate_throwsInvalidDate() {
        do {
            try SchemaValidator.validateBriefingGet(date: "06-24-2026")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_date")
            #expect(error.got == "06-24-2026")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - ContainerDelete

    @Test func containerDelete_validInput_doesNotThrow() throws {
        try SchemaValidator.validateContainerDelete(id: "550E8400-E29B-41D4-A716-446655440000")
    }

    @Test func containerDelete_emptyId_throwsMissingField() {
        do {
            try SchemaValidator.validateContainerDelete(id: "")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "id")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func containerDelete_invalidUUID_throws() {
        do {
            try SchemaValidator.validateContainerDelete(id: "not-a-uuid")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_uuid")
            #expect(error.field == "id")
            #expect(error.got == "not-a-uuid")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - CardDelete

    @Test func cardDelete_validInput_doesNotThrow() throws {
        try SchemaValidator.validateCardDelete(id: "660E8400-E29B-41D4-A716-446655440000")
    }

    @Test func cardDelete_emptyId_throwsMissingField() {
        do {
            try SchemaValidator.validateCardDelete(id: "")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "id")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardDelete_invalidUUID_throws() {
        do {
            try SchemaValidator.validateCardDelete(id: "not-a-uuid")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_uuid")
            #expect(error.field == "id")
            #expect(error.got == "not-a-uuid")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - EventsPull

    @Test func eventsPull_nilCardId_doesNotThrow() throws {
        try SchemaValidator.validateEventsPull(cardId: nil)
    }

    @Test func eventsPull_validCardId_doesNotThrow() throws {
        try SchemaValidator.validateEventsPull(cardId: "550E8400-E29B-41D4-A716-446655440000")
    }

    @Test func eventsPull_invalidCardId_throws() {
        do {
            try SchemaValidator.validateEventsPull(cardId: "not-a-uuid")
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_uuid")
            #expect(error.field == "cardId")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - CardPut

    @Test func cardPut_validInput_doesNotThrow() throws {
        let payload = try JSONEncoder().encode(
            MetricPayload(items: [
                MetricPayload.Item(
                    label: "Steps",
                    value: 10000,
                    unit: "steps",
                    trend: .up
                )
            ])
        )
        try SchemaValidator.validateCardPut(
            containerId: "550E8400-E29B-41D4-A716-446655440000",
            id: "660E8400-E29B-41D4-A716-446655440000",
            type: "metric",
            size: "small",
            style: "neutral",
            payload: payload
        )
    }

    @Test func cardPut_validInsight_doesNotThrow() throws {
        let payload = try JSONEncoder().encode(
            InsightPayload(title: "Test insight", body: "Some analysis", citations: nil)
        )
        try SchemaValidator.validateCardPut(
            containerId: "550E8400-E29B-41D4-A716-446655440000",
            id: "660E8400-E29B-41D4-A716-446655440000",
            type: "insight",
            size: "medium",
            style: "neutral",
            payload: payload
        )
    }

    @Test func cardPut_validAgentSummary_doesNotThrow() throws {
        let payload = try JSONEncoder().encode(
            AgentSummaryPayload(
                agentName: "multica/test",
                completed: [AgentSummaryPayload.Completed(title: "Fixed bug", ref: nil)],
                stats: nil
            )
        )
        try SchemaValidator.validateCardPut(
            containerId: "550E8400-E29B-41D4-A716-446655440000",
            id: "660E8400-E29B-41D4-A716-446655440000",
            type: "agentSummary",
            size: "medium",
            style: "neutral",
            payload: payload
        )
    }

    @Test func cardPut_validTodoList_doesNotThrow() throws {
        let payload = try JSONEncoder().encode(
            TodoListPayload(items: [
                TodoListPayload.Item(title: "Review PRs", priority: .high, due: nil, ref: nil)
            ])
        )
        try SchemaValidator.validateCardPut(
            containerId: "550E8400-E29B-41D4-A716-446655440000",
            id: "660E8400-E29B-41D4-A716-446655440000",
            type: "todoList",
            size: "medium",
            style: "neutral",
            payload: payload
        )
    }

    @Test func cardPut_validTrending_doesNotThrow() throws {
        let payload = try JSONEncoder().encode(
            TrendingPayload(
                topic: "Swift news",
                items: [TrendingPayload.Item(title: "Swift 6.1 released", url: "https://swift.org", score: nil)]
            )
        )
        try SchemaValidator.validateCardPut(
            containerId: "550E8400-E29B-41D4-A716-446655440000",
            id: "660E8400-E29B-41D4-A716-446655440000",
            type: "trending",
            size: "wide",
            style: "neutral",
            payload: payload
        )
    }

    @Test func cardPut_validDigest_doesNotThrow() throws {
        let payload = try JSONEncoder().encode(
            DigestPayload(title: "Tuesday at a glance", body: "Overview of the day.", sections: nil)
        )
        try SchemaValidator.validateCardPut(
            containerId: "550E8400-E29B-41D4-A716-446655440000",
            id: "660E8400-E29B-41D4-A716-446655440000",
            type: "digest",
            size: "hero",
            style: "neutral",
            payload: payload
        )
    }

    @Test func cardPut_validSectionHeader_doesNotThrow() throws {
        let payload = try JSONEncoder().encode(
            SectionHeaderPayload(title: "Engineering", subtitle: nil)
        )
        try SchemaValidator.validateCardPut(
            containerId: "550E8400-E29B-41D4-A716-446655440000",
            id: "660E8400-E29B-41D4-A716-446655440000",
            type: "sectionHeader",
            size: "small",
            style: "neutral",
            payload: payload
        )
    }

    @Test func cardPut_unknownType_throws() {
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "unknown_type",
                size: "small",
                style: "neutral",
                payload: Data("{}".utf8)
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_card_type")
            #expect(error.got == "unknown_type")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_unknownSize_throws() {
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "metric",
                size: "gigantic",
                style: "neutral",
                payload: Data("{}".utf8)
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_card_size")
            #expect(error.got == "gigantic")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_unknownStyle_throws() {
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "metric",
                size: "small",
                style: "rainbow",
                payload: Data("{}".utf8)
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_card_style")
            #expect(error.got == "rainbow")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_payloadTooLarge_throws() {
        let bigPayload = Data(repeating: 0x41, count: 256 * 1024 + 1)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "metric",
                size: "small",
                style: "neutral",
                payload: bigPayload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_too_large")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_payloadDecodeFailed_throws() {
        let badPayload = Data("{\"wrong\": true}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "metric",
                size: "small",
                style: "neutral",
                payload: badPayload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "items")
        } catch {
            Issue.record("Unexpected error type")
        }
    }
}
