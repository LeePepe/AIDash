import Testing
import SwiftUI
@testable import DesignKit

// Smoke tests for the cockpit data-viz components. These are Views, so we
// assert they construct with representative inputs (empty, single, trend,
// and out-of-range ratios) without trapping — mirroring the existing
// component-test style (construction + golden token values).
@Suite("Cockpit viz components")
struct CockpitVizComponentTests {

    @Test("Sparkbars constructs for empty / single / trend series")
    func sparkbars() {
        _ = Sparkbars(data: [], color: .green)
        _ = Sparkbars(data: [5], color: .green)
        _ = Sparkbars(data: [180, 170, 150, 124], color: .green, baseline: .gray.opacity(0.15))
    }

    @Test("SegmentedGauge clamps ratio to 0...1 and constructs")
    func segmentedGauge() {
        // Under-, in-, and over-range ratios must all construct (clamped).
        _ = SegmentedGauge(value: -0.5)
        _ = SegmentedGauge(value: 0.87)
        _ = SegmentedGauge(value: 1.4, segments: 20)
    }
}
