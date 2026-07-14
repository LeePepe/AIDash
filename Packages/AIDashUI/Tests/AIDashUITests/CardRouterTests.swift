import Testing
import SwiftUI
import Foundation
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("CardRouter Tests")
struct CardRouterTests {

    // MARK: - Helpers

    private func makeCard(
        type: CardType,
        size: CardSize = .medium,
        style: CardStyle = .neutral,
        payloadJSON: Data
    ) -> CardModel {
        CardModel(id: "test-\(type.rawValue)", type: type, size: size, style: style, payloadJSON: payloadJSON)
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(value)
    }

    // MARK: - Successful routing for each CardType

    @Test("routes metric card with valid payload")
    func routesMetric() throws {
        let payload = MetricPayload(items: [.init(label: "Steps", value: 10_000, unit: "steps", trend: .up)])
        let card = makeCard(type: .metric, payloadJSON: encode(payload))
        let router = CardRouter(card: card)

        #expect(router.card.type == .metric)
        #expect(router.card.size == .medium)
        #expect(router.card.style == .neutral)
        // Verify decode succeeds (no fallback)
        let decoded = try card.type.decode(card.payloadJSON) as? MetricPayload
        #expect(decoded?.items.count == 1)
        #expect(decoded?.items.first?.label == "Steps")
    }

    @Test("routes insight card with valid payload")
    func routesInsight() throws {
        let payload = InsightPayload(title: "Insight Title", body: "Body text")
        let card = makeCard(type: .insight, size: .wide, style: .accent, payloadJSON: encode(payload))
        let router = CardRouter(card: card)

        #expect(router.card.type == .insight)
        #expect(router.card.size == .wide)
        #expect(router.card.style == .accent)
        let decoded = try card.type.decode(card.payloadJSON) as? InsightPayload
        #expect(decoded?.title == "Insight Title")
    }

    @Test("routes agentSummary card with valid payload")
    func routesAgentSummary() throws {
        let payload = AgentSummaryPayload(agentName: "TestBot", completed: [.init(title: "Task 1")])
        let card = makeCard(type: .agentSummary, payloadJSON: encode(payload))

        let decoded = try card.type.decode(card.payloadJSON) as? AgentSummaryPayload
        #expect(decoded?.agentName == "TestBot")
        #expect(decoded?.completed.count == 1)
    }

    @Test("routes todoList card with valid payload including dates")
    func routesTodoList() throws {
        let dueDate = Date(timeIntervalSince1970: 1_750_000_000)
        let payload = TodoListPayload(items: [.init(title: "Buy milk", priority: .high, due: dueDate)])
        let card = makeCard(type: .todoList, payloadJSON: encode(payload))

        // This verifies CardType.decode uses .iso8601 date strategy
        let decoded = try card.type.decode(card.payloadJSON) as? TodoListPayload
        #expect(decoded?.items.first?.title == "Buy milk")
        #expect(decoded?.items.first?.priority == .high)
        #expect(decoded?.items.first?.due != nil)
    }

    @Test("routes trending card with valid payload")
    func routesTrending() throws {
        let payload = TrendingPayload(topic: "Swift", items: [.init(title: "Concurrency", url: "https://example.com")])
        let card = makeCard(type: .trending, payloadJSON: encode(payload))

        let decoded = try card.type.decode(card.payloadJSON) as? TrendingPayload
        #expect(decoded?.topic == "Swift")
    }

    @Test("routes digest card with valid payload")
    func routesDigest() throws {
        let payload = DigestPayload(title: "Daily Digest", body: "Summary here")
        let card = makeCard(type: .digest, payloadJSON: encode(payload))

        let decoded = try card.type.decode(card.payloadJSON) as? DigestPayload
        #expect(decoded?.title == "Daily Digest")
    }

    @Test("routes sectionHeader card with valid payload")
    func routesSectionHeader() throws {
        let payload = SectionHeaderPayload(title: "Section A", subtitle: "Subtitle")
        let card = makeCard(type: .sectionHeader, payloadJSON: encode(payload))

        let decoded = try card.type.decode(card.payloadJSON) as? SectionHeaderPayload
        #expect(decoded?.title == "Section A")
        #expect(decoded?.subtitle == "Subtitle")
    }

    // MARK: - Fallback on decode failure

