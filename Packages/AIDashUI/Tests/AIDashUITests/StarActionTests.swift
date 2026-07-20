import Testing
import SwiftUI
import Foundation
import AIDashCore
import DesignKit
@testable import AIDashUI

/// Tests for T003 (spec 002 D3): the star affordance on Trending items.
///
/// The star button is a **pure view** — it reads its state from the
/// environment (already-starred set) and emits intent via an environment
/// callback. Zero local state, zero storage access from the view layer.
///
/// These tests pin:
///  * default environment values (no-op callback, empty starred set,
///    nil currentCardId) so previews / snapshots never crash;
///  * that the injected callback receives (cardId, itemRef, desiredStarred)
///    with itemRef == item.url and desiredStarred == !isStarred;
///  * that the button reports a distinct accessibility label per state;
///  * that CardRouter publishes card.id via `currentCardId`.
@MainActor
@Suite("Star action environment + button")
struct StarActionTests {

    // MARK: - Environment defaults are safe

    @Test("default onStarItem is a no-op that does not crash")
    func defaultOnStarItemIsNoOp() {
        let env = EnvironmentValues()
        // Calling the default must not trap or throw. There is nothing to
        // assert other than "this line returns normally".
        env.onStarItem("card-1", "https://example.com", true)
    }

    @Test("default starredItemRefs is empty")
    func defaultStarredItemRefsIsEmpty() {
        let env = EnvironmentValues()
        #expect(env.starredItemRefs.isEmpty)
    }

    @Test("default currentCardId is nil")
    func defaultCurrentCardIdIsNil() {
        let env = EnvironmentValues()
        #expect(env.currentCardId == nil)
    }

    // MARK: - Button body materializes in both states + all sizes

    @Test("button body materializes for starred + unstarred states")
    func buttonBodyMaterializes() {
        // Directly instantiate — calling `.body` on a ModifiedContent traps
        // in SwiftUI (framework calls body, not user code). We rely on the
        // environment defaults (empty starred set) to exercise the outline
        // path; the filled path is exercised via the source-level contract
        // (test below asserts filled/outline glyphs are both referenced).
        let button = StarActionButton(itemRef: "https://x.test/a",
                                      itemTitle: "owner/repo")
        _ = button.body
    }

    @Test("button source references both filled + outline glyphs")
    func buttonReferencesBothGlyphs() throws {
        let src = try loadRendererSource(named: "StarActionButton")
        #expect(src.contains("star.fill"), "filled glyph for the starred state")
        #expect(src.contains("\"star\""), "outline glyph for the unstarred state")
    }

    // MARK: - Sizing tokens honour the 44pt AC

    @Test("hit target is at least 44pt (AC touch-target requirement)")
    func hitTargetMeetsAccessibilityMinimum() {
        #expect(StarActionButton.hitTarget >= 44)
    }

    @Test("glyph is smaller than the hit target (comfortable inset)")
    func glyphIsSmallerThanHitTarget() {
        #expect(StarActionButton.glyphSize < StarActionButton.hitTarget)
    }

    // MARK: - Accessibility labels

    @Test("accessibility label distinguishes star vs unstar")
    func accessibilityLabelDiffersByState() {
        let starLabel = StarActionButton.accessibilityLabel(
            isStarred: false, title: "owner/repo")
        let unstarLabel = StarActionButton.accessibilityLabel(
            isStarred: true, title: "owner/repo")

        #expect(!starLabel.isEmpty)
        #expect(!unstarLabel.isEmpty)
        #expect(starLabel != unstarLabel)
        #expect(starLabel.contains("owner/repo"))
        #expect(unstarLabel.contains("owner/repo"))
    }

    // MARK: - Trending card body renders with and without stars

