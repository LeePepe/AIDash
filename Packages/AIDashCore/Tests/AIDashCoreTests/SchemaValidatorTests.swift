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

    // MARK: - Payload Invariant Tests

    @Test func cardPut_metric_emptyItems_throws() {
        let payload = Data("{\"items\":[]}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "metric",
                size: "small",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "items")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_insight_emptyTitle_throws() {
        let payload = Data("{\"title\":\"\",\"body\":\"some body\"}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "insight",
                size: "medium",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "title")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_insight_emptyBody_throws() {
        let payload = Data("{\"title\":\"Good title\",\"body\":\"\"}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "insight",
                size: "medium",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "body")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_agentSummary_emptyAgentName_throws() {
        let payload = Data("""
        {"agentName":"","completed":[{"title":"Task 1"}]}
        """.utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "agentSummary",
                size: "medium",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "agentName")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_agentSummary_emptyCompleted_throws() {
        let payload = Data("""
        {"agentName":"bot","completed":[]}
        """.utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "agentSummary",
                size: "medium",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "completed")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_todoList_emptyItems_throws() {
        let payload = Data("{\"items\":[]}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "todoList",
                size: "medium",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "items")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_trending_emptyTopic_throws() {
        let payload = Data("""
        {"topic":"","items":[{"title":"News","url":"https://x.com"}]}
        """.utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "trending",
                size: "wide",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "topic")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_trending_emptyItems_throws() {
        let payload = Data("{\"topic\":\"Swift\",\"items\":[]}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "trending",
                size: "wide",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "items")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_digest_emptyTitle_throws() {
        let payload = Data("{\"title\":\"\",\"body\":\"Some digest body\"}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "digest",
                size: "hero",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "title")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_digest_emptyBody_throws() {
        let payload = Data("{\"title\":\"Digest\",\"body\":\"\"}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "digest",
                size: "hero",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "body")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_sectionHeader_emptyTitle_throws() {
        let payload = Data("{\"title\":\"\"}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "sectionHeader",
                size: "small",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "title")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func cardPut_decodeFailed_reportsFirstFailingKey() {
        // Missing required "items" key entirely — should report "items" as the failing field
        let payload = Data("{\"not_items\": 42}".utf8)
        do {
            try SchemaValidator.validateCardPut(
                containerId: "550E8400-E29B-41D4-A716-446655440000",
                id: "660E8400-E29B-41D4-A716-446655440000",
                type: "metric",
                size: "small",
                style: "neutral",
                payload: payload
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_decode_failed")
            #expect(error.field == "items")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - UserEvent

    @Test func userEvent_validInput_doesNotThrow() throws {
        try SchemaValidator.validateUserEvent(
            id: "550E8400-E29B-41D4-A716-446655440000",
            device: "iPhone17,1",
            cardId: "660E8400-E29B-41D4-A716-446655440000",
            action: "done"
        )
    }

    @Test func userEvent_unknownAction_throws() {
        do {
            try SchemaValidator.validateUserEvent(
                id: "550E8400-E29B-41D4-A716-446655440000",
                device: "iPhone17,1",
                cardId: "660E8400-E29B-41D4-A716-446655440000",
                action: "delete"
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.unknown_user_event_action")
            #expect(error.got == "delete")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func userEvent_invalidUUID_throws() {
        do {
            try SchemaValidator.validateUserEvent(
                id: "bad-uuid",
                device: "iPhone17,1",
                cardId: "660E8400-E29B-41D4-A716-446655440000",
                action: "done"
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_uuid")
            #expect(error.field == "id")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    @Test func userEvent_emptyAction_throwsMissingField() {
        do {
            try SchemaValidator.validateUserEvent(
                id: "550E8400-E29B-41D4-A716-446655440000",
                device: "iPhone17,1",
                cardId: "660E8400-E29B-41D4-A716-446655440000",
                action: ""
            )
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.missing_required_field")
            #expect(error.field == "action")
        } catch {
            Issue.record("Unexpected error type")
        }
    }

    // MARK: - PayloadSize

    @Test func payloadSize_atLimit_doesNotThrow() throws {
        let data = Data(repeating: 0x41, count: 256 * 1024)
        try SchemaValidator.validatePayloadSize(data)
    }

    @Test func payloadSize_overLimit_throws() {
        let data = Data(repeating: 0x41, count: 256 * 1024 + 1)
        do {
            try SchemaValidator.validatePayloadSize(data)
            Issue.record("Should have thrown")
        } catch let error as XPCError {
            #expect(error.code == "schema.payload_too_large")
        } catch {
            Issue.record("Unexpected error type")
        }
    }
}
