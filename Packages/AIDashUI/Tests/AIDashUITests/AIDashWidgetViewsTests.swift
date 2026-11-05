import Testing
import SwiftUI
import Foundation
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

    @Test("system cockpit accepts full gateway names")
    func cockpitUsesFullGatewayNames() {
        _ = MacSiliconCockpitWidgetView(
            snapshot: WidgetSystemSnapshot(magpieUp: true, ravenUp: true, falconUp: true)
        ).body
    }

    @Test("widget numeric display conversions clamp extreme and non-finite doubles")
    func numericDisplayConversionsAreSafe() {
        #expect(WidgetSnapshotNumeric.clampedInt(1e100) == 999_999)
        #expect(WidgetSnapshotNumeric.clampedInt(-50) == 0)
        #expect(WidgetSnapshotNumeric.clampedInt(.nan) == 0)

        let extremeBreakdown = WidgetBriefingSnapshot.TimeBreakdown(
            leadTimeMinutesP50: 1e100,
            agentMinutes: -50,
            modelMinutes: .nan
        )
        _ = EfficiencyTimeWidgetView(
            snapshot: WidgetBriefingSnapshot(timeBreakdown: extremeBreakdown)
        ).body
        _ = MacSiliconCockpitWidgetView(
            snapshot: WidgetSystemSnapshot(cpuUsage: 1e100, gpuUsage: -50, memoryUsage: .nan)
        ).body
    }

    @Test("widget localization keys are rooted and translated")
    func widgetLocalizationKeysAreComplete() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])

        for key in [
            "widgets.completed_goals",
            "widgets.efficiency.title",
            "widgets.needs_person.title",
            "widgets.spend.title"
        ] {
            let entry = try #require(strings[key] as? [String: Any], "\(key) is not rooted in strings")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for locale in ["en", "zh-Hans"] {
                let localization = try #require(localizations[locale] as? [String: Any])
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any])
                let value = try #require(stringUnit["value"] as? String)
                #expect(!value.isEmpty, "\(key) has an empty \(locale) translation")
            }
        }
    }

    private static var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AIDashUI/Resources/Localizable.xcstrings")
    }
}
