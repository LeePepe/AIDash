import Foundation
import Testing
@testable import AIDashCore

// Payload-invariant and value-domain validation for CardPut, plus UserEvent
// and PayloadSize checks. Split out of SchemaValidatorTests to keep each file
// within the file/type length budget.
@Suite("SchemaValidator Payload Invariant Tests")
struct SchemaValidatorPayloadInvariantTests {

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
