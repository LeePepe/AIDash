import Testing
import SwiftUI
import Foundation
import AIDashCore
@testable import AIDashUI
@testable import DesignKit

// Off-screen snapshot renderer. Uses SwiftUI's ImageRenderer (no screen-
// recording permission needed) to rasterize the modernized cards with the
// sample-briefing data, so the rendered result can be inspected directly.
// Gated behind AIDASH_SNAPSHOT=1 so it never runs in the normal test gate.
@MainActor
@Suite("Snapshot render (manual)")
struct SnapshotRenderTests {

    private func render(_ view: some View, width: CGFloat, to name: String) {
        let host = view
            .frame(width: width)
            .designTheme(seed: .appleBlue, neutral: .slate)
        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        #if canImport(AppKit)
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        let url = URL(fileURLWithPath: "/tmp/aidash-shots/\(name).png")
        try? png.write(to: url)
        #endif
    }

    @Test("render OVERVIEW KPI grid + prose cards to /tmp/aidash-shots")
    func renderSample() {
        guard ProcessInfo.processInfo.environment["AIDASH_SNAPSHOT"] == "1" else { return }

        let overview = container("Overview", .grid, [
            card(.metric, .small, .neutral, #"{"items":[{"label":"PRs merged","value":12,"trend":"up","higherIsBetter":true,"context":"Sapphire · this week","series":[4,6,5,8,7,10,9,12]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Build time","value":124,"unit":"s","trend":"down","higherIsBetter":false,"context":"CI median · 7d","series":[180,170,165,150,148,140,132,124]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Coverage","value":87,"unit":"%","ratio":0.87,"context":"Sapphire"}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Open incidents","value":3,"trend":"up","higherIsBetter":false,"context":"all repos · today","series":[0,1,1,2,1,2,2,3]}]}"#),
        ])

        let today = container("Today", .grid, [
            card(.digest, .wide, .neutral, #"{"title":"A strong, incident-light day","subtitle":"All repos · yesterday","body":"Twelve PRs merged across Sapphire and Basalt, with the v9-blocking crash finally resolved. The design-system migration crossed 70%. Build times are trending down.","sections":[{"heading":"Shipped","paragraphs":["SAP-301 crash fix (unblocks v9).","Cache rework cut CI 30%."]},{"heading":"Blocking today","paragraphs":["Perf review feedback due 5pm."]}]}"#),
            card(.insight, .medium, .accent, #"{"title":"Build-cache rework is paying off","subtitle":"Sapphire CI · this week","body":"Median CI dropped 180s to 124s over the week — the single biggest developer-time win this sprint."}"#),
            card(.agentSummary, .medium, .success, #"{"agentName":"Multica","completed":[{"title":"Merged 3 Sapphire PRs"},{"title":"Regenerated changelog"}],"stats":[{"label":"PRs","value":3},{"label":"Reviews","value":9},{"label":"Hours","value":6.5}]}"#),
            card(.todoList, .medium, .warning, #"{"items":[{"title":"Reply to perf review","priority":"high"},{"title":"Decide Q3 priorities","priority":"high"},{"title":"Review changelog","priority":"medium"},{"title":"Archive branches","priority":"low"}]}"#),
        ])

        render(
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("2026-07-08").font(.largeTitle.bold())
                    Text("Published just now").font(.caption).foregroundStyle(.secondary)
                }
                ContainerView(container: overview)
                ContainerView(container: today)
            }
            .padding(24)
            .background(Color(hex: "#EDEEF2")),
            width: 1000,
            to: "render"
        )
    }

    // MARK: - In-memory model builders

    private func container(_ title: String, _ layout: ContainerLayout, _ cards: [CardModel]) -> ContainerModel {
        let c = ContainerModel(
            id: UUID().uuidString, title: title, subtitle: nil,
            order: 10, layout: layout, style: .neutral
        )
        c.cards = cards
        return c
    }

    private func card(_ type: CardType, _ size: CardSize, _ style: CardStyle, _ json: String) -> CardModel {
        CardModel(
            id: UUID().uuidString, type: type, size: size,
            style: style, payloadJSON: Data(json.utf8)
        )
    }
}
