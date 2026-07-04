#if os(macOS)
import Testing
import Foundation
@testable import AIDashApp
import AIDashCore

/// End-to-end XPC handler tests for the briefing.* commands
/// (put / publish / get). See ``XPCTestSupport`` for the shared fixture.
@MainActor
@Suite("XPCHandlers briefing.*")
struct XPCHandlersBriefingTests {

    // MARK: - briefing.put

    @Test("briefing.put creates a new briefing")
    func briefingPutCreates() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let response = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "test-agent", published: false)
        )

        #expect(response.ok == true)
        #expect(response.error == nil)
        let result = try XPCTestSupport.decodeResult(BriefingPutResult.self, from: response)
        #expect(result.date == "2026-06-29")
        #expect(result.publishedAt == nil)
    }

    @Test("briefing.put is idempotent on the same date (upsert)")
    func briefingPutIdempotent() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        _ = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "agent-v1", published: false)
        )
        let response = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "agent-v2", published: false)
        )
        #expect(response.ok == true)
        let result = try XPCTestSupport.decodeResult(BriefingPutResult.self, from: response)
        #expect(result.date == "2026-06-29")
    }

    @Test("briefing.put with published=true sets publishedAt atomically")
    func briefingPutWithPublishedFlag() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let response = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "test", published: true)
        )
        #expect(response.ok == true)
        let result = try XPCTestSupport.decodeResult(BriefingPutResult.self, from: response)
        #expect(result.publishedAt != nil)
    }

    // MARK: - briefing.publish

    @Test("briefing.publish sets publishedAt on existing briefing")
    func briefingPublishSucceeds() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        _ = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "test", published: false)
        )
        let response = try await XPCTestSupport.send(
            handlers,
            command: "briefing.publish",
            params: BriefingPublishParams(date: "2026-06-29")
        )
        #expect(response.ok == true)
        #expect(response.error == nil)
    }

    @Test("briefing.publish on missing briefing returns briefing.not_found")
    func briefingPublishMissingReturnsError() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let response = try await XPCTestSupport.send(
            handlers,
            command: "briefing.publish",
            params: BriefingPublishParams(date: "2099-01-01")
        )
        #expect(response.ok == false)
        #expect(response.error?.code == "briefing.not_found")
    }

    // MARK: - briefing.get

    @Test("briefing.get returns persisted briefing with containers + cards")
    func briefingGetReturnsFullStructure() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let date = "2026-06-29"
        let containerId = "11111111-1111-1111-1111-111111111111"
        let cardId = "22222222-2222-2222-2222-222222222222"

        _ = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: true)
        )
        _ = try await XPCTestSupport.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: containerId, title: "Test container",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let payload = try XPCTestSupport.jsonEncoder.encode(
            SectionHeaderPayload(title: "Hello", subtitle: nil)
        )
        _ = try await XPCTestSupport.send(
            handlers,
            command: "card.put",
            params: CardPutParams(
                containerId: containerId, id: cardId, type: .sectionHeader,
                size: .wide, style: .neutral, payload: payload
            )
        )

        let response = try await XPCTestSupport.send(
            handlers,
            command: "briefing.get",
            params: BriefingGetParams(date: date)
        )
        #expect(response.ok == true)
        let result = try XPCTestSupport.decodeResult(BriefingGetResult.self, from: response)
        #expect(result.briefing.date == date)
        #expect(result.briefing.containers.count == 1)
        #expect(result.briefing.containers.first?.id == containerId)
        #expect(result.briefing.containers.first?.cards.count == 1)
        #expect(result.briefing.containers.first?.cards.first?.id == cardId)
    }

    @Test("briefing.get on missing date returns briefing.not_found")
    func briefingGetMissingReturnsError() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let response = try await XPCTestSupport.send(
            handlers,
            command: "briefing.get",
            params: BriefingGetParams(date: "2099-12-31")
        )
        #expect(response.ok == false)
        #expect(response.error?.code == "briefing.not_found")
    }
}
#endif
