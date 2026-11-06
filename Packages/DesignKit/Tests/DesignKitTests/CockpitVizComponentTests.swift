import Testing
import SwiftUI
@testable import DesignKit

// Smoke tests for the cockpit data-viz components. These are Views, so we
// assert they construct with representative inputs (empty, single, trend,
// and out-of-range ratios) without trapping — mirroring the existing
// component-test style (construction + golden token values).
@Suite("Cockpit viz components")
struct CockpitVizComponentTests {

    @Test("Container hit target uses the platform minimum")
    @MainActor
    func containerHitTarget() {
        #if os(macOS)
        #expect(CockpitHitTarget.platformMinimum == 28)
        #else
        #expect(CockpitHitTarget.platformMinimum == 44)
        #endif

        _ = Text("Section")
            .containerHitTarget()
            .containerHitTarget(minSize: 44)
    }

    @Test("Rail chip accepts token-backed status and selection variants")
    @MainActor
    func railChip() {
        _ = RailChip("Overview")
        _ = RailChip("Healthy", icon: "checkmark", tone: .success)
        _ = RailChip("Archive", icon: "archivebox", isSelected: true)
    }

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

    @Test("SegmentedGauge preserves its default height and scales segments")
    func segmentedGaugeHeight() {
        #expect(SegmentedGauge.defaultHeight == 30)
        #expect(SegmentedGauge.litHeight(for: SegmentedGauge.defaultHeight) == 22)
        #expect(SegmentedGauge.unlitHeight(for: SegmentedGauge.defaultHeight) == 14)
        #expect(SegmentedGauge.litHeight(for: 52) == CGFloat(52) * 22 / 30)
        #expect(SegmentedGauge.unlitHeight(for: 52) == CGFloat(52) * 14 / 30)
        _ = SegmentedGauge(value: 0.5, height: 52)
    }
}
