import SwiftUI

// MARK: - Card affordance geometry
//
// `CardRouter` attaches the whole-card star as an OVERLAY: it floats over the
// routed view's own chrome rather than participating in card layout, so it can
// never alter a card's size / style / chrome dimensions (constitution §VI —
// the star is a content signal, not a fourth card dimension).
//
// The cost of floating is that the overlay and the card body lay out
// independently: nothing stops a renderer from putting trailing-aligned
// content directly under the control. That is exactly what happened on the
// ranking card, whose first row's value read-out sat in the star's band and
// collided with it.
//
// The reservation therefore lives in the TOKEN layer, derived from the tokens
// the overlay itself consumes, so a renderer never measures a clearance off a
// screenshot and the two can never drift apart.

public extension AIDashSpacing {

    /// Horizontal band a card must leave clear at its TOP-TRAILING corner for
    /// the whole-card star affordance.
    ///
    /// This is the star's own hit target plus the trailing inset `CardRouter`
    /// applies to it — the full width the control occupies from the card's
    /// trailing edge inward. A renderer whose topmost band carries
    /// trailing-aligned content reserves this on THAT BAND ONLY; insetting a
    /// comparative element (a bar track) would distort the scale it encodes,
    /// which is a worse defect than the collision being avoided.
    static var cardAffordanceGutter: CGFloat {
        starButtonHitTarget + AIDashSpace.s8
    }
}
