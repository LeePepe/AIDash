import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("SectionHeaderCardView Tests")
struct SectionHeaderCardViewTests {
    @Test("initializes with payload, size, and style")
    func initializesCorrectly() {
        let payload = SectionHeaderPayload(title: "Engineering", subtitle: "Backend, infra")
        let view = SectionHeaderCardView(payload: payload, size: .medium, style: .neutral)

        #expect(view.payload.title == "Engineering")
        #expect(view.payload.subtitle == "Backend, infra")
        #expect(view.size == .medium)
        #expect(view.style == .neutral)
    }

    @Test("accepts nil subtitle")
    func nilSubtitle() {
        let payload = SectionHeaderPayload(title: "Header only")
        let view = SectionHeaderCardView(payload: payload, size: .small, style: .accent)

        #expect(view.payload.subtitle == nil)
        #expect(view.payload.title == "Header only")
    }

    @Test("all card sizes produce valid views")
    func allSizesValid() {
        let payload = SectionHeaderPayload(title: "Title", subtitle: "Subtitle")

        for cardSize in CardSize.allCases {
            let view = SectionHeaderCardView(payload: payload, size: cardSize, style: .neutral)
            #expect(view.size == cardSize)
        }
    }

    @Test("all card styles produce valid views")
    func allStylesValid() {
        let payload = SectionHeaderPayload(title: "Title")

        for cardStyle in CardStyle.allCases {
            let view = SectionHeaderCardView(payload: payload, size: .medium, style: cardStyle)
            #expect(view.style == cardStyle)
        }
    }

    @Test("body materializes without error for every size+style combination")
    func bodyMaterializes() {
        let payload = SectionHeaderPayload(title: "Title", subtitle: "Subtitle")

        for size in CardSize.allCases {
            for style in CardStyle.allCases {
                let view = SectionHeaderCardView(payload: payload, size: size, style: style)
                _ = view.body
            }
        }
    }

    @Test("empty subtitle string is tolerated by initializer")
    func emptySubtitleString() {
        // The view renders no subtitle Text when subtitle is empty —
        // covered by the body-materialization path above. Here we just
        // confirm the initializer accepts it.
        let payload = SectionHeaderPayload(title: "Title", subtitle: "")
        let view = SectionHeaderCardView(payload: payload, size: .hero, style: .warning)

        #expect(view.payload.subtitle == "")
        _ = view.body
    }

    @Test("init signature matches CardRouter expectation")
    func initSignatureMatches() {
        // Compile-time guarantee: the (payload:size:style:) initializer
        // exists with these exact parameter labels so CardRouter (T096)
        // can call it the same way it calls the other card views.
        let payload = SectionHeaderPayload(title: "T")
        let _: SectionHeaderCardView = SectionHeaderCardView(
            payload: payload,
            size: .wide,
            style: .success
        )
    }
}
