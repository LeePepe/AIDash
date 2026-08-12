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
        (try? encoder.encode(payload)) ?? Data()
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

    // MARK: - relationship

    /// Relationship payload with the mark set the visualization requires.
    private func relationship(
        _ visualization: RelationshipVisualization,
        points: Int = 0,
        rows: Int = 0,
        columns: Int = 0,
        slopes: Int = 0
    ) -> RelationshipPayload {
        RelationshipPayload(
            title: "Cost × outcome",
            visualization: visualization,
            xAxis: .init(label: "x"),
            yAxis: .init(label: "y"),
            points: (0..<points).map { .init(label: "p\($0)", x: Double($0), y: Double($0)) },
            cells: (0..<rows).flatMap { r in
                (0..<columns).map { c in
                    .init(column: "c\(c)", row: "r\(r)", value: Double(r * 10 + c))
                }
            },
            slopes: (0..<slopes).map { .init(label: "s\($0)", before: 1, after: 2) },
            sampleSize: max(1, points + rows * columns + slopes),
            timeWindow: "7d",
            metricDefinition: "d",
            summary: "s"
        )
    }

    @Test("relationship scatter downgrades until the plot has enough points")
    func relationshipScatter() {
        // A 1-point "scatter" is a dot, not a relationship: no width earned.
        #expect(resolve(.relationship, .hero, relationship(.scatter, points: 1)) == .medium)
        #expect(resolve(.relationship, .wide, relationship(.scatter, points: 1)) == .medium)
        // 2–4 points still read fine in a medium plot.
        #expect(resolve(.relationship, .hero, relationship(.scatter, points: 2)) == .medium)
        #expect(resolve(.relationship, .wide, relationship(.scatter, points: 4)) == .medium)
        // 5+ points earn the full row — but never more than wide: relationship
        // tops out at a chart + evidence rail, which hero would over-inflate.
        #expect(resolve(.relationship, .wide, relationship(.scatter, points: 5)) == .wide)
        #expect(resolve(.relationship, .hero, relationship(.scatter, points: 5)) == .wide)
        #expect(resolve(.relationship, .hero, relationship(.scatter, points: 40)) == .wide)
    }

    @Test("relationship heatmap needs a 2×2 matrix to earn wide")
    func relationshipHeatmap() {
        // A single row or single column is a bar chart wearing a matrix
        // costume — downgrade rather than render a one-line grid at full row.
        #expect(resolve(.relationship, .hero, relationship(.heatmap, rows: 1, columns: 1)) == .medium)
        #expect(resolve(.relationship, .wide, relationship(.heatmap, rows: 1, columns: 5)) == .medium)
        #expect(resolve(.relationship, .wide, relationship(.heatmap, rows: 5, columns: 1)) == .medium)
        // 2×2 and denser is a genuine matrix.
        #expect(resolve(.relationship, .wide, relationship(.heatmap, rows: 2, columns: 2)) == .wide)
        #expect(resolve(.relationship, .hero, relationship(.heatmap, rows: 4, columns: 7)) == .wide)
    }

    @Test("relationship slope needs two or more series to earn wide")
    func relationshipSlope() {
        #expect(resolve(.relationship, .hero, relationship(.slope, slopes: 1)) == .medium)
        #expect(resolve(.relationship, .wide, relationship(.slope, slopes: 1)) == .medium)
        #expect(resolve(.relationship, .wide, relationship(.slope, slopes: 2)) == .wide)
        #expect(resolve(.relationship, .hero, relationship(.slope, slopes: 6)) == .wide)
    }

    @Test("relationship never grows an authored small/medium card")
    func relationshipNeverGrows() {
        let rich = relationship(.scatter, points: 40)
        #expect(resolve(.relationship, .small, rich) == .small)
        #expect(resolve(.relationship, .medium, rich) == .medium)
        let matrix = relationship(.heatmap, rows: 6, columns: 6)
        #expect(resolve(.relationship, .small, matrix) == .small)
        #expect(resolve(.relationship, .medium, matrix) == .medium)
        // And a sparse payload authored small stays small, not medium.
        #expect(resolve(.relationship, .small, relationship(.slope, slopes: 1)) == .small)
    }

    @Test("relationship with an empty mark set degrades to medium")
    func relationshipEmptyMarks() {
        // An empty payload cannot pass validation, but the resolver runs on
        // stored cards too and must not hand a blank chart the full row.
        #expect(resolve(.relationship, .hero, relationship(.scatter)) == .medium)
        #expect(resolve(.relationship, .wide, relationship(.heatmap)) == .medium)
        #expect(resolve(.relationship, .wide, relationship(.slope)) == .medium)
    }

    @Test("relationship keeps the authored size under collapseToList")
    func relationshipCollapseToList() {
        #expect(resolve(
            .relationship, .hero, relationship(.scatter, points: 1), collapseToList: true) == .hero)
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

    @Test("metric / trending / sectionHeader / barList / stackedBar are pass-through (never downgraded)")
    func passThroughTypes() {
        let metric = MetricPayload(items: [.init(label: "solo", value: 1)])
        for size in CardSize.allCases {
            #expect(resolve(.metric, size, metric) == size)
        }
        let trending = TrendingPayload(topic: "t", items: [.init(title: "x", url: "https://e.com", score: 1)])
        #expect(resolve(.trending, .hero, trending) == .hero)
        let header = SectionHeaderPayload(title: "H")
        #expect(resolve(.sectionHeader, .hero, header) == .hero)
        // barList / stackedBar carry a single deliberate bar; a lone item must
        // NOT shrink the authored size the way a thin digest would.
        let barList = BarListPayload(items: [.init(label: "solo", value: 1)])
        #expect(resolve(.barList, .hero, barList) == .hero)
        let stacked = StackedBarPayload(segments: [.init(label: "solo", value: 1)])
        #expect(resolve(.stackedBar, .hero, stacked) == .hero)
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