    @Test("renders fallback for invalid JSON")
    func fallbackOnInvalidJSON() {
        let card = makeCard(type: .metric, payloadJSON: Data("not json".utf8))
        let router = CardRouter(card: card)

        // decode must fail → fallback
        let result = try? card.type.decode(card.payloadJSON)
        #expect(result == nil)
        #expect(router.card.type == .metric)
    }

    @Test("renders fallback for empty data")
    func fallbackOnEmptyData() {
        let card = makeCard(type: .insight, payloadJSON: Data())

        let result = try? card.type.decode(card.payloadJSON)
        #expect(result == nil)
    }

    @Test("renders fallback for type-mismatched payload")
    func fallbackOnTypeMismatch() {
        // Encode a MetricPayload but declare the card as .insight
        let metricPayload = MetricPayload(items: [.init(label: "X", value: 1)])
        let encoder = JSONEncoder()
        let data = try! encoder.encode(metricPayload)
        let card = makeCard(type: .insight, payloadJSON: data)

        // InsightPayload requires "title" and "body" — MetricPayload JSON won't decode as InsightPayload
        let result = try? card.type.decode(card.payloadJSON)
        #expect(result == nil)
    }

    // MARK: - Size and style propagation

    @Test("size and style are passed through to card model")
    func sizeAndStylePropagation() {
        let payload = MetricPayload(items: [.init(label: "A", value: 1)])
        let card = makeCard(type: .metric, size: .hero, style: .warning, payloadJSON: encode(payload))
        let router = CardRouter(card: card)

        #expect(router.card.size == .hero)
        #expect(router.card.style == .warning)
    }

    @Test("all card sizes are accepted")
    func allCardSizes() {
        let payload = MetricPayload(items: [.init(label: "A", value: 1)])
        for size in CardSize.allCases {
            let card = makeCard(type: .metric, size: size, payloadJSON: encode(payload))
            let router = CardRouter(card: card)
            #expect(router.card.size == size)
        }
    }

    @Test("all card styles are accepted")
    func allCardStyles() {
        let payload = MetricPayload(items: [.init(label: "A", value: 1)])
        for style in CardStyle.allCases {
            let card = makeCard(type: .metric, style: style, payloadJSON: encode(payload))
            let router = CardRouter(card: card)
            #expect(router.card.style == style)
        }
    }

    // MARK: - Exhaustive type coverage

    @Test("every CardType has a route")
    func everyTypeRoutes() throws {
        for cardType in CardType.allCases {
            let data: Data
            switch cardType {
            case .metric:
                data = encode(MetricPayload(items: [.init(label: "L", value: 1)]))
            case .insight:
                data = encode(InsightPayload(title: "T", body: "B"))
            case .agentSummary:
                data = encode(AgentSummaryPayload(agentName: "A", completed: [.init(title: "C")]))
            case .todoList:
                data = encode(TodoListPayload(items: [.init(title: "I")]))
            case .trending:
                data = encode(TrendingPayload(topic: "T", items: [.init(title: "I", url: "u")]))
            case .digest:
                data = encode(DigestPayload(title: "T", body: "B"))
            case .sectionHeader:
                data = encode(SectionHeaderPayload(title: "H"))
            }

            let card = makeCard(type: cardType, payloadJSON: data)
            // Verify decode succeeds for every type
            let decoded = try card.type.decode(card.payloadJSON)
            #expect(decoded is CardPayloadProtocol)
        }
    }

    // MARK: - Effective size (content-derived downgrade)

    @Test("effectiveSize defaults to the authored size when omitted")
    func effectiveSizeDefaultsToAuthored() {
        let card = makeCard(
            type: .digest, size: .hero,
            payloadJSON: encode(DigestPayload(title: "T", body: "B"))
        )
        let router = CardRouter(card: card)
        #expect(router.effectiveSize == .hero)
        #expect(router.card.size == .hero)
    }

    @Test("effectiveSize is decoupled from the stored authored size")
    func effectiveSizeDecoupledFromStored() {
        // A thin digest authored `hero` that the grid resolved down to `small`:
        // the router renders at `small` while the stored card stays `hero`.
        let card = makeCard(
            type: .digest, size: .hero,
            payloadJSON: encode(DigestPayload(title: "T", body: "one line"))
        )
        let router = CardRouter(card: card, effectiveSize: .small)
        #expect(router.effectiveSize == .small)
        #expect(router.card.size == .hero) // stored card untouched
        _ = router.body // materialise — must not crash rendering at the downgraded size
    }
}
