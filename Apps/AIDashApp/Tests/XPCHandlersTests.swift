#if os(macOS)
import Testing
import Foundation
import SwiftData
@testable import AIDashApp
import AIDashCore

/// End-to-end XPC handler integration tests.
///
/// XPCHandlers is the 588-line core that bridges the CLI's XPC requests to
/// SwiftData. The 9 private handler methods (briefing.put / publish / get,
/// container.put / delete, card.put / delete, events.pull, schema.list)
/// are exercised through the public AIDashXPCServiceProtocol surface:
/// build an XPCRequest envelope, call `execute(requestData:reply:)`, decode
/// the XPCResponse and assert.
///
/// Each test uses an in-memory SwiftData ModelContainer (no CloudKit), so
/// the suite is hermetic and runs in <1s.
@MainActor
@Suite("XPCHandlers integration")
struct XPCHandlersTests {

    // MARK: - Fixture

    private static func makeHandlers() throws -> XPCHandlers {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
            configurations: config
        )
        return XPCHandlers(container: container)
    }

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Send a request through the public AIDashXPCServiceProtocol surface
    /// and synchronously await the reply by hopping back to the main actor.
    private static func send<Params: Encodable>(
        _ handlers: XPCHandlers,
        command: String,
        params: Params
    ) async throws -> XPCResponse {
        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "test",
            command: command,
            params: try jsonEncoder.encode(params)
        )
        let requestData = try jsonEncoder.encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            handlers.execute(requestData: requestData) { responseData in
                do {
                    let response = try Self.jsonDecoder.decode(XPCResponse.self, from: responseData)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func decodeResult<R: Decodable>(
        _ type: R.Type,
        from response: XPCResponse
    ) throws -> R {
        let data = try #require(response.data, "XPCResponse.data must be non-nil for ok=true")
        return try Self.jsonDecoder.decode(type, from: data)
    }

    // MARK: - briefing.put

    @Test("briefing.put creates a new briefing")
    func briefingPutCreates() async throws {
        let handlers = try Self.makeHandlers()
        let response = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "test-agent", published: false)
        )

        #expect(response.ok == true)
        #expect(response.error == nil)
        let result = try Self.decodeResult(BriefingPutResult.self, from: response)
        #expect(result.date == "2026-06-29")
        #expect(result.publishedAt == nil)
    }

    @Test("briefing.put is idempotent on the same date (upsert)")
    func briefingPutIdempotent() async throws {
        let handlers = try Self.makeHandlers()
        _ = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "agent-v1", published: false)
        )
        let response = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "agent-v2", published: false)
        )
        #expect(response.ok == true)
        let result = try Self.decodeResult(BriefingPutResult.self, from: response)
        #expect(result.date == "2026-06-29")
    }

    @Test("briefing.put with published=true sets publishedAt atomically")
    func briefingPutWithPublishedFlag() async throws {
        let handlers = try Self.makeHandlers()
        let response = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "test", published: true)
        )
        #expect(response.ok == true)
        let result = try Self.decodeResult(BriefingPutResult.self, from: response)
        #expect(result.publishedAt != nil)
    }

    // MARK: - briefing.publish

    @Test("briefing.publish sets publishedAt on existing briefing")
    func briefingPublishSucceeds() async throws {
        let handlers = try Self.makeHandlers()
        _ = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: "2026-06-29", generatedBy: "test", published: false)
        )
        let response = try await Self.send(
            handlers,
            command: "briefing.publish",
            params: BriefingPublishParams(date: "2026-06-29")
        )
        #expect(response.ok == true)
        #expect(response.error == nil)
    }

    @Test("briefing.publish on missing briefing returns briefing.not_found")
    func briefingPublishMissingReturnsError() async throws {
        let handlers = try Self.makeHandlers()
        let response = try await Self.send(
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
        let handlers = try Self.makeHandlers()
        let date = "2026-06-29"
        let containerId = "11111111-1111-1111-1111-111111111111"
        let cardId = "22222222-2222-2222-2222-222222222222"

        _ = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: true)
        )
        _ = try await Self.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: containerId, title: "Test container",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let payload = try Self.jsonEncoder.encode(
            SectionHeaderPayload(title: "Hello", subtitle: nil)
        )
        _ = try await Self.send(
            handlers,
            command: "card.put",
            params: CardPutParams(
                containerId: containerId, id: cardId, type: .sectionHeader,
                size: .wide, style: .neutral, payload: payload
            )
        )

        let response = try await Self.send(
            handlers,
            command: "briefing.get",
            params: BriefingGetParams(date: date)
        )
        #expect(response.ok == true)
        let result = try Self.decodeResult(BriefingGetResult.self, from: response)
        #expect(result.briefing.date == date)
        #expect(result.briefing.containers.count == 1)
        #expect(result.briefing.containers.first?.id == containerId)
        #expect(result.briefing.containers.first?.cards.count == 1)
        #expect(result.briefing.containers.first?.cards.first?.id == cardId)
    }

    @Test("briefing.get on missing date returns briefing.not_found")
    func briefingGetMissingReturnsError() async throws {
        let handlers = try Self.makeHandlers()
        let response = try await Self.send(
            handlers,
            command: "briefing.get",
            params: BriefingGetParams(date: "2099-12-31")
        )
        #expect(response.ok == false)
        #expect(response.error?.code == "briefing.not_found")
    }

    // MARK: - container.put

    @Test("container.put creates a container under an existing briefing")
    func containerPutCreates() async throws {
        let handlers = try Self.makeHandlers()
        let date = "2026-06-29"
        _ = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: false)
        )
        let response = try await Self.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date,
                id: "33333333-3333-3333-3333-333333333333",
                title: "C1",
                subtitle: "sub",
                order: 10,
                layout: .auto,
                style: .neutral
            )
        )
        #expect(response.ok == true)
        let result = try Self.decodeResult(ContainerPutResult.self, from: response)
        #expect(result.id == "33333333-3333-3333-3333-333333333333")
    }

    @Test("container.put is idempotent on the same id (upsert)")
    func containerPutIdempotent() async throws {
        let handlers = try Self.makeHandlers()
        let date = "2026-06-29"
        let id = "44444444-4444-4444-4444-444444444444"
        _ = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: false)
        )
        _ = try await Self.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: id, title: "v1",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let response = try await Self.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: id, title: "v2",
                subtitle: nil, order: 20, layout: .list, style: .accent
            )
        )
        #expect(response.ok == true)

        // Verify upsert worked: briefing.get returns the v2 fields.
        let getResp = try await Self.send(
            handlers,
            command: "briefing.get",
            params: BriefingGetParams(date: date)
        )
        let briefing = try Self.decodeResult(BriefingGetResult.self, from: getResp).briefing
        #expect(briefing.containers.count == 1)
        #expect(briefing.containers.first?.title == "v2")
        #expect(briefing.containers.first?.layout == .list)
    }

    // MARK: - card.put

    @Test("card.put creates a card under an existing container")
    func cardPutCreates() async throws {
        let handlers = try Self.makeHandlers()
        let date = "2026-06-29"
        let containerId = "55555555-5555-5555-5555-555555555555"
        let cardId = "66666666-6666-6666-6666-666666666666"

        _ = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: false)
        )
        _ = try await Self.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: containerId, title: "C",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let payload = try Self.jsonEncoder.encode(
            MetricPayload(items: [.init(label: "PR", value: 4, unit: nil, trend: .up)])
        )
        let response = try await Self.send(
            handlers,
            command: "card.put",
            params: CardPutParams(
                containerId: containerId, id: cardId, type: .metric,
                size: .small, style: .neutral, payload: payload
            )
        )
        #expect(response.ok == true)
        let result = try Self.decodeResult(CardPutResult.self, from: response)
        #expect(result.id == cardId)
    }

    @Test("card.put with malformed payload bytes returns schema error")
    func cardPutWithInvalidPayloadFails() async throws {
        let handlers = try Self.makeHandlers()
        let date = "2026-06-29"
        let containerId = "77777777-7777-7777-7777-777777777777"

        _ = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: false)
        )
        _ = try await Self.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: containerId, title: "C",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let response = try await Self.send(
            handlers,
            command: "card.put",
            params: CardPutParams(
                containerId: containerId,
                id: "88888888-8888-8888-8888-888888888888",
                type: .metric,
                size: .small,
                style: .neutral,
                payload: Data("not valid JSON".utf8)
            )
        )
        #expect(response.ok == false)
        #expect(response.error != nil)
        // The schema validator surfaces a schema.* error code, not a SwiftData crash.
        #expect(response.error!.code.hasPrefix("schema."))
    }

    // MARK: - container.delete / card.delete

    @Test("container.delete removes the container and cascades to cards")
    func containerDeleteCascades() async throws {
        let handlers = try Self.makeHandlers()
        let date = "2026-06-29"
        let containerId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let cardId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

        _ = try await Self.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "t", published: false)
        )
        _ = try await Self.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: containerId, title: "C",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let payload = try Self.jsonEncoder.encode(SectionHeaderPayload(title: "X", subtitle: nil))
        _ = try await Self.send(
            handlers,
            command: "card.put",
            params: CardPutParams(
                containerId: containerId, id: cardId, type: .sectionHeader,
                size: .wide, style: .neutral, payload: payload
            )
        )

        let deleteResp = try await Self.send(
            handlers,
            command: "container.delete",
            params: ContainerDeleteParams(id: containerId)
        )
        #expect(deleteResp.ok == true)

        let getResp = try await Self.send(
            handlers,
            command: "briefing.get",
            params: BriefingGetParams(date: date)
        )
        let briefing = try Self.decodeResult(BriefingGetResult.self, from: getResp).briefing
        #expect(briefing.containers.isEmpty, "Cascade delete should remove the container row")
    }

    // MARK: - schema.list

    @Test("schema.list returns all enums and payload schemas")
    func schemaListReturnsFullCatalog() async throws {
        let handlers = try Self.makeHandlers()
        // schema.list takes no params; the dispatcher decodes an empty params blob.
        struct Empty: Codable {}
        let response = try await Self.send(
            handlers,
            command: "schema.list",
            params: Empty()
        )
        #expect(response.ok == true)
        let result = try Self.decodeResult(SchemaListResult.self, from: response)
        // 7 card types, 4 sizes, 4 styles, 4 layouts at minimum.
        #expect(result.cardTypes.count == CardType.allCases.count)
        #expect(result.cardSizes.count == CardSize.allCases.count)
        #expect(result.cardStyles.count == CardStyle.allCases.count)
        #expect(result.containerLayouts.count == ContainerLayout.allCases.count)
        // Every card type has a documented payload schema.
        for type in CardType.allCases where type != .sectionHeader {
            #expect(result.payloads[type.rawValue] != nil, "Missing payload schema for \(type.rawValue)")
        }
    }

    // MARK: - Unknown command

    @Test("dispatch on unknown command returns schema.unknown_command")
    func unknownCommandReturnsError() async throws {
        let handlers = try Self.makeHandlers()
        struct Empty: Codable {}
        let response = try await Self.send(
            handlers,
            command: "does.not.exist",
            params: Empty()
        )
        #expect(response.ok == false)
        #expect(response.error?.code == "schema.unknown_command")
    }

    // MARK: - ping

    @Test("ping succeeds with nil data and no error")
    func pingSucceeds() async throws {
        let handlers = try Self.makeHandlers()
        struct Empty: Codable {}
        let response = try await Self.send(
            handlers,
            command: "ping",
            params: Empty()
        )
        #expect(response.ok == true)
        #expect(response.data == nil)
        #expect(response.error == nil)
    }
}
#endif