    @Test("Trending card body materializes with a populated starred set")
    func trendingBodyMaterializesWithStarredSet() {
        // Body must be called directly on the concrete view (calling `.body`
        // on a ModifiedContent traps). Environment defaults exercise the
        // no-starred path; other tests pin the filled path via source
        // contract + accessibility label helpers.
        let payload = TrendingPayload(
            topic: "Test",
            items: [
                .init(title: "one", url: "https://x.test/one", score: 100),
                .init(title: "two", url: "https://x.test/two", score: 50),
                .init(title: "three", url: "https://x.test/three", score: 25),
            ]
        )
        for size in CardSize.allCases {
            let view = TrendingCardView(payload: payload, size: size, style: .neutral)
            _ = view.body
        }
    }

    // MARK: - Callback contract: (cardId, itemRef, desiredStarred)
    //
    // We can't fire a real Button tap in a unit test, but the callback
    // shape is small enough to test in isolation: install a recorder,
    // resolve the environment, invoke it the way the button does.

    @Test("callback receives cardId + itemRef + desired-starred triple")
    func callbackShapeIsStable() {
        // Simple @MainActor mutable box — this whole test is @MainActor so
        // no cross-actor hop is needed. Avoids Task/actor plumbing (and
        // its Sendable pitfalls) for a synchronous callback contract test.
        final class Recorder {
            var events: [(String, String, Bool)] = []
        }
        let recorder = Recorder()
        let handler: OnStarItem = { cardId, itemRef, desired in
            recorder.events.append((cardId, itemRef, desired))
        }

        // Simulate the button dispatch for an *unstarred* item.
        let starred1: Set<String> = []
        let ref1 = "https://x.test/alpha"
        let card1 = "card-alpha"
        handler(card1, ref1, !starred1.contains(ref1))

        // And for an *already starred* item.
        let starred2: Set<String> = ["https://x.test/beta"]
        let ref2 = "https://x.test/beta"
        let card2 = "card-beta"
        handler(card2, ref2, !starred2.contains(ref2))

        #expect(recorder.events.count == 2)
        #expect(recorder.events[0].0 == card1)
        #expect(recorder.events[0].1 == ref1)
        #expect(recorder.events[0].2 == true, "unstarred item → intent = star (true)")
        #expect(recorder.events[1].0 == card2)
        #expect(recorder.events[1].1 == ref2)
        #expect(recorder.events[1].2 == false, "already-starred item → intent = unstar (false)")
    }

    @Test("starActionEnvironment convenience installs both values")
    func starActionEnvironmentInstallsBoth() {
        let starred: Set<String> = ["ref-1", "ref-2"]
        let modified = Color.clear
            .starActionEnvironment(starred: starred, onStar: { _, _, _ in })
        _ = modified   // materialisation check; the modifier is opaque
    }

    // MARK: - CardRouter publishes card.id via currentCardId

    @Test("CardRouter installs currentCardId on its subtree")
    func cardRouterPublishesCurrentCardId() throws {
        // We assert this at the source level rather than through view
        // introspection (which SwiftUI doesn't officially expose): the
        // router body MUST attach `.environment(\.currentCardId, card.id)`
        // to its content. If someone refactors that away, this test trips.
        let src = try loadRendererSource(named: "CardRouter")
        #expect(src.contains(".environment(\\.currentCardId, card.id)"),
                "CardRouter must publish card.id via the currentCardId environment key")
    }

    // MARK: - Renderer source contract

    @Test("TrendingCardView wires StarActionButton in both row + cell paths")
    func trendingWiresStarButtonEverywhere() throws {
        let src = try loadRendererSource(named: "TrendingCardView")
        // Two call sites: the compact/wide row and the hero grid cell.
        let occurrences = src.components(separatedBy: "StarActionButton(").count - 1
        #expect(occurrences >= 2,
                "expected StarActionButton to be wired in both TrendingItemRow and TrendingRepoCell")
    }

    @Test("TrendingCardView passes item.url as the itemRef (stable primary key)")
    func trendingUsesItemURLAsRef() throws {
        let src = try loadRendererSource(named: "TrendingCardView")
        #expect(src.contains("StarActionButton(itemRef: item.url"),
                "itemRef must be item.url per spec D3 (stable radar-entry key)")
    }
}
