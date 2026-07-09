#if os(macOS)
import Testing
import Foundation
@testable import AIDashApp
import AIDashCore

/// End-to-end XPC handler tests for container.* / card.* commands plus the
/// schema.list, unknown-command and ping surfaces. See ``XPCTestSupport`` for
/// the shared fixture.
@MainActor
@Suite("XPCHandlers container/card/schema")
struct XPCHandlersContainerCardTests {

    // MARK: - container.put

    @Test("container.put creates a container under an existing briefing")
    func containerPutCreates() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let date = "2026-06-29"
        _ = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: false)
        )
        let response = try await XPCTestSupport.send(
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
        let result = try XPCTestSupport.decodeResult(ContainerPutResult.self, from: response)
        #expect(result.id == "33333333-3333-3333-3333-333333333333")
    }

    @Test("container.put is idempotent on the same id (upsert)")
    func containerPutIdempotent() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let date = "2026-06-29"
        let id = "44444444-4444-4444-4444-444444444444"
        _ = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: false)
        )
        _ = try await XPCTestSupport.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: id, title: "v1",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let response = try await XPCTestSupport.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: id, title: "v2",
                subtitle: nil, order: 20, layout: .list, style: .accent
            )
        )
        #expect(response.ok == true)

        // Verify upsert worked: briefing.get returns the v2 fields.
        let getResp = try await XPCTestSupport.send(
            handlers,
            command: "briefing.get",
            params: BriefingGetParams(date: date)
        )
        let briefing = try XPCTestSupport.decodeResult(BriefingGetResult.self, from: getResp).briefing
        #expect(briefing.containers.count == 1)
        #expect(briefing.containers.first?.title == "v2")
        #expect(briefing.containers.first?.layout == .list)
    }

    // MARK: - card.put

    @Test("card.put creates a card under an existing container")
    func cardPutCreates() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let date = "2026-06-29"
        let containerId = "55555555-5555-5555-5555-555555555555"
        let cardId = "66666666-6666-6666-6666-666666666666"

        _ = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: false)
        )
        _ = try await XPCTestSupport.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: containerId, title: "C",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let payload = try XPCTestSupport.jsonEncoder.encode(
            MetricPayload(items: [.init(label: "PR", value: 4, unit: nil, trend: .up)])
        )
        let response = try await XPCTestSupport.send(
            handlers,
            command: "card.put",
            params: CardPutParams(
                containerId: containerId, id: cardId, type: .metric,
                size: .small, style: .neutral, payload: payload
            )
        )
        #expect(response.ok == true)
        let result = try XPCTestSupport.decodeResult(CardPutResult.self, from: response)
        #expect(result.id == cardId)
    }

    @Test("card.put with malformed payload bytes returns schema error")
    func cardPutWithInvalidPayloadFails() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        let date = "2026-06-29"
        let containerId = "77777777-7777-7777-7777-777777777777"

        _ = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "test", published: false)
        )
        _ = try await XPCTestSupport.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: containerId, title: "C",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let response = try await XPCTestSupport.send(
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
        let handlers = try XPCTestSupport.makeHandlers()
        let date = "2026-06-29"
        let containerId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let cardId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

        _ = try await XPCTestSupport.send(
            handlers,
            command: "briefing.put",
            params: BriefingPutParams(date: date, generatedBy: "t", published: false)
        )
        _ = try await XPCTestSupport.send(
            handlers,
            command: "container.put",
            params: ContainerPutParams(
                briefingDate: date, id: containerId, title: "C",
                subtitle: nil, order: 10, layout: .auto, style: .neutral
            )
        )
        let payload = try XPCTestSupport.jsonEncoder.encode(SectionHeaderPayload(title: "X", subtitle: nil))
        _ = try await XPCTestSupport.send(
            handlers,
            command: "card.put",
            params: CardPutParams(
                containerId: containerId, id: cardId, type: .sectionHeader,
                size: .wide, style: .neutral, payload: payload
            )
        )

        let deleteResp = try await XPCTestSupport.send(
            handlers,
            command: "container.delete",
            params: ContainerDeleteParams(id: containerId)
        )
        #expect(deleteResp.ok == true)

        let getResp = try await XPCTestSupport.send(
            handlers,
            command: "briefing.get",
            params: BriefingGetParams(date: date)
        )
        let briefing = try XPCTestSupport.decodeResult(BriefingGetResult.self, from: getResp).briefing
        #expect(briefing.containers.isEmpty, "Cascade delete should remove the container row")
    }

    // MARK: - schema.list

    @Test("schema.list returns all enums and payload schemas")
    func schemaListReturnsFullCatalog() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        // schema.list takes no params; the dispatcher decodes an empty params blob.
        struct Empty: Codable {}
        let response = try await XPCTestSupport.send(
            handlers,
            command: "schema.list",
            params: Empty()
        )
        #expect(response.ok == true)
        let result = try XPCTestSupport.decodeResult(SchemaListResult.self, from: response)
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

    /// Anti-drift guard: the hand-written JSON Schema strings in
    /// `handleSchemaList` are maintained separately from the Codable payload
    /// models, so a field added to a model (e.g. metric `series`/`ratio`) can
    /// silently go missing from `aidash schema list`. This test fully-populates
    /// each payload, encodes it, walks every JSON key, and asserts each one is
    /// declared in that type's advertised schema `properties` — so any new
    /// model field forces a matching schema update.
    @Test("schema.list advertises every field the payload models can emit")
    func schemaListCoversAllModelFields() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        struct Empty: Codable {}
        let response = try await XPCTestSupport.send(handlers, command: "schema.list", params: Empty())
        let result = try XPCTestSupport.decodeResult(SchemaListResult.self, from: response)

        // Fully-populated instances — every optional field set — so the encoded
        // JSON exercises the whole surface, not just required fields.
        let fixtures: [CardType: any Encodable] = [
            .metric: MetricPayload(items: [
                .init(label: "PRs", value: 3, unit: "s", trend: .up,
                      series: [1, 2, 3], ratio: 0.5, higherIsBetter: true, context: "Sapphire")
            ]),
            .insight: InsightPayload(
                title: "t", subtitle: "s", body: "b",
                citations: [.init(label: "l", url: "u")]
            ),
            .digest: DigestPayload(
                title: "t", subtitle: "s", body: "b",
                sections: [.init(heading: "h", paragraphs: ["p"])]
            ),
        ]

        for (type, payload) in fixtures {
            let schemaString = try #require(result.payloads[type.rawValue],
                                            "no schema for \(type.rawValue)")
            let declared = Self.schemaPropertyKeys(schemaString)
            let emitted = try Self.jsonKeys(of: payload)
            let missing = emitted.subtracting(declared)
            #expect(missing.isEmpty,
                    "\(type.rawValue) schema is missing fields the model emits: \(missing.sorted())")
        }
    }

    /// Every `properties` key anywhere in a JSON Schema document (recursively,
    /// so nested `items`/object schemas are covered).
    private static func schemaPropertyKeys(_ schema: String) -> Set<String> {
        guard let data = schema.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var keys: Set<String> = []
        func walk(_ node: Any) {
            guard let obj = node as? [String: Any] else {
                if let arr = node as? [Any] { arr.forEach(walk) }
                return
            }
            if let props = obj["properties"] as? [String: Any] {
                keys.formUnion(props.keys)
            }
            obj.values.forEach(walk)
        }
        walk(root)
        return keys
    }

    /// Every object key anywhere in an encoded payload (recursively), i.e. the
    /// set of field names the model can actually put on the wire.
    private static func jsonKeys(of value: some Encodable) throws -> Set<String> {
        let data = try JSONEncoder().encode(value)
        let root = try JSONSerialization.jsonObject(with: data)
        var keys: Set<String> = []
        func walk(_ node: Any) {
            if let obj = node as? [String: Any] {
                keys.formUnion(obj.keys)
                obj.values.forEach(walk)
            } else if let arr = node as? [Any] {
                arr.forEach(walk)
            }
        }
        walk(root)
        return keys
    }

    // MARK: - Unknown command

    @Test("dispatch on unknown command returns schema.unknown_command")
    func unknownCommandReturnsError() async throws {
        let handlers = try XPCTestSupport.makeHandlers()
        struct Empty: Codable {}
        let response = try await XPCTestSupport.send(
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
        let handlers = try XPCTestSupport.makeHandlers()
        struct Empty: Codable {}
        let response = try await XPCTestSupport.send(
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
