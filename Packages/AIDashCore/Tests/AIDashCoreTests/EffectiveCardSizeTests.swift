import Foundation
import Testing
@testable import AIDashCore

// Truth table for the content-derived effective-size resolver. The resolver is
// downgrade-only: it treats the authored `size` as an upper bound and returns
// the smaller of (authored, content-justified). Metric / trending /
// sectionHeader are pass-through; collapseToList and decode-failure preserve
// the authored size.
@Suite("EffectiveCardSize")
struct EffectiveCardSizeTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private func json(_ payload: some Encodable) -> Data {
        try! encoder.encode(payload)
    }

    /// Resolve from an authored size + a payload value (encodes then resolves).
    private func resolve(
        _ type: CardType,
        _ authored: CardSize,
        _ payload: some Encodable,
        collapseToList: Bool = false
    ) -> CardSize {
        EffectiveCardSize.resolve(
            type: type,
            authored: authored,
            payloadJSON: json(payload),
            collapseToList: collapseToList
        )
    }

    private func body(_ n: Int) -> String { String(repeating: "x", count: n) }

    // MARK: - digest

    @Test("digest downgrades by section count and body length")
    func digest() {
        // 2+ sections → hero justified; a hero stays hero.
        let twoSections = DigestPayload(
            title: "t", body: body(50),
            sections: [.init(heading: "a", paragraphs: ["p"]),
                       .init(heading: "b", paragraphs: ["p"])]
        )
        #expect(resolve(.digest, .hero, twoSections) == .hero)

        // 1 section → wide justified; hero downgrades to wide.
        let oneSection = DigestPayload(
            title: "t", body: body(50),
            sections: [.init(heading: "a", paragraphs: ["p"])]
        )
        #expect(resolve(.digest, .hero, oneSection) == .wide)

        // No sections, thin body → small; hero collapses to small (the
        // "AI 使用日报 one-liner tagged hero" case).
        let thin = DigestPayload(title: "t", body: body(20))
        #expect(resolve(.digest, .hero, thin) == .small)
        #expect(resolve(.digest, .wide, thin) == .small)

        // No sections, medium-length body → medium.
        let mid = DigestPayload(title: "t", body: body(200))
        #expect(resolve(.digest, .hero, mid) == .medium)

        // No sections, long body → wide (never hero without sections).
        let long = DigestPayload(title: "t", body: body(500))
        #expect(resolve(.digest, .hero, long) == .wide)
    }

    // MARK: - insight

    @Test("insight downgrades by citations and body length")
    func insight() {
        // Citations + long body → hero justified; hero stays.
        let citedLong = InsightPayload(
            title: "t", body: body(300),
            citations: [.init(label: "a", url: "https://e.com/a")]
        )
        #expect(resolve(.insight, .hero, citedLong) == .hero)

        // Citations + short body → wide; hero downgrades to wide.
        let citedShort = InsightPayload(
            title: "t", body: body(30),
            citations: [.init(label: "a", url: "https://e.com/a")]
        )
        #expect(resolve(.insight, .hero, citedShort) == .wide)

        // No citations, short body → small (the "数据源健康 one-liner wide" case).
        let thin = InsightPayload(title: "t", body: body(20))
        #expect(resolve(.insight, .wide, thin) == .small)

        // No citations, medium body → medium.
        let mid = InsightPayload(title: "t", body: body(120))
        #expect(resolve(.insight, .wide, mid) == .medium)

        // No citations, long body → wide.
        let long = InsightPayload(title: "t", body: body(250))
        #expect(resolve(.insight, .wide, long) == .wide)
    }

    // MARK: - todoList

    @Test("todoList downgrades by item count")
    func todoList() {
        func todo(_ n: Int) -> TodoListPayload {
            TodoListPayload(items: (0..<n).map { .init(title: "item \($0)") })
        }
        #expect(resolve(.todoList, .hero, todo(1)) == .small)  // "今日规划" 1-item hero
        #expect(resolve(.todoList, .hero, todo(3)) == .medium)
        #expect(resolve(.todoList, .hero, todo(5)) == .wide)
        #expect(resolve(.todoList, .hero, todo(8)) == .hero)   // many items earn hero
    }

    // MARK: - agentSummary

    @Test("agentSummary downgrades by completed + stats count")
    func agentSummary() {
        let thin = AgentSummaryPayload(agentName: "A", completed: [.init(title: "x")])
        #expect(resolve(.agentSummary, .hero, thin) == .small)

        let mid = AgentSummaryPayload(
            agentName: "A",
            completed: [.init(title: "x"), .init(title: "y")],
            stats: [.init(label: "PRs", value: 3)]
        )
        #expect(resolve(.agentSummary, .hero, mid) == .medium)

        let rich = AgentSummaryPayload(
            agentName: "A",
            completed: (0..<5).map { .init(title: "c\($0)") }
        )
        #expect(resolve(.agentSummary, .hero, rich) == .wide)
    }

    // MARK: - invariants

    @Test("resolver only ever downgrades, never grows past authored")
    func downgradeOnly() {
        // A thin payload authored at each size never grows.
        let thin = DigestPayload(title: "t", body: body(10))
        for size in CardSize.allCases {
            let effective = resolve(.digest, size, thin)
            #expect(rank(effective) <= rank(size),
                    "digest thin @\(size) grew to \(effective)")
        }
        // An explicitly-small card stays small regardless of rich content.
        let rich = DigestPayload(
            title: "t", body: body(500),
            sections: [.init(heading: "a", paragraphs: ["p"]),
                       .init(heading: "b", paragraphs: ["p"])]
        )
        #expect(resolve(.digest, .small, rich) == .small)
    }

    @Test("metric / trending / sectionHeader are pass-through (never downgraded)")
    func passThroughTypes() {
        let metric = MetricPayload(items: [.init(label: "solo", value: 1)])
        for size in CardSize.allCases {
            #expect(resolve(.metric, size, metric) == size)
        }
        let trending = TrendingPayload(topic: "t", items: [.init(title: "x", url: "https://e.com", score: 1)])
        #expect(resolve(.trending, .hero, trending) == .hero)
        let header = SectionHeaderPayload(title: "H")
        #expect(resolve(.sectionHeader, .hero, header) == .hero)
    }

    @Test("collapseToList preserves the authored size")
    func collapseToListPreserves() {
        let thin = DigestPayload(title: "t", body: body(10))
        #expect(resolve(.digest, .hero, thin, collapseToList: true) == .hero)
    }

    @Test("undecodable payload preserves the authored size")
    func decodeFailurePreserves() {
        let garbage = Data("{ not a digest }".utf8)
        #expect(EffectiveCardSize.resolve(
            type: .digest, authored: .hero, payloadJSON: garbage) == .hero)
    }

    @Test("body-length thresholds are inclusive at the boundary")
    func thresholdBoundaries() {
        // digest medium boundary = 160: 160 → medium, 159 → small.
        #expect(resolve(.digest, .hero, DigestPayload(title: "t", body: body(160))) == .medium)
        #expect(resolve(.digest, .hero, DigestPayload(title: "t", body: body(159))) == .small)
        // digest wide boundary = 400.
        #expect(resolve(.digest, .hero, DigestPayload(title: "t", body: body(400))) == .wide)
        #expect(resolve(.digest, .hero, DigestPayload(title: "t", body: body(399))) == .medium)
    }

    // Local mirror of the resolver's private rank, for the invariant assertion.
    private func rank(_ size: CardSize) -> Int {
        switch size {
        case .small:  return 0
        case .medium: return 1
        case .wide:   return 2
        case .hero:   return 3
        }
    }
}
