import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("SectionHeaderCardView Tests")
struct SectionHeaderCardViewTests {
    private let samplePayload = SectionHeaderPayload(
        title: "Engineering",
        subtitle: "Backend, infra, tooling"
    )

    @Test("initializes with payload, size, and style")
    func initializesCorrectly() {
        let view = SectionHeaderCardView(
            payload: samplePayload,
            size: .medium,
            style: .neutral
        )

        #expect(view.payload.title == "Engineering")
        #expect(view.payload.subtitle == "Backend, infra, tooling")
        #expect(view.size == .medium)
        #expect(view.style == .neutral)
    }

    @Test("accepts all card sizes", arguments: CardSize.allCases)
    func acceptsAllSizes(size: CardSize) {
        let view = SectionHeaderCardView(
            payload: samplePayload,
            size: size,
            style: .neutral
        )

        #expect(view.size == size)
    }

    @Test("accepts all card styles", arguments: CardStyle.allCases)
    func acceptsAllStyles(style: CardStyle) {
        let view = SectionHeaderCardView(
            payload: samplePayload,
            size: .medium,
            style: style
        )

        #expect(view.style == style)
    }

    @Test("handles nil subtitle")
    func handlesNilSubtitle() {
        let payload = SectionHeaderPayload(title: "Title only")
        let view = SectionHeaderCardView(
            payload: payload,
            size: .hero,
            style: .accent
        )

        #expect(view.payload.subtitle == nil)
    }
}
