import Testing
import SwiftUI
import AIDashCore
import DesignKit
@testable import AIDashUI

@MainActor
@Suite("AIDash Widget View Tests")
struct AIDashWidgetViewsTests {
    private let briefing = WidgetBriefingSnapshot(
        needsPersonCount: 2,
        topActions: [.init(id: "a1", title: "Review TIA-93", waitingOn: "Owner")],
        completedGoalsCount: 3,
        ciPassRate: 98,
        ftrPercent: 82,
        timeBreakdown: .init(leadTimeMinutesP50: 42, agentMinutes: 10, modelMinutes: 8, ciMinutes: 12, waitMinutes: 12),
        quotas: [.init(id: "claude", provider: "Claude 7d", remainingPercent: 71)]
    )

    @Test("all four widget families are stable")
    func familyCases() {
        #expect(AIDashWidgetFamily.allCases.count == 4)
        #expect(AIDashWidgetFamily.needsPersonLinear.rawValue == "needsPersonLinear")
    }

    @Test("briefing views materialize with populated data")
    func briefingViewsMaterialize() {
        _ = NeedsPersonLinearWidgetView(snapshot: briefing).body
        _ = EfficiencyTimeWidgetView(snapshot: briefing).body
        _ = SpendQuotaWidgetView(snapshot: briefing).body
    }

    @Test("system cockpit view materializes with gateway states")
    func cockpitMaterializes() {
        let system = WidgetSystemSnapshot(
            chipSummary: "14C (10P + 4E)",
            cpuUsage: 34,
            gpuUsage: 18,
            vramSummary: "1.2 GB",
            memoryUsage: 62,
            memorySummary: "10.4 GB",
            topCPUProcess: "swift-frontend",
            topMemoryProcess: "Xcode",
            powerThermalSummary: "46°C · 1100 RPM",
            magpieUp: true,
            ravenUp: true,
            falconUp: false,
            ttftSummary: "TTFT 1.8s"
        )
        _ = MacSiliconCockpitWidgetView(snapshot: system).body
    }
}
